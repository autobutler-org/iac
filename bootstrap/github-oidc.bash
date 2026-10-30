#!/usr/bin/env bash
#
# Creates the Entra ID app registration GitHub Actions authenticates as, using OIDC
# federation -- no client secret is created, stored, or rotated.
#
# This cannot be Bicep: app registrations and federated credentials live in Microsoft Graph,
# not ARM, and no ARM template can create one. Everything else the CI identity needs (the
# role assignments) is ARM and could have been, but splitting them across two tools for one
# logical setup step would be worse than keeping them together here.
#
# Safe to re-run: every step checks for what it would create first. create also assigns
# Role Based Access Control Administrator on the subscription, with an ABAC condition.
# Contributor cannot write role assignments, and the CI cluster needs several. The
# condition allows write and delete only for the five built-in roles that cluster's
# terraform uses. An assignment with an empty condition is not this grant. It would be
# an unconstrained RBAC administrator, and doctor reports that as missing.

set -euo pipefail

REPO="autobutler-org/iac"
APP_NAME="github-actions-iac"
SUBSCRIPTION="autobutler"
STATE_ACCOUNT="stautobutlertfstate"
STATE_RESOURCE_GROUP="autobutler-tfstate"
ENVIRONMENT="production"

readonly ISSUER="https://token.actions.githubusercontent.com"
readonly AUDIENCE="api://AzureADTokenExchange"

# Role Based Access Control Administrator. Definition id verified 2026-10-29:
#   az role definition list --name "Role Based Access Control Administrator" \
#     --query "[0].name" -o tsv
#   f58310d9-a9f6-439a-9e8d-f62e7b41a168
# The five ids in rbac_admin_condition were checked the same way, against the names
# Network Contributor, Container Registry Repository Reader, Storage Blob Data
# Contributor, Azure Kubernetes Service Cluster User Role, and Azure Kubernetes Service
# RBAC Cluster Admin. Azure returned the documented ids. None differed.
readonly RBAC_ADMIN_ROLE="Role Based Access Control Administrator"
readonly RBAC_ADMIN_CONDITION_VERSION="2.0"

usage() {
	cat <<USAGE
Create the Entra ID identity GitHub Actions uses to run terraform against Azure.

Usage:
  ${0##*/} create [options]     Create or update the app registration and role assignments
  ${0##*/} doctor [options]     Report what exists today and what is missing
  ${0##*/} -h | --help          Show this help

Every step is idempotent, so re-running 'create' after a partial failure -- or after
changing --repo or --environment -- is safe and is the intended way to fix things up.

Options:
  --repo <owner/name>        GitHub repository to trust   (default: ${REPO})
  --app-name <name>          App registration name        (default: ${APP_NAME})
  --subscription <name>      Azure subscription           (default: ${SUBSCRIPTION})
  --state-account <name>     State storage account        (default: ${STATE_ACCOUNT})
  --state-rg <name>          State resource group         (default: ${STATE_RESOURCE_GROUP})
  --environment <name>       GitHub environment to trust  (default: ${ENVIRONMENT})

What 'create' does:
  1. App registration + service principal named '${APP_NAME}'.
  2. Three federated credentials, one per subject GitHub Actions mints here:
       <prefix>:pull_request              plan.yml on a pull request
       <prefix>:ref:refs/heads/main       apply.yml on push to main
       <prefix>:environment:<environment> apply.yml's gated apply job
     <prefix> is read from GitHub, not assumed -- it may embed immutable owner and
     repository IDs (repo:owner@123/repo@456) rather than being repo:owner/repo.
  3. Contributor on the subscription, so terraform can manage resources.
  4. Storage Blob Data Contributor on the state account, so terraform can read, write and
     lease the state blob.
  5. Role Based Access Control Administrator on the subscription, with a condition that
     allows role-assignment write and delete only for Network Contributor, Container
     Registry Repository Reader, Storage Blob Data Contributor, Azure Kubernetes Service
     Cluster User Role, and Azure Kubernetes Service RBAC Cluster Admin. Re-run create
     before the first CI cluster apply, or that apply fails on its first role assignment.

Run 'make bootstrap' first -- step 4 needs the state account to exist.

Prerequisites:
  az login                   (as someone who can create app registrations and assign roles)
USAGE
}

die() {
	echo "Error: $1" >&2
	shift
	for line in "$@"; do
		echo "  $line" >&2
	done
	exit 1
}

require_tools() {
	command -v az &>/dev/null || die "the Azure CLI (az) is not installed or not in PATH" \
		"Install: brew install azure-cli" \
		"Or see:  https://learn.microsoft.com/cli/azure/install-azure-cli"

	az account show &>/dev/null || die "not logged in to Azure" "Run: az login"
}

parse_args() {
	while (($# > 0)); do
		case "$1" in
			--repo) REPO="${2:?--repo needs a value}"; shift 2 ;;
			--app-name) APP_NAME="${2:?--app-name needs a value}"; shift 2 ;;
			--subscription) SUBSCRIPTION="${2:?--subscription needs a value}"; shift 2 ;;
			--state-account) STATE_ACCOUNT="${2:?--state-account needs a value}"; shift 2 ;;
			--state-rg) STATE_RESOURCE_GROUP="${2:?--state-rg needs a value}"; shift 2 ;;
			--environment) ENVIRONMENT="${2:?--environment needs a value}"; shift 2 ;;
			*) die "unknown option '$1'" "Run '${0##*/} --help' for usage." ;;
		esac
	done
}

