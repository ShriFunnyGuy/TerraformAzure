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
  features {}
  
}
resource "azurerm_resource_group" "resource_group" {
  name     = "windowsvm-resources"
  location = "West Europe"
}
resource "azurerm_public_ip" "public_ip" {
    name                = "windowsvm-ip"
    location            = azurerm_resource_group.resource_group.location
    resource_group_name = azurerm_resource_group.resource_group.name
    allocation_method   = "Static"
}



resource "azurerm_virtual_network" "virtual_network" {
    name                = "windowsvm-network"
    address_space       = ["10.0.0.0/16"]
    location            = azurerm_resource_group.resource_group.location
    resource_group_name = azurerm_resource_group.resource_group.name
}
resource "azurerm_subnet" "subnet" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes     = ["10.0.2.0/24"]
}
resource "azurerm_network_interface" "network_interface" {
  name                = "windowsvm-nic"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}
resource "azurerm_network_security_group" "network_security_group" {
  name                = "windowsvm-nsg"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

    security_rule {
        name="WinRM"
        priority=1000
        direction="Inbound"
        access="Allow"
        protocol="Tcp"
        source_port_range="*"
        destination_port_ranges=["5986"]
        source_address_prefix="*"
        destination_address_prefix="*"
    }
  security_rule {
    name                       = "RDP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["3389"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
}
resource "azurerm_network_interface_security_group_association" "nic_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.network_interface.id
  network_security_group_id = azurerm_network_security_group.network_security_group.id
}

resource "azurerm_windows_virtual_machine" "windows_vm" {
  name                = "windowsvm-vm"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  size                = "Standard_DS1_v2"
  admin_username      = "adminuser"
  admin_password      = "P@ssw0rd1234!"
  network_interface_ids = [azurerm_network_interface.network_interface.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
   /*provisioner "remote-exec" {
    inline = [
        "Install-WindowsFeature -Name Web-Server -IncludeManagementTools",
        "Remove-Item -Path 'C:\\inetpub\\wwwroot\\*.htm' -Force -ErrorAction SilentlyContinue",
        "Set-Content -Path 'C:\\inetpub\\wwwroot\\index.html' -Value '<html><body><h1>Hello from Terraform & IIS!</h1></body></html>'"
    ]

    connection {
        type     = "winrm"
        host     = azurerm_public_ip.public_ip.ip_address
        user     = "adminuser"
        password = "P@ssw0rd1234!"
        port     = 5986
        https    = true
        timeout  = "5m"
        }
    }*/
}

resource "azurerm_virtual_machine_extension" "iis_extension" {
  name                 = "IIS"
  virtual_machine_id   = azurerm_windows_virtual_machine.windows_vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    commandToExecute = <<EOT
powershell -Command "Install-WindowsFeature -name Web-Server -IncludeManagementTools; Remove-Item -Path 'C:\\inetpub\\wwwroot\\*.htm' -Force -ErrorAction SilentlyContinue; Add-Content -Path 'C:\\inetpub\\wwwroot\\iisstart.htm' -Value $('Hello World from ' + $env:computername)"
EOT
  })
}

output "public_ip_address" {
  value = azurerm_public_ip.public_ip.ip_address
}
output app_url {
  value = "http://${azurerm_public_ip.public_ip.ip_address}:80"
}