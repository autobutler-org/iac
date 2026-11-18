# External Secrets in the factory cluster, and the factory namespace with its database
# URL projected from the factory vault. The same split as ci-gitops.tf, without Argo:
# the factory chart is deployed by autobutler-org/factory's own workflow, so this
# cluster has nothing in this repo for Argo to watch.

resource "azurerm_user_assigned_identity" "factory_secrets" {
  name                = "id-autobutler-factory-secrets"
  resource_group_name = azurerm_resource_group.factory.name
  location            = var.location
  tags                = local.tags

  lifecycle {
    replace_triggered_by = [terraform_data.tenant]
  }
}

resource "azurerm_federated_identity_credential" "factory_secrets" {
  name                      = "external-secrets"
  user_assigned_identity_id = azurerm_user_assigned_identity.factory_secrets.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = module.factory.oidc_issuer_url
  subject                   = "system:serviceaccount:external-secrets:external-secrets"
}

resource "azurerm_key_vault_access_policy" "factory_secrets" {
  key_vault_id = module.factory.key_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.factory_secrets.principal_id

  secret_permissions = [
    "Get",
    "List",
  ]
}

# Same chart and version as the CI cluster's release. The system pool here is not
# tainted, so no tolerations.
resource "helm_release" "factory_external_secrets" {
  provider = helm.factory

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "2.15.0"
  namespace        = "external-secrets"
  create_namespace = true

  values = [
    yamlencode({
      serviceAccount = {
        name = "external-secrets"
        annotations = {
          "azure.workload.identity/client-id" = azurerm_user_assigned_identity.factory_secrets.client_id
        }
      }
      podLabels = {
        "azure.workload.identity/use" = "true"
      }
    }),
  ]
}

# A second release, for the CRD ordering reason given for argocd_bootstrap in
# ci-gitops.tf: the ClusterSecretStore kind does not exist until the release above.
resource "helm_release" "factory_bootstrap" {
  provider = helm.factory

  name       = "factory-bootstrap"
  chart      = "${path.module}/charts/factory-bootstrap"
  namespace  = "external-secrets"
  depends_on = [helm_release.factory_external_secrets]

  values = [
    yamlencode({
      vaultUrl = module.factory.key_vault_uri
    }),
  ]
}
