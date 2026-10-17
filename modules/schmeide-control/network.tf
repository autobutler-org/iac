resource "azurerm_virtual_network" "this" {
  name                = "${local.name}-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  name                 = "default"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.0.0.0/24"]
}

# Static and Standard, as for headscale. Static is what lets the VM be replaced without
# moving the hostname: the IP is its own resource, the NIC re-attaches it, and the alias
# record in dns.tf never changes. Runners and the GitHub App keep the same address.
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

# SSH, HTTP and HTTPS match modules/headscale, priorities included. The webhook listener
# (8080) is not here: it is plain HTTP, and only Caddy reaches it, over the docker network.
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

  # Caddy, proxying to the webhook listener. GitHub delivers webhooks from a published but
  # changing set of ranges, so this stays open rather than chasing api.github.com/meta.
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

  # Not redundant with 443: Caddy answers the ACME HTTP-01 challenge here, so closing it
  # breaks certificate issuance and renewal -- and NATS shares that certificate.
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

  # NATS, for runners. Public because runners can sit anywhere. schmeide serves TLS on it
  # with Caddy's certificate, and each runner authenticates with its steward's token.
  security_rule {
    name                       = "AllowNATS"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "4222"
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
