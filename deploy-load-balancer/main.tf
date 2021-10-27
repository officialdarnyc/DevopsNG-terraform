# Configure the Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.65"
    }
  }

  required_version = ">= 0.14.9"
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "prod" {
  name     = "${var.prefix}-resources"
  location = var.location
}

resource "azurerm_virtual_network" "prod" {
  name                = "${var.prefix}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.prod.location
  resource_group_name = azurerm_resource_group.prod.name
}

resource "azurerm_subnet" "prod" {
  name                 = "${var.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.prod.name
  virtual_network_name = azurerm_virtual_network.prod.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "prod" {
  name                = "${var.prefix}-pip"
  location            = azurerm_resource_group.prod.location
  resource_group_name = azurerm_resource_group.prod.name
  allocation_method   = "Dynamic"
  domain_name_label   = azurerm_resource_group.prod.name
}

resource "azurerm_lb" "prod" {
  name                = "${var.prefix}-lb"
  location            = azurerm_resource_group.prod.location
  resource_group_name = azurerm_resource_group.prod.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.prod.id
  }
}

resource "azurerm_lb_backend_address_pool" "prod" {
  resource_group_name = azurerm_resource_group.prod.name
  loadbalancer_id     = azurerm_lb.prod.id
  name                = "BackEndAddressPool"
}

resource "azurerm_lb_probe" "prod" {
  resource_group_name = azurerm_resource_group.prod.name
  loadbalancer_id     = azurerm_lb.prod.id
  name                = "ssh-probe"
  protocol            = "Tcp"
  port                = 22
}

resource "azurerm_lb_nat_pool" "prod" {
  resource_group_name            = azurerm_resource_group.prod.name
  name                           = "ssh"
  loadbalancer_id                = azurerm_lb.prod.id
  protocol                       = "Tcp"
  frontend_port_start            = 220
  frontend_port_end              = 229
  backend_port                   = 22
  frontend_ip_configuration_name = "PublicIPAddress"
}

resource "azurerm_linux_virtual_machine_scale_set" "prod" {
  name                = "${var.prefix}-vmss"
  resource_group_name = azurerm_resource_group.prod.name
  location            = azurerm_resource_group.prod.location
  sku                 = "Standard_F2"
  instances           = 1
  admin_username      = "ikenna"
  admin_password      = "****"

  disable_password_authentication = false

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "prod"
    primary = true

    ip_configuration {
      name                                   = "internal"
      primary                                = true
      subnet_id                              = azurerm_subnet.prod.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.prod.id]
      load_balancer_inbound_nat_rules_ids    = [azurerm_lb_nat_pool.prod.id]
    }
  }

  depends_on = [azurerm_lb_probe.prod]
}
