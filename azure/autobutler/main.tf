locals {
  # Applied to everything this root module manages. Anything adopted from a hand-built
  # resource picks these up on the apply that adopts it, which shows as a tag diff in the
  # plan -- expected, not drift.
  tags = merge(
    {
      managed_by   = "terraform"
      repo         = "autobutler-org/iac"
      subscription = "autobutler"
    },
    var.tags,
  )
}
