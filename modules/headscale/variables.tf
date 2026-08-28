variable "name_prefix" {
  description = "Prefix for every resource this module creates. The VM takes this name verbatim; the rest append a suffix (-vnet, -pip, -nsg, -nic, -osdisk). Also used as the public IP's DNS label, so it must be unique within the region and valid as a DNS label."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to create the headscale resources in. The module does not create it -- a headscale host is one instance among several a subscription might hold, and the group's lifecycle is the caller's."
  type        = string
}

variable "location" {
  description = "Azure region for every resource this module creates."
  type        = string
  default     = "eastus"
}

variable "headscale_domain" {
  description = "Public FQDN clients reach headscale on, e.g. network.quark.autobutler.org. Becomes server_url in the headscale config, the nginx server_name, and the certbot certificate name. An A record for it must point at the module's public IP output before TLS can be issued."
  type        = string
}

variable "headscale_base_domain" {
  description = "MagicDNS base domain headscale hands out to nodes, e.g. headscale.quark.autobutler.org. Must differ from headscale_domain -- a node named the same as the control server would shadow it in DNS."
  type        = string
  default     = "headscale.example.org"
}

variable "admin_email" {
  description = "Email registered with Let's Encrypt for expiry notices on the certbot certificate."
  type        = string
}

variable "admin_username" {
  description = "Local admin user created on the VM and given the SSH public key."
  type        = string
  default     = "quark"
}

variable "admin_ssh_public_key" {
  description = "SSH public key authorised for admin_username. A public key, so committing it is fine -- it is what lets CI apply this module without a secret."
  type        = string
}

variable "vm_size" {
  description = "Azure VM SKU. headscale is a control plane only -- peer traffic goes direct over WireGuard and never touches this host -- so the default is deliberately small. Must match var.vm_architecture."
  type        = string
  default     = "Standard_B2pts_v2"
}

variable "vm_architecture" {
  description = "CPU architecture of vm_size. Selects the Ubuntu image SKU and the Go and headscale downloads, so it cannot drift from the size."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "amd64"], var.vm_architecture)
    error_message = "vm_architecture must be \"arm64\" or \"amd64\"."
  }
}

variable "os_disk_storage_account_type" {
  description = "Managed disk type for the OS disk."
  type        = string
  default     = "Standard_LRS"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_address_prefix" {
  description = "Address prefix for the single subnet the VM's NIC sits in."
  type        = string
  default     = "10.0.0.0/24"
}

variable "allowed_ssh_cidr" {
  description = "Source CIDR permitted to reach port 22, or \"*\" for anywhere. Narrowing this is the single highest-value hardening step available here; it defaults open only to match the existing hand-built host."
  type        = string
  default     = "*"
}

variable "headscale_version" {
  description = "Headscale release tag to install, e.g. v0.28.0. The leading v is stripped for the .deb filename by the setup script."
  type        = string
  default     = "v0.28.0"
}

variable "go_version" {
  description = "Go toolchain version installed on the VM to build the provisioning binary from source."
  type        = string
  default     = "1.22.3"
}

variable "provisioning_repo_url" {
  description = "Git repository cloned on the VM to build the provisioning service."
  type        = string
  default     = "https://github.com/autobutler-org/quark.git"
}

variable "provisioning_repo_branch" {
  description = "Branch of provisioning_repo_url to clone. The clone is --depth 1, so this pins what gets built only as far as the branch tip at boot."
  type        = string
  default     = "main"
}

variable "provisioning_package" {
  description = "Go package path within the cloned repository to build."
  type        = string
  default     = "./cmd/provisioning/"
}

variable "provisioning_service_name" {
  description = "Name of the systemd unit and of the binary installed into /usr/local/bin."
  type        = string
  default     = "quark-provisioning"
}

variable "provisioning_source_dir" {
  description = "Directory on the VM the provisioning repository is cloned into. Wiped and re-cloned on every run of the setup script."
  type        = string
  default     = "/opt/quark-src"
}

variable "provisioning_config_dir" {
  description = "Directory on the VM holding provisioning.env, where the headscale API key is written by hand after first boot."
  type        = string
  default     = "/etc/quark"
}

variable "tags" {
  description = "Tags applied to every resource this module manages."
  type        = map(string)
  default     = {}
}

variable "dns_zone_name" {
  description = "Azure DNS zone to create the control server's A record in. Leave null to manage the record outside terraform, in which case headscale_domain must be pointed at the public_ip_address output by hand. headscale_domain must be inside this zone."
  type        = string
  default     = null
}

variable "dns_zone_resource_group_name" {
  description = "Resource group holding dns_zone_name. Required when dns_zone_name is set; the zone is commonly in a different group from the VM."
  type        = string
  default     = null
}