# The subject prefix is NOT always "repo:<owner>/<repo>". GitHub now mints immutable
# subjects for many repositories, embedding the numeric owner and repository IDs:
#
#     repo:autobutler-org@217851255/iac@1349061815:ref:refs/heads/main
#
# A credential registered with the classic prefix is then never matched, and the failure is
# an AADSTS700213 at login that names the presented subject but not the fix. Ask GitHub what
# prefix it actually uses rather than assuming; the API reports it whichever form is in play,
# and immutable subjects survive a repo or org rename, which the classic form does not.
#
# Falls back to the classic form only when the API is unreachable, and says so -- a silent
# fallback here reintroduces exactly the bug this exists to avoid.
sub_claim_prefix() {
	local prefix
	if prefix=$(gh api "repos/${REPO}/actions/oidc/customization/sub" \
		--jq '.sub_claim_prefix // empty' 2>/dev/null) && [[ -n "$prefix" ]]; then
		echo "$prefix"
		return
	fi
	echo "warning: could not read the OIDC subject prefix from GitHub; assuming 'repo:${REPO}'." >&2
	echo "         If login fails with AADSTS700213, compare the subject in that error against" >&2
	echo "         'gh api repos/${REPO}/actions/oidc/customization/sub'." >&2
	echo "repo:${REPO}"
}

subjects() {
	local prefix
	prefix=$(sub_claim_prefix)
	echo "${prefix}:pull_request"
	echo "${prefix}:ref:refs/heads/main"
	echo "${prefix}:environment:${ENVIRONMENT}"
}

# Federated credential names have to be stable across runs for this to stay idempotent, and
# they cannot contain the characters a subject uses, so derive a slug rather than reusing it.
credential_name_for() {
	case "$1" in
		*:pull_request) echo "github-pull-request" ;;
		*:ref:refs/heads/main) echo "github-main" ;;
		*:environment:*) echo "github-environment-${ENVIRONMENT}" ;;
		*) echo "github-$(echo "$1" | tr -c '[:alnum:]' '-')" ;;
	esac
}

app_id_for_name() {
	az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv 2>/dev/null
}

assign_role() {
	local role="$1" scope="$2" object_id="$3"

	if [[ -n "$(az role assignment list --assignee "$object_id" --scope "$scope" \
		--query "[?roleDefinitionName=='${role}'].id" -o tsv 2>/dev/null)" ]]; then
		echo "  ok       ${role} already assigned"
		return
	fi

	# --assignee-object-id with an explicit principal type, rather than --assignee: a
	# freshly created service principal has not finished replicating through Graph, and
	# --assignee does a lookup that fails until it has.
	az role assignment create \
		--role "$role" \
		--assignee-object-id "$object_id" \
		--assignee-principal-type ServicePrincipal \
		--scope "$scope" \
		--only-show-errors >/dev/null
	echo "  created  ${role}"
}

