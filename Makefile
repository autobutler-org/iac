SHELL := bash
.SHELLFLAGS := -e -o pipefail -c
.DEFAULT_GOAL := help
.NOTPARALLEL:
.ONESHELL:
.PHONY: $(MAKECMDGOALS) # this Makefile is a script runner, not a build system
.SILENT: # use `make SHELL="bash -x"` to see the commands
MAKEFLAGS += --no-print-directory # nested make calls

# Every recipe here is written as a single bash script -- multi-line `if`, shell variables
# that persist across lines -- which only works because of .ONESHELL:. That needs GNU Make
# 3.82+, and macOS ships 3.81 as /usr/bin/make, where the recipes fall apart line by line
# with a syntax error that says nothing about the cause. Fail with the fix instead.
ifeq ($(filter oneshell,$(.FEATURES)),)
$(error GNU Make 3.82+ required, found $(MAKE_VERSION). On macOS: `brew install make` then use `gmake`)
endif

# Which subscription to act on. Every directory under azure/ is one Azure subscription and
# holds exactly one root module, so the subscription name IS the terraform directory.
# There is one subscription today, so it is also the default and `make plan` just works.
SUBSCRIPTION ?= autobutler
TF_DIR := azure/$(SUBSCRIPTION)
PLANFILE := planfile.tfplan

# The bootstrap deployment is subscription-scoped, so it needs a location for the
# deployment record itself even though the resources carry their own.
BOOTSTRAP_SUB := autobutler
BOOTSTRAP_LOCATION ?= eastus
BOOTSTRAP_TEMPLATE := bootstrap/main.bicep
BOOTSTRAP_PARAMS := bootstrap/main.bicepparam

EXTRA_TF_ARGS ?=
EXTRA_TFLINT_ARGS ?=

# The azurerm provider reads ARM_SUBSCRIPTION_ID natively, so pointing terraform at the
# right subscription needs no terraform variable and no GUID committed to the repo: the
# directory name is the source of truth, and `az` resolves it. A root module in
# azure/<sub>/ cannot silently apply to another subscription, because nothing but the
# directory name decides.
define arm_subscription
export ARM_SUBSCRIPTION_ID=$$(az account show --subscription '$(SUBSCRIPTION)' --query id -o tsv)
if [[ -z "$$ARM_SUBSCRIPTION_ID" ]]; then
	echo "Error: could not resolve subscription '$(SUBSCRIPTION)'" >&2
	echo "  Check that it exists and is enabled: az account list --all -o table" >&2
	exit 1
fi
endef

##@ Commands

init: subscription-required want-terraform want-az az-login ## Init terraform
	echo "[$@] $(TF_DIR)"
	$(arm_subscription)

	set +e
	terraform -chdir=$(TF_DIR) init -reconfigure $(EXTRA_TF_ARGS)
	exit_code=$$?
	set -e
	if ((exit_code != 0)); then
		echo "[$@] $(TF_DIR) init failed, deleting .terraform directory"
		find $(TF_DIR)/.terraform -ls -delete
		exit $$exit_code
	fi

plan: subscription-required want-terraform want-az az-login ## Plan changes, writing planfile.tfplan
	echo "[$@] $(TF_DIR)"
	$(arm_subscription)

	# -lock=false unconditionally. This Makefile is for local use only, and a local plan is
	# read-only -- it has no business holding the blob lease that a CI apply needs, and a
	# developer planning at their desk should not be able to block a merge from applying.
	# It also means a plan works for a principal with only read access to the state blob:
	# taking the lease requires write, breaking it requires more.
	#
	# The apply targets deliberately do NOT pass it. An apply must lock.
	set +e
	terraform -chdir=$(TF_DIR) plan -lock=false -out=$(PLANFILE) $(EXTRA_TF_ARGS)
	exit_code=$$?
	set -e
	if ((exit_code == 1)); then
		# 1 = a real terraform error. A stale planfile is worse than none.
		echo "[$@] $(TF_DIR) plan failed (exit code: $$exit_code)"
		rm -fv $(TF_DIR)/$(PLANFILE)
		exit $$exit_code
	elif ((exit_code == 2)); then
		# 2 = -detailed-exitcode "changes present". Expected for drift detection, and the
		# planfile is the useful output, so keep it. Do not read a 2 as a broken plan.
		echo "[$@] $(TF_DIR) plan detected changes (exit code: $$exit_code)"
		exit $$exit_code
	fi

