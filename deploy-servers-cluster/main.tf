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

locals {
  instance_count = 6
}

resource "azurerm_resource_group" "prodenv" {
  name     = "${var.prefix}-resources"
  location = "${var.location}"
}

resource "azurerm_virtual_network" "prodenv" {
  name                = "${var.prefix}-network"
  resource_group_name = "${azurerm_resource_group.prodenv.name}"
  location            = "${azurerm_resource_group.prodenv.location}"
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "prodenv" {
  name                 = "internal"
  virtual_network_name = "${azurerm_virtual_network.prodenv.name}"
  resource_group_name  = "${azurerm_resource_group.prodenv.name}"
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_virtual_machine_scale_set" "prodenv" {
  name                = "${var.prefix}-vmss"
  location            = "${azurerm_resource_group.prodenv.location}"
  resource_group_name = "${azurerm_resource_group.prodenv.name}"
  upgrade_policy_mode = "Manual"

  sku {
    name     = "Standard_D1_v2"
    tier     = "Standard"
    capacity = "${local.instance_count}"
  }

  os_profile {
    computer_name_prefix = "${var.prefix}-vm"
    admin_username       = "myadmin"
    admin_password       = "****"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  network_profile {
    name    = "web_ss_net_profile"
    primary = true

    ip_configuration {
      name      = "internal"
      subnet_id = "${azurerm_subnet.prodenv.id}"
      primary   = true
    }
  }

  storage_profile_os_disk {
    name              = ""
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_profile_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
}

resource "azurerm_monitor_autoscale_setting" "prodenv" {
  name                = "autoscale-cpu"
  target_resource_id  = "${azurerm_virtual_machine_scale_set.prodenv.id}"
  location            = "${azurerm_resource_group.prodenv.location}"
  resource_group_name = "${azurerm_resource_group.prodenv.name}"

  profile {
    name = "autoscale-cpu"

    capacity {
      default = "${local.instance_count}"
      minimum = 0
      maximum = 15
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = "${azurerm_virtual_machine_scale_set.prodenv.id}"
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = "${azurerm_virtual_machine_scale_set.prodenv.id}"
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 15
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }
  }
}
