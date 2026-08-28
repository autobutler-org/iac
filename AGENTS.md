# Terraform Coding Standards

This repository is the Azure infrastructure for autobutler-org: Terraform against the
`azurerm` provider, plus a Bicep template in `bootstrap/` that creates the storage account
Terraform keeps its state in. There is no application code here.

## General guidance

Follow the conventions this repo's formatting and linting configuration already enforces.
When in doubt, do what `make check` tells you.

## Read `README.md` first

`README.md` is the design record. Most "why is it like this?" questions are answered there
with the reasoning intact: why a subscription is a directory, why state is pinned to the
`autobutler` subscription regardless of what a root module targets, why the lock file
covers four platforms, and why the state account has no access keys.

`bootstrap/README.md` covers the state backend specifically — what it creates, how to
recover a clobbered state file from blob versioning, and why it is Bicep rather than
Terraform.

## File layout

```
azure/<subscription>/     one Azure subscription, one root module, one state file
modules/<name>/           shared modules, referenced with a relative source
bootstrap/                Bicep for the terraform state backend
```

**Every directory under `azure/` is an Azure subscription.** That rule is load-bearing: the
Makefile turns the directory name into `ARM_SUBSCRIPTION_ID`, so the path is what decides
which subscription gets touched. Never put a non-subscription directory under `azure/` —
that is why `modules/` sits at the repo root instead.

Inside a module, each resource type gets its own file, named after the type minus the
provider prefix: every `azurerm_storage_account` goes in `storage.tf`, every
`azurerm_virtual_network` in `network.tf`. Supporting files stay single-purpose:

- `backend.tf` — the `terraform` block for a **root** module: `required_version`,
  `required_providers`, and the `backend "azurerm"` block.
- `main.tf` — `locals` in a root module; the `terraform` block in a **shared** module,
  which has no backend of its own.
- `providers.tf` — provider blocks.
- `variables.tf`, `outputs.tf`, `imports.tf` (`import` blocks).

There is no empty `main.tf`. If a file would have nothing in it, do not create it.

Shared modules are shared, so treat a change to one as a change to every caller. They
declare version constraints as floors (`>= 5.0`), not pins; the root module is where
versions actually get pinned.

## Use the Makefile, not bare `terraform`

Every command lives in the root `Makefile`, run from the repo root. `TF_DIR` is set there,
so no `-chdir` is needed:

```bash
make                                   # help: every target, with descriptions
make subscriptions                     # what SUBSCRIPTION= accepts
make init                              # terraform init -reconfigure
make plan                              # writes planfile.tfplan
make validate                          # needs `make init` first
make check/validate                    # init -backend=false + validate; no credentials
make check                             # format + lint + bicep + validate
make plan/show                         # print the planfile in readable form
make lock                              # regenerate the four-platform provider lock
make generate-resources-from-imports   # plan -generate-config-out=generated.tf
make import-resource RESOURCE_PATH=... RESOURCE_ID=...
make bootstrap/whatif                  # preview the state backend deployment
make bootstrap                         # create the state backend (once, before anything)
```

The Makefile needs GNU Make 3.82+ for `.ONESHELL:` — macOS ships 3.81 as `/usr/bin/make`,
so use `gmake` there (`brew install make`). The Makefile checks and says so.

`SUBSCRIPTION` selects the root module and defaults to `autobutler`, the only one today.
Pass it explicitly once there is more than one: `make plan SUBSCRIPTION=autobutler`.

Everything that talks to Azure needs `az login`; the `az-login` guard says so rather than
failing with an auth error. `check/format`, `check/lint`, `check/validate`, `check/bicep`
and `plan/show` need no credentials.

Pass extra flags through the variables rather than editing the targets:

```bash
make plan EXTRA_TF_ARGS="-target=module.quark -detailed-exitcode"
make check/lint EXTRA_TFLINT_ARGS="--format=compact"
```

`make plan` deliberately does not fail on exit code 2. With `-detailed-exitcode` that means
"changes present"; it keeps the planfile and exits 2. Do not treat a 2 as a broken plan.

`make plan` also always passes `-lock=false`. A local plan is read-only, so it has no
business holding the blob lease an apply needs. The apply targets do not pass it — an apply
must lock.

## CI

Four workflows in `.github/workflows/`:

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `check.yml` | PR to `main`, manual | `make check/format`, `check/lint`, `check/validate`, `check/bicep` |
| `plan.yml` | PR to `main`, `workflow_call` | `make init` + `make plan`, uploads the planfile, writes the plan into the job summary |
| `apply.yml` | push to `main`, manual | calls `plan.yml`, then `make apply-from-planfile` on the planfile that job produced |
| `codeql.yml` | PR to `main`, push to `main`, weekly, manual | CodeQL on the `actions` language — the workflows themselves, nothing else |

`check.yml` needs **no Azure credentials** — `check/validate` inits with `-backend=false`,
so it reads provider schemas and nothing else. Keep it that way; anything needing Azure
belongs in `plan.yml`.

`apply.yml` does not re-derive the plan. It runs `plan.yml` as a job and applies that
job's planfile, which is named with the commit SHA, so what gets applied is provably what
was planned for the commit being applied. Its `apply` job is gated on the `production`
environment, where required reviewers can be added in repo settings.

