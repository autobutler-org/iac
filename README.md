# iac

Azure infrastructure for autobutler-org, as Terraform against the `azurerm` provider.

`AGENTS.md` is the rules and commands. This file is the reasoning.

## Layout

```text
azure/<subscription>/     one Azure subscription, one root module, one state file
modules/<name>/           shared modules, referenced with a relative source
bootstrap/                Bicep for the terraform state backend, and the CI identity script
.github/workflows/        check on PRs, plan on PRs, apply on push to main
```

**Every directory under `azure/` is an Azure subscription.** `azure/autobutler/` is the
root module for the `autobutler` subscription, and the only one today.

That rule is load-bearing rather than cosmetic. The Makefile turns the directory name into
`ARM_SUBSCRIPTION_ID`, which the `azurerm` provider reads natively, so the path is the
single thing deciding which subscription gets touched. No subscription GUID has to be kept
in sync across root modules, and a configuration under `azure/autobutler/` cannot quietly
apply somewhere else. It is also why `modules/` sits at the repo root: a non-subscription
directory under `azure/` would break the mapping.

## State lives in one place, on purpose

Every root module writes state to the `tfstate` container of the `stautobutlertfstate`
storage account in the `autobutler` subscription, one blob per root module.

A Terraform backend resolves its storage account independently of the provider's
subscription. So a future `azure/<other>/` root module deploying into a different
subscription still records its state alongside everything else, without a second bootstrap
and without anyone having to remember where a given stack's state went. The subscription is
written out as a literal in each `backend.tf` because a backend block cannot take variables
— and because it should *not* follow the target subscription.

The state account has no access keys: `allowSharedKeyAccess` is `false`. Access is Entra ID
RBAC, which is why each backend block sets `use_azuread_auth = true` and omits
`resource_group_name` — that argument exists only to drive the account-key lookup this
makes impossible. Locking is a native blob lease, so there is no lock table to run.

`bootstrap/` is Bicep and not Terraform for the obvious reason: a backend has to exist
before Terraform has anywhere to record that it built one. See `bootstrap/README.md`.

## Getting started

Prerequisites:

```bash
brew install terraform tflint azure-cli
az login
```

`az bicep` is installed on demand by the Azure CLI. `make` reports any missing tool with
the command that installs it.

On macOS use `gmake`: the Makefile needs GNU Make 3.82+ for `.ONESHELL:`, and `/usr/bin/make`
is 3.81. The Makefile checks this and says so rather than failing with a shell syntax error.

First time in a fresh subscription — create the state backend, then the CI identity:

```bash
make bootstrap/whatif                 # preview
make bootstrap                        # create the state storage account
./bootstrap/github-oidc.bash create   # create the GitHub Actions identity
```

Both are idempotent. See `bootstrap/README.md`.

Then:

```bash
make                    # help
make subscriptions      # what SUBSCRIPTION= accepts
make init
make plan
make check              # format + lint + bicep + validate
```

`SUBSCRIPTION` defaults to `autobutler`, so the commands above need no arguments today.
Pass it explicitly once there is more than one: `make plan SUBSCRIPTION=autobutler`.

## CI

`check.yml` runs formatting, linting and validation on every PR, and deliberately needs no
Azure credentials at all — `make check/validate` inits with `-backend=false`, so it reads
provider schemas and nothing else. That keeps the basic signal working regardless of
whether a run has an Azure identity.

`plan.yml` runs a real plan on a PR, uploads the planfile as an artifact named for the
commit, and writes the readable plan into the job summary. `apply.yml` runs on push to
`main`, calls `plan.yml` as its first job, and applies that job's planfile — so what gets
applied is provably what was planned for the commit being applied, rather than a second
plan that might have raced with someone else's merge.

Authentication is OIDC; there is no client secret. `bootstrap/github-oidc.bash` creates the
app registration and federated credentials, and prints the three repository variables to
set.

`codeql.yml` is a deliberately narrow fourth workflow. CodeQL supports neither Terraform nor
Bicep — the analysers do not exist — so the only thing in this repository it can read is the
workflow files themselves, scanned as the `actions` language. That is worth having: a
`${{ ... }}` expression interpolated into a `run:` block is a shell injection, and `plan.yml`
builds its job summary out of exactly that shape. It is not worth dressing up. Listing
languages the repository has no code in would turn the security tab green over an analysis
of nothing, which is a worse outcome than no scan at all, because it looks like coverage.
The Terraform is covered by `tflint` with the `azurerm` ruleset in `check.yml`.

`.github/dependabot.yml` keeps the two things here that go stale current: the action
versions the workflows pin, and the `azurerm` provider constraint. Weekly, one grouped pull
request per ecosystem. The one thing to watch on a provider bump is the lock file — see
AGENTS.md, "Dependency updates" — because Dependabot regenerates it and can leave it
covering fewer platforms than the four this repo commits, in a way CI cannot see.

## Adding a subscription

1. `mkdir azure/<name>/`, where `<name>` matches the subscription as `az account list`
   shows it. The name is how the Makefile resolves `ARM_SUBSCRIPTION_ID`, so it has to
   match exactly.
2. Copy `azure/autobutler/backend.tf` and change `key` to `azure/<name>.tfstate`. Leave
   `subscription_id` and `tenant_id` pointing at the state account — they identify where
   state goes, not where resources go.
3. Copy `providers.tf` unchanged, and write `main.tf` with the locals for that subscription.
4. `make init SUBSCRIPTION=<name>` then `make lock SUBSCRIPTION=<name>`.

## Adding a shared module

`modules/<name>/`, with `storage.tf` / `network.tf` / etc. per resource type,
`variables.tf`, `outputs.tf`, and a `main.tf` holding the module's `terraform` block. Call
it from a root module with a relative `source`. Constraints in a module are floors
(`>= 5.0`); the root module pins.

## What is here now

`modules/quark/` — release artifact hosting for the
[quark](https://github.com/autobutler-org/quark) client: a resource group, the
`quarkrelease` storage account, and the `releases` container.

The account and container are **anonymously readable, deliberately**. Quark's self-update
path builds an `azblob` client with `NewClientWithNoCredential` and lists the container by
prefix, so public container-level access is the transport, not an oversight. The comment in
`modules/quark/storage.tf` spells this out; read it before tightening anything there,
because the failure mode is every installed client in the field silently losing the ability
to update, with nothing in this repo failing.

These resources predate this repo. They were adopted through `import` blocks rather than
created, and that adoption is done — state holds all three and `make plan` is clean. The
`import` blocks have been removed; see "Adopting an existing resource" for the loop to
follow next time.