# The shape from the azurerm role_assignment ABAC example: ForAnyOfAnyValues:GuidEquals
# on the write/request side and on the delete/resource side. Compacted to one line so it
# can sit in the JSON body `az role assignment update` requires. Whitespace is not
# significant; doctor and create compare with it stripped.
rbac_admin_condition() {
	local guids="4d97b98b-1d4f-4787-a291-c67834d212e7"
	guids+=", b93aa761-3e63-49ed-ac28-beffa264f7ac"
	guids+=", ba92f5b4-2d11-453d-a403-e96b0029c9fe"
	guids+=", 4abbcc35-e782-43d8-92c5-2d3f1bd2253f"
	guids+=", b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b"
	printf '%s' \
		"((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'}))" \
		" OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${guids}}))" \
		" AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'}))" \
		" OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${guids}}))"
}

normalize_condition() {
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]'
}

# Empty, and the literal "null"/"None" some az tsv paths print for an absent property,
# are the same thing: no condition. An unconstrained grant must not count as done.
condition_is_empty() {
	local value="$1"
	[[ -z "$value" || "$value" == "null" || "$value" == "None" ]]
}

# assign_role cannot pass a condition. This sibling can, and a re-run stays idempotent:
# same condition prints ok, a different condition is updated in place, a missing
# assignment is created. Update rather than delete-and-create, so a failed create cannot
# leave CI with no role-assignment permission at all.
assign_constrained_rbac_admin() {
	local scope="$1" object_id="$2"
	local role="$RBAC_ADMIN_ROLE"
	local condition assignment_name current principal_type role_definition_id
	condition=$(rbac_admin_condition)

	assignment_name=$(az role assignment list --assignee "$object_id" --scope "$scope" \
		--query "[?roleDefinitionName=='${role}'] | [0].name" -o tsv 2>/dev/null || true)
	if [[ -n "$assignment_name" ]]; then
		current=$(az role assignment list --assignee "$object_id" --scope "$scope" \
			--query "[?roleDefinitionName=='${role}'] | [0].condition" -o tsv 2>/dev/null || true)
		if ! condition_is_empty "$current" \
			&& [[ "$(normalize_condition "$current")" == "$(normalize_condition "$condition")" ]]; then
			echo "  ok       ${role} already assigned with the same condition"
			return
		fi

		principal_type=$(az role assignment list --assignee "$object_id" --scope "$scope" \
			--query "[?roleDefinitionName=='${role}'] | [0].principalType" -o tsv)
		role_definition_id=$(az role assignment list --assignee "$object_id" --scope "$scope" \
			--query "[?roleDefinitionName=='${role}'] | [0].roleDefinitionId" -o tsv)

		# `az role assignment update` takes the assignment as JSON. It has no --condition
		# flag. scope and name address it; the other fields are what the PUT sends back.
		az role assignment update --role-assignment @- --only-show-errors >/dev/null <<EOF
{
  "name": "${assignment_name}",
  "scope": "${scope}",
  "principalId": "${object_id}",
  "principalType": "${principal_type}",
  "roleDefinitionId": "${role_definition_id}",
  "condition": "${condition}",
  "conditionVersion": "${RBAC_ADMIN_CONDITION_VERSION}"
}
EOF
		if condition_is_empty "$current"; then
			echo "  updated  ${role} (assignment had no condition)"
		else
			echo "  updated  ${role} condition"
		fi
		return
	fi

	az role assignment create \
		--role "$role" \
		--assignee-object-id "$object_id" \
		--assignee-principal-type ServicePrincipal \
		--scope "$scope" \
		--condition "$condition" \
		--condition-version "$RBAC_ADMIN_CONDITION_VERSION" \
		--only-show-errors >/dev/null
	echo "  created  ${role}"
}