Authentication is OIDC via `azure/login`. There is no client secret anywhere:
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID` are repository
*variables*, none of which is sensitive. `bootstrap/github-oidc.bash` creates the app
registration and federated credentials this depends on.

`concurrency` differs between the two on purpose: a superseded plan is cancelled, an apply
never is. A half-applied change is worse than a queued one.

`codeql.yml` scans **only** the `actions` language, and that is deliberate. CodeQL has no
Terraform/HCL analyser and no Bicep analyser, so `azure/`, `modules/` and `bootstrap/` are
invisible to it; the workflows in `.github/workflows/` are the one thing here it can read,
where it catches expression injection into `run:` blocks and over-broad job permissions. Do
not add languages to that matrix to make the security tab look fuller — an analysis of
nothing reads exactly like an analysis that found nothing. What lints the Terraform is
`tflint` with the `azurerm` ruleset, in `check.yml`.

## Dependency updates

`.github/dependabot.yml` covers the two ecosystems this repo has: `github-actions` (the
action versions the workflows pin) and `terraform` (the `azurerm` provider constraint).
Weekly, grouped into one pull request per ecosystem.

**Check the lock file diff on every Terraform update from Dependabot.** Dependabot
regenerates `.terraform.lock.hcl` when it moves a provider constraint, and it has to infer
which platforms the existing lock covered — falling back to `linux_amd64` alone if it infers
none. A lock that shrank that way still passes every CI job, because CI is `linux_amd64`; it
breaks the next `terraform init` on a darwin machine with a checksum mismatch, long after
the merge that caused it. If the `h1:` list got shorter, run `make lock` on the branch.

## Plan locally, apply through CI

State is shared. A local apply from an unmerged branch writes real Azure changes plus a
state version that no reviewed commit explains, and the next person to plan inherits both
with no way to tell where they came from. CI applies from `main`, where every change has
been reviewed.

`make apply-from-source`, `make apply-from-planfile` and `make destroy` exist for CI and
for recovery. Do not run them locally unless the user asks for it in that message.

## Never commit

`*.tfplan` (`planfile.tfplan`), `generated.tf`, `.terraform/`, `*override.tf.json`, and
anything matching `*.tfstate*` — including `errored.tfstate`, which is a full state
snapshot. All are in `.gitignore`; the failure mode is forcing one past it. If you see an
`errored.tfstate`, tell the user rather than deleting it — it is the recovery artifact for
a half-applied change.

`.terraform.lock.hcl` **is** committed, and it covers four platforms (`linux_amd64`,
`linux_arm64`, `darwin_amd64`, `darwin_arm64`). A plain `terraform init` on one machine
shrinks it to that machine's platform; if a diff drops platform hashes, that is a
regression, not a cleanup. Regenerate with `make lock`. A Dependabot provider bump can
shrink it the same way — see **Dependency updates** under CI.

## Importing existing Azure resources

Most of what this repo manages already exists — it was created by hand or by `az` and is
being adopted. The loop:

1. Add an `import` block to the **root module's** `imports.tf` with the resource address
   and the full ARM resource ID. Import blocks belong to the configuration, not the module,
   so a resource inside a module is addressed through it:
   `to = module.quark.azurerm_storage_account.release`.
2. `make generate-resources-from-imports` for a draft in `generated.tf`.
3. Move the draft into the right per-type file and correct it, then delete `generated.tf`.
4. `make plan` and iterate until the plan reports **no changes** for that resource. A
   zero-change plan is the only evidence the block matches what Azure actually has.

`generated.tf` is gitignored — scratch output, never a source file, do not `git add -f` it.

Prefer `import` blocks over `make import-resource`: the block is reviewable in the diff,
whereas `terraform import` is an out-of-band state mutation. Remove the block once the
import has been applied and state holds the resource.

ARM resource IDs are long and easy to get subtly wrong. Get one from
`az resource show --ids ... --query id -o tsv` or `az <type> show ... --query id -o tsv`
rather than assembling it by hand. Nested resources like a blob container use the full
manager ID (`.../storageAccounts/<name>/blobServices/default/containers/<name>`), not the
data-plane URL.

## Linting

`.tflint.hcl` runs the full `terraform` ruleset plus the `azurerm` ruleset, with the strict
rules **on** deliberately — documented variables and outputs, no unused declarations,
required version constraints, standard module structure. This repo is greenfield; there is
no legacy tree to grandfather in, and a rule that is cheap to satisfy on the first file is
expensive to retrofit on the hundredth.

Do not disable a rule to make your change pass. Fix the code. If a rule is genuinely wrong
for this layout, disable that one rule with a comment saying exactly why.

`azurerm_resources_missing_prevent_destroy` will fire on anything holding data. Adding
`lifecycle { prevent_destroy = true }` is usually the right answer, not a suppression.

## State and bootstrap

State lives in the `autobutler` subscription, in the `tfstate` container of the
`stautobutlertfstate` storage account, one blob per root module. It is pinned there in
`backend.tf` on purpose: the backend resolves its account independently of the provider, so
a root module targeting a different subscription still writes state to the same common
place.

That account sets `allowSharedKeyAccess: false`, so there are no account keys. Access is
Entra ID RBAC (Storage Blob Data Owner), which is why every backend block sets
`use_azuread_auth = true` and omits `resource_group_name` — that argument exists only to
drive the key lookup. Locking is a native blob lease; there is no lock table.

`bootstrap/` has to be deployed before Terraform has anywhere to write:

```bash
make bootstrap/whatif
make bootstrap
./bootstrap/github-oidc.bash create   # the CI identity; needs the account to exist first
```

See `bootstrap/README.md` for what these create and how to recover a clobbered state file.

## Maintaining this document

After significant changes, decide whether they belong here or in `README.md`. Rough split:
**AGENTS.md** is the rules and the commands, **README.md** is the reasoning and the
history. Update this file if you add a Makefile target, change the credential flow, add a
linter rule, or introduce a new convention.
