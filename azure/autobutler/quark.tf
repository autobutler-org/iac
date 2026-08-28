# Release artifact hosting for the quark client (github.com/autobutler-org/quark).
#
# The module lives at the repo root rather than under azure/, because every directory under
# azure/ is an Azure subscription and a modules/ directory there would break that rule.
module "quark" {
  source = "../../modules/quark"

  location = var.location
  tags     = local.tags
}
