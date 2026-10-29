# subscription_id is not set here on purpose. It comes from ARM_SUBSCRIPTION_ID, which the
# Makefile derives from the `azure/<subscription>/` directory this root module lives in --
# so the directory name is the single source of truth for which subscription gets touched,
# and no subscription GUID has to be kept in sync across root modules.
#
# Running terraform directly, outside `make`, needs it exported:
#   export ARM_SUBSCRIPTION_ID=$(az account show --subscription autobutler --query id -o tsv)
provider "azurerm" {
  features {}
}

# Same Azure CLI login as azurerm. No separate credential. modules/ci-cluster uses this
# to look up the github-actions-iac service principal, so a plan does not grant cluster
# admin to whoever happened to run it.
provider "azuread" {}

# kubelogin, not a client certificate. local_account_disabled means the cluster does not
# issue an admin kubeconfig, so the Helm provider cannot use client_certificate or
# client_key. host and the CA come from the cluster module. The CA attribute is base64,
# and the provider wants PEM. The server id is the well-known AKS Microsoft Entra app.
provider "helm" {
  kubernetes = {
    host                   = module.ci_cluster.cluster_host
    cluster_ca_certificate = base64decode(module.ci_cluster.cluster_ca_certificate)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "kubelogin"
      args = [
        "get-token",
        "--login",
        "azurecli",
        "--server-id",
        "6dae42f8-4368-4678-94ff-3960e28e3630",
      ]
    }
  }
}
