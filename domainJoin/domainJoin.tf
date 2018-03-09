#Variables
variable "rsg" { default = "TossDCLab" } 
variable "location" { default = "eastus2" } 
variable "hostname" { default = "tfbox18" } 
variable "username" { default = "<local_admin_UserID>" } 
variable "password" { default = "<local_admin_Password>" } 
variable "vmsize" { default = "Standard_DS1_v2" } 
variable "storagetype" { default = "Premium_LRS" } 
variable "sku" { default = "2016-Datacenter" } 
variable "environment" { default = "Production"}

# Build the Resource Group
resource "azurerm_resource_group" "rsg" {
  name = "${var.rsg}"
  location = "${var.location}"
}

#Build the Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name = "TossDCLab-vnet"
  address_space = ["172.16.1.0/24"]
  location = "${var.location}"
  resource_group_name = "${var.rsg}"
  dns_servers = ["172.16.1.4"]
}
# Build subnet
resource "azurerm_subnet" "subnet1" {
  name = "default"
  resource_group_name = "${var.rsg}"
  virtual_network_name = "TossDCLab-vnet"
  address_prefix = "172.16.1.0/24"
}
# Create Public IP 
resource "azurerm_public_ip" "pip" {
  name = "${var.hostname}-pip" location = "${var.location}" resource_group_name = "${azurerm_resource_group.rsg.name}" 
  public_ip_address_allocation = "static"

  tags {
    environment = "Production"
  }
}

# Network Security Group
resource "azurerm_network_security_group" "nsg" {
  name = "${var.rsg}-nsg"
  location = "${var.location}"
  resource_group_name = "${azurerm_resource_group.rsg.name}"
  security_rule {
    name = "RDP"
    priority = 100
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = 3389
    destination_port_range = 3389
    source_address_prefix = "10.0.0.0/8"
    destination_address_prefix = "*"
  }
  tags {
    environment = "Production"
  }
}
# Set the private and public IP
resource "azurerm_network_interface" "ni" {
  name = "${var.hostname}-ni"
  location = "${var.location}"
  resource_group_name = "${azurerm_resource_group.rsg.name}"
  network_security_group_id = "${azurerm_network_security_group.nsg.id}"
  # dynamic IP configuration
  ip_configuration {
    name = "${var.hostname}-ipconfig"
    subnet_id = "${azurerm_subnet.subnet1.id}"
    private_ip_address_allocation = "dynamic"
  }
}
# Build Virtual Machine
resource "azurerm_virtual_machine" "vm" {
  name = "${var.hostname}"
  location = "${var.location}"
  resource_group_name = "${azurerm_resource_group.rsg.name}"
  network_interface_ids = ["${azurerm_network_interface.ni.id}"]
  vm_size = "${var.vmsize}"
  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer = "WindowsServer"
    sku = "${var.sku}"
    version = "latest"
  }
  storage_os_disk {
    name = "${var.hostname}-osdisk"
    caching = "ReadWrite"
    create_option = "FromImage"
    managed_disk_type = "${var.storagetype}"
  }
os_profile {
    computer_name = "${var.hostname}"
    admin_username = "${var.username}"
    admin_password = "${var.password}"
  }
  os_profile_windows_config {
    enable_automatic_upgrades = true
    provision_vm_agent = true
  }
  tags {
    environment = "Production"
  }
}
resource "azurerm_virtual_machine_extension" "join-domain" {
  name = "${azurerm_virtual_machine.vm.name}"
  location = "${var.location}"
  resource_group_name = "${azurerm_resource_group.rsg.name}"
  virtual_machine_name = "${azurerm_virtual_machine.vm.name}"
  publisher = "Microsoft.Compute"
  type = "JsonADDomainExtension" 
  type_handler_version = "1.0"

  settings = <<SETTINGS
    {
        "Name": "griffith.com",
        "OUPath": "",
        "User": "griffith.com\\griffith",
        "Restart": "true",
        "Options": "3"
    }
SETTINGS

  protected_settings = <<SETTINGS
    {
        "Password": "<domain_admin_Password>"
    }
SETTINGS

  depends_on = ["null_resource.wait-for-domain-to-provision"]
}
