locals {
  # Applied to everything this root module manages. The imported resources carry no tags
  # today, so the first apply after the import will add these -- a real but benign diff,
  # visible in the plan. See imports.tf.
  tags = merge(
    {
      managed_by   = "terraform"
      repo         = "autobutler-org/iac"
      subscription = "autobutler"
    },
    var.tags,
  )
}