cmd_doctor() {
	require_tools

	local subscription_id app_id sp_object_id
	subscription_id=$(az account show --subscription "$SUBSCRIPTION" --query id -o tsv)
	echo "Subscription:  ${SUBSCRIPTION} (${subscription_id})"
	echo "Repository:    ${REPO}"
	echo

	app_id=$(app_id_for_name)
	if [[ -z "$app_id" ]]; then
		echo "App registration '${APP_NAME}': MISSING"
		echo "  Run: ${0##*/} create"
		return 1
	fi
	echo "App registration '${APP_NAME}': ${app_id}"

	sp_object_id=$(az ad sp show --id "$app_id" --query id -o tsv 2>/dev/null || true)
	if [[ -z "$sp_object_id" ]]; then
		echo "  service principal: MISSING -- run '${0##*/} create'"
		return 1
	fi
	echo "  service principal: ${sp_object_id}"

	echo "  federated credentials:"
	local existing
	# Keyed by name for the same reason cmd_create is: a credential whose name is right but
	# whose subject is stale is the failure that actually happens, and reporting it as a flat
	# MISSING sends you off to create one, which then collides on the name already there.
	# Name the real problem instead.
	existing=$(az ad app federated-credential list --id "$app_id" \
		--query "[].{name:name,subject:subject}" -o tsv 2>/dev/null || true)
	local missing=0
	local name current
	while read -r subject; do
		name=$(credential_name_for "$subject")
		current=$(awk -v n="$name" -F'\t' '$1 == n { print $2 }' <<<"$existing")
		if [[ "$current" == "$subject" ]]; then
			echo "    ok      ${name}"
		elif [[ -n "$current" ]]; then
			echo "    STALE   ${name} -- subject changed; '${0##*/} create' updates it in place"
			echo "              has   ${current}"
			echo "              needs ${subject}"
			missing=1
		else
			echo "    MISSING ${name}  ${subject}"
			missing=1
		fi
	done < <(subjects)

	echo "  role assignments:"
	local sub_scope="/subscriptions/${subscription_id}"
	local state_scope="${sub_scope}/resourceGroups/${STATE_RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STATE_ACCOUNT}"
	local role
	for role in "Contributor|${sub_scope}" "Storage Blob Data Contributor|${state_scope}"; do
		local name="${role%%|*}" scope="${role#*|}"
		if [[ -n "$(az role assignment list --assignee "$sp_object_id" --scope "$scope" \
			--query "[?roleDefinitionName=='${name}'].id" -o tsv 2>/dev/null)" ]]; then
			echo "    ok      ${name}"
		else
			echo "    MISSING ${name}"
			missing=1
		fi
	done

	# Present with an empty condition is MISSING on purpose. That assignment would be an
	# unconstrained RBAC administrator, which is not the grant this script leaves behind.
	local rbac_name rbac_condition
	rbac_name=$(az role assignment list --assignee "$sp_object_id" --scope "$sub_scope" \
		--query "[?roleDefinitionName=='${RBAC_ADMIN_ROLE}'] | [0].name" -o tsv 2>/dev/null || true)
	rbac_condition=$(az role assignment list --assignee "$sp_object_id" --scope "$sub_scope" \
		--query "[?roleDefinitionName=='${RBAC_ADMIN_ROLE}'] | [0].condition" -o tsv 2>/dev/null || true)
	if [[ -z "$rbac_name" ]] || condition_is_empty "$rbac_condition"; then
		echo "    MISSING ${RBAC_ADMIN_ROLE}"
		missing=1
	elif [[ "$(normalize_condition "$rbac_condition")" == "$(normalize_condition "$(rbac_admin_condition)")" ]]; then
		echo "    ok      ${RBAC_ADMIN_ROLE}"
	else
		echo "    STALE   ${RBAC_ADMIN_ROLE} -- condition differs; '${0##*/} create' updates it"
		missing=1
	fi

	if ((missing)); then
		echo
		echo "Something is missing. Run: ${0##*/} create"
		return 1
	fi
	echo
	echo "Everything is in place."
	print_variables "$app_id" "$(az account show --subscription "$SUBSCRIPTION" --query tenantId -o tsv)" "$subscription_id"
}

print_variables() {
	local app_id="$1" tenant_id="$2" subscription_id="$3"
	cat <<VARS

Set these as repository *variables* (not secrets -- none of them is sensitive, and OIDC
means there is no client secret at all):

  gh variable set AZURE_CLIENT_ID --repo ${REPO} --body ${app_id}
  gh variable set AZURE_TENANT_ID --repo ${REPO} --body ${tenant_id}
  gh variable set AZURE_SUBSCRIPTION_ID --repo ${REPO} --body ${subscription_id}

Without gh, add them by hand at:
  https://github.com/${REPO}/settings/variables/actions
VARS
}

