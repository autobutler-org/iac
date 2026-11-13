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

# Static and Standard, as for headscale. The alias record in dns.tf points at this resource,
# so the hostname -- and the beacon URL baked into both websites -- survives a VM replacement.
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

# SSH, HTTPS and HTTP, with modules/headscale's names and priorities. Nothing else listens:
# GoatCounter serves 443 itself and answers 80 only to redirect and to complete the ACME
# HTTP-01 challenge.
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

  # Public: every visitor's browser sends its page view here, and the dashboard is here.
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

  # Not redundant with 443: Let's Encrypt's HTTP-01 challenge arrives on port 80, so closing
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