apply-from-source: subscription-required want-terraform want-az az-login ## Apply from source
	echo "[$@] $(TF_DIR)"
	$(arm_subscription)

	terraform -chdir=$(TF_DIR) apply $(EXTRA_TF_ARGS)

apply-from-planfile: subscription-required want-terraform want-az az-login ## Apply from the planfile
	echo "[$@] $(TF_DIR)"

	if [[ ! -f "$(TF_DIR)/$(PLANFILE)" ]]; then
		echo "[$@] $(TF_DIR) has no planfile, run 'make plan SUBSCRIPTION=$(SUBSCRIPTION)' first"
		exit 1
	fi
	$(arm_subscription)

	terraform -chdir=$(TF_DIR) apply $(EXTRA_TF_ARGS) $(PLANFILE)

plan/show: subscription-required want-terraform ## Print the planfile in human-readable form
	if [[ ! -f "$(TF_DIR)/$(PLANFILE)" ]]; then
		echo "[$@] $(TF_DIR) has no planfile, run 'make plan' first"
		exit 1
	fi
	# Reads the planfile only -- no state, no credentials. CI pipes this into the PR's job
	# summary, because a planfile artifact is unreadable to a human reviewer.
	terraform -chdir=$(TF_DIR) show -no-color $(PLANFILE)

refresh: ## Reconcile state with reality, changing nothing else
	$(MAKE) apply-from-source EXTRA_TF_ARGS="-refresh-only $(EXTRA_TF_ARGS)"

destroy: subscription-required want-terraform want-az az-login ## Destroy everything in the subscription's state
	echo "[$@] $(TF_DIR)"
	$(arm_subscription)

	terraform -chdir=$(TF_DIR) destroy $(EXTRA_TF_ARGS)

validate: subscription-required want-terraform ## Validate the configuration (needs `make init` first)
	echo "[$@] $(TF_DIR)"
	terraform -chdir=$(TF_DIR) validate $(EXTRA_TF_ARGS)

output: subscription-required want-terraform want-az az-login ## Show terraform outputs
	echo "[$@] $(TF_DIR)"
	$(arm_subscription)

	terraform -chdir=$(TF_DIR) output $(EXTRA_TF_ARGS)

import-resource: subscription-required want-terraform want-az az-login env-RESOURCE_ID env-RESOURCE_PATH ## Import one existing resource into state
	echo "[$@] $(TF_DIR)"
	$(arm_subscription)

	terraform -chdir=$(TF_DIR) import '$(RESOURCE_PATH)' '$(RESOURCE_ID)'

generate-resources-from-imports: ## Draft resource blocks for the import blocks in imports.tf
	$(MAKE) plan EXTRA_TF_ARGS="-generate-config-out=generated.tf $(EXTRA_TF_ARGS)"

##@ Bootstrap

bootstrap/whatif: want-az az-login ## Preview the terraform state backend deployment
	echo "[$@] $(BOOTSTRAP_TEMPLATE)"
	az deployment sub what-if \
		--subscription $(BOOTSTRAP_SUB) \
		--location $(BOOTSTRAP_LOCATION) \
		--template-file $(BOOTSTRAP_TEMPLATE) \
		--parameters $(BOOTSTRAP_PARAMS)

bootstrap: want-az az-login ## Deploy the terraform state backend (run once, before any stack)
	echo "[$@] $(BOOTSTRAP_TEMPLATE)"
	az deployment sub create \
		--subscription $(BOOTSTRAP_SUB) \
		--location $(BOOTSTRAP_LOCATION) \
		--template-file $(BOOTSTRAP_TEMPLATE) \
		--parameters $(BOOTSTRAP_PARAMS) \
		--query properties.outputs \
		-o json

	echo
	echo "[$@] state backend is up. Every root module's backend.tf already points at it;"
	echo "[$@] run 'make init' to connect it."

##@ Checks

check: check/format check/lint check/bicep check/validate ## Everything CI checks, in one target

check/format: want-terraform ## Fail if any HCL is unformatted
	echo "[$@] azure/ modules/"
	terraform fmt -recursive -check -diff azure/ modules/

check/lint: want-tflint ## Run tflint over every root module and shared module
	echo "[$@] azure/ modules/"
	# --recursive from the repo root so both azure/ and modules/ are covered. --config has
	# to be absolute: with --recursive tflint resolves it per directory.
	tflint --config=$(PWD)/.tflint.hcl --init
	tflint --config=$(PWD)/.tflint.hcl --recursive $(EXTRA_TFLINT_ARGS)

