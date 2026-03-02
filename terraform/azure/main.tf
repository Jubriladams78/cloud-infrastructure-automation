# =============================================================
# Azure Infrastructure Automation - Terraform
# Author: Jubril Adams
# Description: Deploys a secure Azure environment including
#   Resource Group, VNet, Subnet, NSG, and Linux VM
# =============================================================

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
  }
}

provider "azurerm" {
  features {}
}

# --- Variables ---
variable "location" {
  description = "Azure region for resources"
  default     = "eastus"
}

variable "environment" {
  description = "Environment tag (dev, staging, prod)"
  default     = "dev"
}

variable "admin_username" {
  description = "Admin username for the VM"
  default     = "azureadmin"
}

variable "admin_password" {
  description = "Admin password for the VM"
  sensitive   = true
}

# --- Resource Group ---
resource "azurerm_resource_group" "main" {
  name     = "rg-cloud-automation-${var.environment}"
  location = var.location

  tags = {
    Environment = var.environment
    Owner       = "Jubril Adams"
    Project     = "cloud-infrastructure-automation"
    ManagedBy   = "Terraform"
  }
}

# --- Virtual Network ---
resource "azurerm_virtual_network" "main" {
  name                = "vnet-main-${var.environment}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = azurerm_resource_group.main.tags
}

# --- Subnet ---
resource "azurerm_subnet" "web" {
  name                 = "snet-web"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# --- Network Security Group ---
resource "azurerm_network_security_group" "web" {
  name                = "nsg-web-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "10.0.0.0/8"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = azurerm_resource_group.main.tags
}

# --- Associate NSG to Subnet ---
resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

# --- Public IP ---
resource "azurerm_public_ip" "vm" {
  name                = "pip-vm-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = azurerm_resource_group.main.tags
}

# --- Network Interface ---
resource "azurerm_network_interface" "vm" {
  name                = "nic-vm-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }

  tags = azurerm_resource_group.main.tags
}

# --- Linux Virtual Machine ---
resource "azurerm_linux_virtual_machine" "main" {
  name                = "vm-web-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_B2s"
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.vm.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  tags = azurerm_resource_group.main.tags
}

# --- Outputs ---
output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "vm_public_ip" {
  description = "Public IP address of the VM"
  value       = azurerm_public_ip.vm.ip_address
}

output "vnet_name" {
  value = azurerm_virtual_network.main.name
}
