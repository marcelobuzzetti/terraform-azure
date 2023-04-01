terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "mafs-rg" {
  name     = "mafs-resources"
  location = "East US"
  tags = {
    environment = "dev"
  }
}

resource "azurerm_virtual_network" "mafs-vn" {
  name                = "mafs-network"
  resource_group_name = azurerm_resource_group.mafs-rg.name
  location            = azurerm_resource_group.mafs-rg.location
  address_space       = ["10.123.0.0/16"]

  tags = {
    environment = "dev"
  }
}

resource "azurerm_subnet" "mafs-subnet" {
  name                 = "mafs-subnet"
  resource_group_name  = azurerm_resource_group.mafs-rg.name
  virtual_network_name = azurerm_virtual_network.mafs-vn.name
  address_prefixes     = ["10.123.1.0/24"]
}

resource "azurerm_network_security_group" "mafs-sg" {
  name                = "mafs-sg"
  location            = azurerm_resource_group.mafs-rg.location
  resource_group_name = azurerm_resource_group.mafs-rg.name
  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_security_rule" "mafs-dev-rule" {
  name                        = "mafs-dev-rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.mafs-rg.name
  network_security_group_name = azurerm_network_security_group.mafs-sg.name
}

resource "azurerm_subnet_network_security_group_association" "mafs-sga" {
  subnet_id                 = azurerm_subnet.mafs-subnet.id
  network_security_group_id = azurerm_network_security_group.mafs-sg.id
}

resource "azurerm_public_ip" "mafs-ip" {
  name                = "mafs-ip"
  resource_group_name = azurerm_resource_group.mafs-rg.name
  location            = azurerm_resource_group.mafs-rg.location
  allocation_method   = "Dynamic"

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_interface" "mafs-nic" {
  name                = "mafs-nic"
  location            = azurerm_resource_group.mafs-rg.location
  resource_group_name = azurerm_resource_group.mafs-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.mafs-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.mafs-ip.id
  }

  tags = {
    environment = "dev"
  }
}

resource "azurerm_linux_virtual_machine" "mafs-vm" {
  name                = "mafs-vm"
  resource_group_name = azurerm_resource_group.mafs-rg.name
  location            = azurerm_resource_group.mafs-rg.location
  size                = "Standard_B1s"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.mafs-nic.id,
  ]

  custom_data = filebase64("customdata.tpl")

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/mafsazurekey.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  provisioner "local-exec" {
    command = templatefile("${var.host_os}-ssh-script.tpl", {
      hostname     = self.public_ip_address,
      user         = "adminuser",
      identityfile = "~/.ssh/mafsazurekey"
    })
    interpreter = var.host_os == "windows" ? ["Powershell", "-Command"] : ["bash", "-c"]
  }

  tags = {
    environment = "dev"
  }
}

data "azurerm_public_ip" "mafs-ip-data" {
  name                = azurerm_public_ip.mafs-ip.name
  resource_group_name = azurerm_resource_group.mafs-rg.name
}

output "public_ip_address" {
  value       = "${azurerm_linux_virtual_machine.mafs-vm.name}: ${data.azurerm_public_ip.mafs-ip-data.ip_address}"
}