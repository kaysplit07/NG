provider "azurerm" {
  features {}
}

# terraform {
#   backend "azurerm" {
#     resource_group_name  = "test-dev-eus2-testing-rg"
#     storage_account_name = "6425dveus2aristb01"
#     container_name       = "terraform-state"
#     key                  = "LoadBalancer-terraform.tfstate"
#     access_key = "" 
#     # access_key           = var.storage_account_access_key
#   }
# }


terraform {
  backend "azurerm" {}
}

data "azurerm_subscription" "current" {}  # Read the current subscription info

data "azurerm_client_config" "clientconfig" {}  # Read the current client config

locals {
  get_data = csvdecode(file("../parameters.csv"))
  # Define data for naming standards
  naming = {
    bu                = lower(split("-", data.azurerm_subscription.current.display_name)[1])  # Read app/bu from the subscription data block
    environment       = lower(split("-", data.azurerm_subscription.current.display_name)[2])  # Read environment from subscription data block
    locations         = var.location
    nn                = lower(split("-", data.azurerm_subscription.current.display_name)[3])
    subscription_name = data.azurerm_subscription.current.display_name
    subscription_id   = data.azurerm_subscription.current.id
  }
  env_location = {
    env_abbreviation       = var.environment_map[local.naming.environment]
    locations_abbreviation = var.location_map[local.naming.locations]
  }

  # Extract the full purpose (including sequence) from RGname or var.purpose
  purpose_full = var.RGname != "" ? lower(split("-", var.RGname)[3]) : var.purpose

  # Split the purpose_full into purpose and sequence
  purpose_parts = split("/", local.purpose_full)

  # Assign purpose and sequence, defaulting sequence to "01" if not provided
  purpose    = local.purpose_parts[0]
  sequence   = length(local.purpose_parts) > 1 ? local.purpose_parts[1] : "01"
  purpose_rg = local.purpose
}

data "azurerm_resource_group" "rg" {
  for_each = { for inst in local.get_data : inst.unique_id => inst }
  name     = join("-", [local.naming.bu, local.naming.environment, local.env_location.locations_abbreviation, local.purpose, "rg"])
}

output "resource_group_name" {
  value = data.azurerm_resource_group.rg
}

data "azurerm_virtual_network" "vnet" {
  for_each = { for index, inst in local.get_data : index => inst }
   name = (lookup(each.value, "vnet_name", null) != null && lookup(each.value, "vnet_name", "") != "") ? each.value.vnet_name : join("-", [local.naming.bu, local.naming.environment, local.env_location.locations_abbreviation, "vnet", local.naming.nn])
   resource_group_name  = (lookup(each.value, "vnet_resource_group", null) != null && lookup(each.value, "vnet_resource_group", "") != "") ? each.value.vnet_resource_group : join("-", [local.naming.bu, local.naming.environment, local.env_location.locations_abbreviation, "spokenetwork-rg"])
  
}

output "virtual_network_id" {
  value      = data.azurerm_virtual_network.vnet
  sensitive  = true
}

data "azurerm_subnet" "subnet" {
  for_each = { for index, inst in local.get_data : index => inst }
  name                 = (lookup(each.value, "subnet_name", null) != null && lookup(each.value, "subnet_name", "") != "") ? each.value.subnet_name : var.subnetname //lz<app>-<env>-<region>-<purpose>-snet-<nn>
  virtual_network_name = data.azurerm_virtual_network.vnet[each.key].name
  resource_group_name  = (lookup(each.value, "vnet_resource_group", null) != null && lookup(each.value, "vnet_resource_group", "") != "") ? each.value.vnet_resource_group : join("-", [local.naming.bu, local.naming.environment, local.env_location.locations_abbreviation, "spokenetwork-rg"])
}

output "subnet_id" {
  value      = data.azurerm_subnet.subnet
  sensitive  = true
}

# Azure Load Balancer Resource
resource "azurerm_lb" "internal_lb" {
  for_each            = { for inst in local.get_data : inst.unique_id => inst }
  name                = join("-", ["ari", local.naming.environment, local.env_location.locations_abbreviation, local.purpose_rg, "lbi", local.sequence])
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg[each.key].name
  sku                 = lookup(each.value, "sku_name", var.sku_name)

  frontend_ip_configuration {
    name                          = "internal-${local.purpose_rg}-server-feip"
    subnet_id                     = data.azurerm_subnet.subnet["0"].id
    private_ip_address            = var.private_ip_address  # Use the variable
    private_ip_address_allocation = "Static"
  }
}

# Define Backend Address Pool
resource "azurerm_lb_backend_address_pool" "internal_lb_bepool" {
  for_each        = azurerm_lb.internal_lb
  loadbalancer_id = azurerm_lb.internal_lb[each.key].id
  name            = "internal-${local.purpose_rg}-server-bepool"
}

# Load Balancer Probe
resource "azurerm_lb_probe" "tcp_probe" {
  for_each            = azurerm_lb.internal_lb
  name                = "internal-${local.purpose_rg}-server-tcp-probe"
  loadbalancer_id     = azurerm_lb.internal_lb[each.key].id
  protocol            = "Tcp"
  port                = 20000
  interval_in_seconds = 10
  number_of_probes    = 5
}

# Load Balancer TCP Rule
resource "azurerm_lb_rule" "tcp_rule" {
  for_each                       = azurerm_lb.internal_lb
  name                           = "internal-${local.purpose_rg}-server-tcp-lbrule"
  loadbalancer_id                = azurerm_lb.internal_lb[each.key].id
  protocol                       = "Tcp"
  frontend_port                  = 20000
  backend_port                   = 20000
  frontend_ip_configuration_name = azurerm_lb.internal_lb[each.key].frontend_ip_configuration[0].name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.internal_lb_bepool[each.key].id]
  idle_timeout_in_minutes        = 5
  enable_floating_ip             = false
  enable_tcp_reset               = false
  disable_outbound_snat          = false
  probe_id                       = azurerm_lb_probe.tcp_probe[each.key].id
}

# Load Balancer HTTPS Rule
resource "azurerm_lb_rule" "https_rule" {
  for_each                       = azurerm_lb.internal_lb
  name                           = "internal-${local.purpose_rg}-server-https-lbrule"
  loadbalancer_id                = azurerm_lb.internal_lb[each.key].id
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = azurerm_lb.internal_lb[each.key].frontend_ip_configuration[0].name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.internal_lb_bepool[each.key].id]
  idle_timeout_in_minutes        = 4
  enable_floating_ip             = false
  enable_tcp_reset               = false
  disable_outbound_snat          = false
  probe_id                       = azurerm_lb_probe.tcp_probe[each.key].id
}




Initializing the backend...
╷
│ Error: "storage_account_name": required field is not set
│ 
│ 
╵
╷
│ Error: "container_name": required field is not set
│ 
│ 
╵
╷
│ Error: "key": required field is not set
│ 
│ 
╵

