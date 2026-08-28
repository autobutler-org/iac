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
# Safe to re-run: every step checks for what it would create first.

set -euo pipefail

REPO="autobutler-org/iac"
APP_NAME="github-actions-iac"
SUBSCRIPTION="autobutler"
STATE_ACCOUNT="stautobutlertfstate"
STATE_RESOURCE_GROUP="autobutler-tfstate"
ENVIRONMENT="production"

readonly ISSUER="https://token.actions.githubusercontent.com"
readonly AUDIENCE="api://AzureADTokenExchange"

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
	existing=$(az ad app federated-credential list --id "$app_id" --query "[].subject" -o tsv 2>/dev/null || true)
	local missing=0
	while read -r subject; do
		if grep -qxF "$subject" <<<"$existing"; then
			echo "    ok      ${subject}"
		else
			echo "    MISSING ${subject}"
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

	echo "Federated credentials:"
	local existing
	existing=$(az ad app federated-credential list --id "$app_id" --query "[].subject" -o tsv 2>/dev/null || true)
	local subject name
	while read -r subject; do
		if grep -qxF "$subject" <<<"$existing"; then
			echo "  ok       ${subject}"
			continue
		fi
		name=$(credential_name_for "$subject")
		az ad app federated-credential create --id "$app_id" --parameters @- >/dev/null <<JSON
{
  "name": "${name}",
  "issuer": "${ISSUER}",
  "subject": "${subject}",
  "description": "GitHub Actions for ${REPO}",
  "audiences": ["${AUDIENCE}"]
}
JSON
		echo "  created  ${subject}"
	done < <(subjects)

	echo "Role assignments:"
	assign_role "Contributor" "/subscriptions/${subscription_id}" "$sp_object_id"

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
