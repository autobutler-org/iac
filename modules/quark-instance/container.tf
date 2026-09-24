locals {
  hostname = "${var.dns_record_name}.${var.dns_zone_name}"
}

# One quark server behind Caddy for TLS. Quark serves plain HTTP on 8080 and its docs say
# not to expose that to the internet, so only Caddy's 80/443 are public. Caddy reaches
# quark over localhost, which is in quark's default QUARK_TRUSTED_PROXIES, so per-client
# login rate limiting works without setting it.
#
# Any change to a container forces a replacement of the whole group, so a version bump is
# a short outage and a new public IP. The Azure FQDN stays the same, which is why dns.tf
# CNAMEs to it rather than holding the IP.
resource "azurerm_container_group" "quark" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  ip_address_type     = "Public"
  dns_name_label      = var.dns_name_label
  restart_policy      = "Always"

  container {
    name   = "quark"
    image  = "ghcr.io/autobutler-org/quark:${var.quark_version}"
    cpu    = var.cpu
    memory = var.memory_gb

    # Not exposed: listed so Caddy has something to proxy to on localhost.
    ports {
      port = 8080
    }

    volume {
      name                 = "quark"
      mount_path           = "/var/lib/quark"
      share_name           = azurerm_storage_share.quark.name
      storage_account_name = azurerm_storage_account.data.name
      storage_account_key  = azurerm_storage_account.data.primary_access_key
    }
  }

  container {
    name   = "caddy"
    image  = "caddy:2"
    cpu    = 0.25
    memory = 0.5

    commands = ["caddy", "reverse-proxy", "--from", local.hostname, "--to", "localhost:8080"]

    ports {
      port = 80
    }

    ports {
      port = 443
    }

    volume {
      name                 = "caddy"
      mount_path           = "/data"
      share_name           = azurerm_storage_share.caddy.name
      storage_account_name = azurerm_storage_account.data.name
      storage_account_key  = azurerm_storage_account.data.primary_access_key
    }
  }

  exposed_port {
    port = 80
  }

  exposed_port {
    port = 443
  }

  tags = var.tags
}
