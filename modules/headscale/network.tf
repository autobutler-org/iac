resource "azurerm_virtual_network" "this" {
  name                = "${local.name}-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.vnet_address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  name                 = "default"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_address_prefix]
}

# Static, and Standard sku because a Standard NIC cannot attach a Basic IP. Static matters
# for more than convenience: the A record for headscale_domain points at this address by
# hand, and a dynamic IP would silently break both the tailnet and certbot renewal on every
# deallocate.
resource "azurerm_public_ip" "this" {
  name                = "${local.name}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  domain_name_label   = local.name
  tags                = var.tags
}

# Priorities match the hand-built autobutler-headscale host so the two stay comparable at a
# glance. 130 is deliberately vacant: it held AllowHeadscaleGRPC (tcp/50443) there, which
# grants nothing -- headscale's grpc_listen_addr is 127.0.0.1:50443, so no process is
# listening on a public interface for that rule to admit. It is dropped here rather than
# replicated, and the gap is left so the remaining numbers still line up.
resource "azurerm_network_security_group" "this" {
  name                = "${local.name}-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_ssh_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Not redundant with 443: certbot's HTTP-01 challenge is served over port 80, so closing
  # this breaks certificate issuance and every renewal after it.
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowProvisioning"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8081"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # STUN, for NAT traversal between tailnet peers. UDP, and genuinely public -- peers that
  # cannot reach it fall back to relaying through DERP, which is slower.
  security_rule {
    name                       = "AllowHeadscaleSTUN"
    priority                   = 150
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "3478"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "this" {
  name                = "${local.name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this.id
  }
}

resource "azurerm_network_interface_security_group_association" "this" {
  network_interface_id      = azurerm_network_interface.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}
