terraform {
  required_version = ">= 0.14.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true
  features {}
}

resource "azurerm_resource_group" "terraformResourceGroup" {
  name     = "terraformResourceGroup"
  location = "eastus"
  tags = {
    "Environment" = "atividade terraform"
  }
}

resource "azurerm_virtual_network" "terraformVirtualNetwork" {
  name                = "terraformVirtualNetwork"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.terraformResourceGroup.location
  resource_group_name = azurerm_resource_group.terraformResourceGroup.name
}

resource "azurerm_subnet" "terraformSubnet" {
  name                 = "terraformSubnet"
  resource_group_name  = azurerm_resource_group.terraformResourceGroup.name
  virtual_network_name = azurerm_virtual_network.terraformVirtualNetwork.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "terraformPublicIp" {
  name                = "terraformPublicIp"
  location            = azurerm_resource_group.terraformResourceGroup.location
  resource_group_name = azurerm_resource_group.terraformResourceGroup.name
  allocation_method   = "Static"
}

resource "azurerm_network_security_group" "terraformSecurityGroup" {
  name                = "terraformSecurityGroup"
  location            = azurerm_resource_group.terraformResourceGroup.location
  resource_group_name = azurerm_resource_group.terraformResourceGroup.name

    security_rule {
    name                       = "mysql"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "ssh"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "terraformNetworkInterface" {
  name                = "terraformNetworkInterface"
  location            = azurerm_resource_group.terraformResourceGroup.location
  resource_group_name = azurerm_resource_group.terraformResourceGroup.name

  ip_configuration {
    name                          = "ipConfiguration"
    subnet_id                     = azurerm_subnet.terraformSubnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.terraformPublicIp.id
  }
}

resource "azurerm_network_interface_security_group_association" "terraformSecurityGroupAssociation" {
  network_interface_id      = azurerm_network_interface.terraformNetworkInterface.id
  network_security_group_id = azurerm_network_security_group.terraformSecurityGroup.id
}

resource "azurerm_storage_account" "terraformStorageAccountMysql" {
  name                     = "terraformatorageaccount"
  resource_group_name      = azurerm_resource_group.terraformResourceGroup.name
  location                 = azurerm_resource_group.terraformResourceGroup.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_linux_virtual_machine" "terraformVirtualMachine" {
  name                  = "terraformVirtualMachine"
  location              = azurerm_resource_group.terraformResourceGroup.location
  resource_group_name   = azurerm_resource_group.terraformResourceGroup.name
  network_interface_ids = [azurerm_network_interface.terraformNetworkInterface.id]
  size                  = "Standard_DS1_v2"

  os_disk {
    name                 = "osDisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  computer_name                   = "terraformVirtualMachine"
  admin_username                  = "adminuser"
  admin_password                  = "abcde@123"
  disable_password_authentication = false

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.terraformStorageAccountMysql.primary_blob_endpoint
  }

  depends_on = [azurerm_resource_group.terraformResourceGroup]
}

resource "time_sleep" "wait_30_seconds_db" {
  depends_on = [azurerm_linux_virtual_machine.terraformVirtualMachine]
  create_duration = "30s"
}

resource "null_resource" "upload_db" {
  provisioner "file" {
    connection {
      type     = "ssh"
      user     = "adminuser"
      password = "abcde@123"
      host     = azurerm_public_ip.terraformPublicIp.ip_address
    }
    source      = "config"
    destination = "/home/adminuser"
  }

   depends_on = [ time_sleep.wait_30_seconds_db ]

}

resource "null_resource" "deploy_db" {
  triggers = {
    order = null_resource.upload_db.id
  }
  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = "adminuser"
      password = "abcde@123"
      host     = azurerm_public_ip.terraformPublicIp.ip_address
    }
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y mysql-server-5.7",
      "sudo mysql < /home/adminuser/config/user.sql",
      "sudo cp -f /home/adminuser/config/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
      "sudo service mysql restart",
      "sleep 20",
    ]
  }
}

output "public_ip_address_mysql" {
  value = azurerm_public_ip.terraformPublicIp.ip_address
}