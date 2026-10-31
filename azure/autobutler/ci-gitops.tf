# Argo CD and External Secrets, installed once. Terraform does not own the runner Helm
# release. Argo watches gitops/autobutler/apps on main and applies that. The chart it
# installs is not in this repo.
#
# The repository credential cannot live in the watched directory. Argo would need the
# credential before it could sync the manifest that creates it. External Secrets projects
# it from Key Vault as part of this Helm release, which runs before Argo syncs anything.
#
# Chart versions looked up on 2026-10-29: external-secrets 2.14.0 (appVersion v2.14.0)
# and argo-cd 10.11.6 (appVersion v3.5.6).

data "azurerm_client_config" "current" {}

# Not the runner identity. That one is for CI jobs. This one is the External Secrets
# controller, which has to read the vault before any runner exists. Recreating it changes
# the client id baked into the Helm release, so it is not disposable.
resource "azurerm_user_assigned_identity" "ci_gitops" {
  name                = "id-autobutler-ci-gitops"
  resource_group_name = azurerm_resource_group.autobutler_ci.name
  location            = var.location
  tags                = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

# Subject confirmed against external-secrets chart 2.14.0. With the release named
# external-secrets, the chart's fullname helper keeps that name, and the service account
# defaults to it, in the release namespace. The chart's service account is created with
# that name explicitly below so the federated credential cannot drift from a helper change.
resource "azurerm_federated_identity_credential" "ci_gitops" {
  name                      = "external-secrets"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci_gitops.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = module.ci_cluster.oidc_issuer_url
  subject                   = "system:serviceaccount:external-secrets:external-secrets"
}

# Get and List only. The vault stays on access policies: Key Vault data-plane roles are
# not in the CI role-assignment condition, so an RBAC grant here would fail the apply.
# This policy is separate from the runner's. A policy added by hand is left alone.
resource "azurerm_key_vault_access_policy" "ci_gitops" {
  key_vault_id = module.ci_cluster.key_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.ci_gitops.principal_id

  secret_permissions = [
    "Get",
    "List",
  ]
}

# The system pool is tainted CriticalAddonsOnly. These two releases are the
# non-addon pods that still belong there.
locals {
  system_tolerations = [
    {
      key      = "CriticalAddonsOnly"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    },
  ]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "2.14.0"
  namespace        = "external-secrets"
  create_namespace = true

  values = [
    yamlencode({
      serviceAccount = {
        name = "external-secrets"
        annotations = {
          "azure.workload.identity/client-id" = azurerm_user_assigned_identity.ci_gitops.client_id
        }
      }
      # The webhook only projects a token into pods that carry this label. The
      # ClusterSecretStore also names the service account, so a token request works
      # even if the webhook does not.
      podLabels = {
        "azure.workload.identity/use" = "true"
      }
      global = {
        tolerations = local.system_tolerations
      }
      tolerations = local.system_tolerations
      webhook = {
        tolerations = local.system_tolerations
      }
      certController = {
        tolerations = local.system_tolerations
      }
    }),
  ]
}

# LoadBalancer on the address reserved in the cluster module. The A record
# argo.errand.cloud.autobutler.org already aliases that IP. The annotations name the
# address in the cluster resource group, which is not the node resource group AKS owns.
# The admin password is left unset so the chart generates one. It is not copied into
# git or into an output.
resource "helm_release" "argo_cd" {
  name             = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.11.6"
  namespace        = "argocd"
  create_namespace = true

  # The repo credential is an ExternalSecret. Its CRD comes from the release above.
  # upgrade_install covers the failed install already left in the cluster: Helm kept
  # the release name, and a plain install would refuse to reuse it.
  depends_on      = [helm_release.external_secrets]
  upgrade_install = true

  values = [
    yamlencode({
      global = {
        tolerations = local.system_tolerations
      }
      server = {
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/azure-load-balancer-resource-group" = module.ci_cluster.resource_group_name
            "service.beta.kubernetes.io/azure-pip-name"                     = module.ci_cluster.argocd_public_ip_name
          }
        }
      }
      # No repository credential. This repo is public, and projecting
      # argocd-repo-token made GitHub reject the clone: the value stored there is not a
      # GitHub token. Add an ExternalSecret back only if the repo becomes private.
      extraObjects = [
        {
          apiVersion = "external-secrets.io/v1"
          kind       = "ClusterSecretStore"
          metadata = {
            name = "autobutler-ci"
          }
          spec = {
            provider = {
              azurekv = {
                authType = "WorkloadIdentity"
                vaultUrl = "https://kv-autobutler-ci.vault.azure.net"
                serviceAccountRef = {
                  name      = "external-secrets"
                  namespace = "external-secrets"
                }
              }
            }
          }
        },
      ]
    }),
  ]
}

# Not in the argo-cd release. That chart installs the Application CRD and Helm builds
# the whole manifest before the API server will serve the new kind, so the apply died
# with "no matches for kind Application". This release runs after that one, when the
# CRD is already registered.
resource "helm_release" "argocd_bootstrap" {
  name            = "argocd-bootstrap"
  chart           = "${path.module}/charts/argocd-bootstrap"
  namespace       = "argocd"
  upgrade_install = true
  depends_on      = [helm_release.argo_cd]
}