cmd_create() {
	require_tools

	local subscription_id tenant_id
	subscription_id=$(az account show --subscription "$SUBSCRIPTION" --query id -o tsv)
	tenant_id=$(az account show --subscription "$SUBSCRIPTION" --query tenantId -o tsv)

	echo "Subscription:  ${SUBSCRIPTION} (${subscription_id})"
	echo "Repository:    ${REPO}"
	echo

	echo "App registration '${APP_NAME}':"
	local app_id
	app_id=$(app_id_for_name)
	if [[ -n "$app_id" ]]; then
		echo "  ok       already exists (${app_id})"
	else
		app_id=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
		echo "  created  ${app_id}"
	fi

	local sp_object_id
	sp_object_id=$(az ad sp show --id "$app_id" --query id -o tsv 2>/dev/null || true)
	if [[ -n "$sp_object_id" ]]; then
		echo "  ok       service principal already exists (${sp_object_id})"
	else
		sp_object_id=$(az ad sp create --id "$app_id" --query id -o tsv)
		echo "  created  service principal ${sp_object_id}"
	fi

	# Keyed by NAME, not by subject. The name is the credential's stable identity -- one per
	# role this repo mints -- while the subject is a value that can legitimately change under
	# it, which is exactly what happened when GitHub moved this repo to immutable subjects.
	# Matching on subject alone reports "missing", tries to create, and collides on the name
	# that is already there:
	#
	#     ERROR: FederatedIdentityCredential with name github-pull-request already exists.
	#
	# So: absent by name -> create; present with the wrong subject -> update it in place.
	# Update rather than delete-and-recreate, so a transient Graph failure cannot leave the
	# app with no credential for a role at all.
	echo "Federated credentials:"
	local existing
	existing=$(az ad app federated-credential list --id "$app_id" \
		--query "[].{name:name,subject:subject}" -o tsv 2>/dev/null || true)
	local subject name current
	while read -r subject; do
		name=$(credential_name_for "$subject")
		current=$(awk -v n="$name" -F'\t' '$1 == n { print $2 }' <<<"$existing")

		if [[ "$current" == "$subject" ]]; then
			echo "  ok       ${name}  ${subject}"
			continue
		fi

		if [[ -n "$current" ]]; then
			az ad app federated-credential update --id "$app_id" --federated-credential-id "$name" \
				--parameters @- >/dev/null <<JSON
{
  "name": "${name}",
  "issuer": "${ISSUER}",
  "subject": "${subject}",
  "description": "GitHub Actions for ${REPO}",
  "audiences": ["${AUDIENCE}"]
}
JSON
			echo "  updated  ${name}"
			echo "             was ${current}"
			echo "             now ${subject}"
			continue
		fi

		az ad app federated-credential create --id "$app_id" --parameters @- >/dev/null <<JSON
{
  "name": "${name}",
  "issuer": "${ISSUER}",
  "subject": "${subject}",
  "description": "GitHub Actions for ${REPO}",
  "audiences": ["${AUDIENCE}"]
}
JSON
		echo "  created  ${name}  ${subject}"
	done < <(subjects)

	echo "Role assignments:"
	assign_role "Contributor" "/subscriptions/${subscription_id}" "$sp_object_id"
	assign_constrained_rbac_admin "/subscriptions/${subscription_id}" "$sp_object_id"

	local state_scope="/subscriptions/${subscription_id}/resourceGroups/${STATE_RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STATE_ACCOUNT}"
	if az storage account show -n "$STATE_ACCOUNT" -g "$STATE_RESOURCE_GROUP" \
		--subscription "$subscription_id" &>/dev/null; then
		assign_role "Storage Blob Data Contributor" "$state_scope" "$sp_object_id"
	else
		echo "  SKIPPED  Storage Blob Data Contributor -- state account '${STATE_ACCOUNT}' does not exist yet"
		echo "           Run 'make bootstrap' to create it, then re-run this script."
	fi

	print_variables "$app_id" "$tenant_id" "$subscription_id"
}

main() {
	local command="${1:-}"
	[[ $# -gt 0 ]] && shift || true

	case "$command" in
		create) parse_args "$@"; cmd_create ;;
		doctor) parse_args "$@"; cmd_doctor ;;
		-h|--help|help) usage ;;
		"") usage; exit 1 ;;
		*) die "unknown command '${command}'" "Run '${0##*/} --help' for usage." ;;
	esac
}

main "$@"
