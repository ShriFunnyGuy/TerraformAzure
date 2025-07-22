terraform {
    required_providers {
        azurerm = {
        source  = "hashicorp/azurerm"
        version = "=4.37.0"
        }
    }
    
    required_version = ">= 0.12"
}
provider "azurerm" {
    features {
      
    }
   
}

data "azurerm_platform_image" "openwebui" {
  location  = azurerm_resource_group.openwebui.location
  publisher = "Debian"
  offer     = "debian-11"
  sku       = "11"
}

resource "azurerm_resource_group" "openwebui" {
  name     = "example-resources"
  location = "West Europe"
}

resource "azurerm_virtual_network" "openwebui" {
  name                = "example-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.openwebui.location
  resource_group_name = azurerm_resource_group.openwebui.name
}

resource "azurerm_subnet" "openwebui" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.openwebui.name
  virtual_network_name = azurerm_virtual_network.openwebui.name
  address_prefixes = [cidrsubnet(tolist(azurerm_virtual_network.openwebui.address_space)[0], 8, 2)]
}

resource "azurerm_public_ip" "openwebui" {
  name                = "openwebui-ip"
  location            = azurerm_resource_group.openwebui.location
  resource_group_name = azurerm_resource_group.openwebui.name
  allocation_method   = "Static"
  
}

resource "azurerm_network_interface" "openwebui" {
  name                = "example-nic"
  location            = azurerm_resource_group.openwebui.location
  resource_group_name = azurerm_resource_group.openwebui.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.openwebui.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.openwebui.id
  }
}

resource "azurerm_network_security_group" "openwebui" {
  name                = "example-nsg"
  location            = azurerm_resource_group.openwebui.location
  resource_group_name = azurerm_resource_group.openwebui.name

  security_rule {
    name                       = "SSH"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["22"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }


  security_rule {
    name                       = "HTTP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
}

resource "azurerm_network_interface_security_group_association" "openwebui" {
  network_interface_id      = azurerm_network_interface.openwebui.id
  network_security_group_id = azurerm_network_security_group.openwebui.id
}

resource "azurerm_linux_virtual_machine" "openwebui" {
  name                = "example-machine"
  resource_group_name = azurerm_resource_group.openwebui.name
  location            = azurerm_resource_group.openwebui.location
  size                = "Standard_A2_v2"
  admin_username      = "openwebui"
  network_interface_ids = [
    azurerm_network_interface.openwebui.id,
  ]

    disable_password_authentication = true

  admin_ssh_key {
    username   = "openwebui"
    public_key = file("/temp/id_rsa.pub")
  }

source_image_reference {
    publisher = data.azurerm_platform_image.openwebui.publisher
    offer     = data.azurerm_platform_image.openwebui.offer
    sku       = data.azurerm_platform_image.openwebui.sku
    version   = data.azurerm_platform_image.openwebui.version
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  
   connection {
      type        = "ssh"
      user        = "openwebui"
      private_key = file("/temp/id_rsa")
      host        = azurerm_public_ip.openwebui.ip_address
    }
  provisioner "file" {
    source      = "app.py"
    destination = "/home/openwebui/app.py"
  }
  provisioner "remote-exec" {
  inline = [
    "echo 'Updating package list...'",
    "sudo apt-get update -y",
    "sudo apt-get install -y ca-certificates curl gnupg lsb-release",

    "sudo mkdir -p /etc/apt/keyrings",
    "curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",

    "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",

    "sudo apt-get update -y",
    "sudo apt-get install -y docker-ce docker-ce-cli containerd.io",

    "sudo systemctl start docker",
    "sudo systemctl enable docker",

    "sudo docker run -d -p 80:80 --name openwebui nginx"
  ]
}
}
output "openwebui_ip" {
    value = azurerm_public_ip.openwebui.ip_address
  }