check/bicep: want-az ## Fail if the bootstrap template does not compile
	echo "[$@] $(BOOTSTRAP_TEMPLATE)"
	az bicep build --file $(BOOTSTRAP_TEMPLATE) --stdout >/dev/null

check/validate: subscription-required want-terraform ## Validate with no Azure credentials (what CI runs)
	echo "[$@] $(TF_DIR)"
	# validate needs provider schemas, so it needs an init -- but -backend=false means that
	# init reads no state, contacts no storage account and needs no credentials at all. That
	# is the property .github/workflows/check.yml is built on: a PR from a fork, or any run
	# with no Azure identity, still gets format, lint and validate.
	terraform -chdir=$(TF_DIR) init -backend=false -input=false >/dev/null
	terraform -chdir=$(TF_DIR) validate $(EXTRA_TF_ARGS)

fix: fix/format fix/lint ## Fix what can be fixed automatically

fix/format: format ## Alias for format

fix/lint: ## Apply tflint's automatic fixes
	$(MAKE) check/lint EXTRA_TFLINT_ARGS="--fix $(EXTRA_TFLINT_ARGS)"

format: want-terraform ## Rewrite all HCL in canonical format
	echo "[$@] azure/ modules/"
	terraform fmt -recursive azure/ modules/

##@ Helpers

subscriptions: ## List the subscriptions available to SUBSCRIPTION=
	echo "Subscriptions:"
	find azure -mindepth 2 -maxdepth 2 -name backend.tf 2>/dev/null \
		| sed -e 's|^azure/||' -e 's|/backend.tf$$||' \
		| sort \
		| sed 's/^/  /'

lock: subscription-required want-terraform ## Regenerate the provider lock for all four supported platforms
	# A lock file records provider hashes per platform, and terraform only records the
	# platform it ran on. A lock generated on a developer's darwin_arm64 laptop fails
	# `terraform init` on CI's linux_amd64 runners with a checksum mismatch, so the lock has
	# to cover every platform anyone inits on.
	#
	# -backend=false: locking providers is offline work as far as state is concerned, and
	# this has to run before `make bootstrap` has created the backend.
	terraform -chdir=$(TF_DIR) init -backend=false -input=false >/dev/null
	terraform -chdir=$(TF_DIR) providers lock \
		-platform=linux_amd64 \
		-platform=linux_arm64 \
		-platform=darwin_amd64 \
		-platform=darwin_arm64

clean: ## Remove the subscription's terraform working directory and planfile
	echo "[$@] $(TF_DIR)"
	rm -rf $(TF_DIR)/.terraform
	rm -f $(TF_DIR)/$(PLANFILE)

subscription-required:
	if [[ ! -d "$(TF_DIR)" ]]; then
		echo "Error: no such subscription '$(SUBSCRIPTION)' (looked in $(TF_DIR))" >&2
		echo >&2
		$(MAKE) subscriptions >&2
		echo >&2
		echo "For example:" >&2
		echo "  make $(firstword $(MAKECMDGOALS)) SUBSCRIPTION=autobutler" >&2
		exit 1
	fi

az-login: want-az
	if ! az account show &>/dev/null; then
		echo "Error: not logged in to Azure" >&2
		echo "  Run: az login" >&2
		exit 1
	fi

env-%:
	: $${$*?Environment variable $* not set. See the README.}

# A missing tool should say how to get it, not just that it is missing.
want-%:
	if ! command -v $* &>/dev/null; then
		echo "Error: $* is not installed or not in PATH" >&2
		case '$*' in
			terraform) echo "  Install: brew install terraform" >&2 ;;
			tflint)    echo "  Install: brew install tflint" >&2 ;;
			az)        echo "  Install: brew install azure-cli" >&2 ;;
			jq)        echo "  Install: brew install jq" >&2 ;;
			*)         echo "  No install hint recorded for $*. Add one to the want-% rule." >&2 ;;
		esac
		exit 1
	fi

help: ## Display this help
	awk '
		BEGIN { FS = ":.*##"; printf "Usage:\n  make \033[36m<target>\033[0m \033[90m[SUBSCRIPTION=<name>]\033[0m\n" }
		END { printf "\nDefault SUBSCRIPTION is \033[36mautobutler\033[0m.\n" }
		/^[a-zA-Z_\/-]+:.*?##/ { printf "  \033[36m%-32s\033[0m %s\n", $$1, $$2 }
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }
		' $(MAKEFILE_LIST)
