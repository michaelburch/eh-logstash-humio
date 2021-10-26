terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.71.0"
    }
  }
}

provider "azurerm" {
  features {}
}

terraform {
  backend "azurerm" {
    resource_group_name  = "common"
    storage_account_name = "commons1014"
    container_name       = "terraform"
    key                  = "tfstate-eh-logstash-humio"
  }
}
data "azurerm_client_config" "current" {
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}


module "network" {
  source                       = "github.com/michaelburch/azure-terraform.git//modules/virtual_network?ref=v0.0.1"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = var.location
  vnet_name                    = var.vnet_name
  address_space                = var.address_space
  tags                         = var.tags

  subnets = [
    {
      name : "serverSubnet"
      address_prefixes : var.server_subnet_address_prefix
      enforce_private_link_endpoint_network_policies : true
      enforce_private_link_service_network_policies : false
    },
    {
      name : var.cluster_subnet_name
      address_prefixes : var.cluster_subnet_address_prefix
      enforce_private_link_endpoint_network_policies : true
      enforce_private_link_service_network_policies : false
    }
  ]
}

module "log_analytics_workspace" {
  source                           = "git::https://github.com/michaelburch/azure-terraform.git//modules/log_analytics?ref=v0.0.1"
  name                             = var.log_analytics_workspace_name
  location                         = var.location
  resource_group_name              = azurerm_resource_group.rg.name
  solution_plan_map                = var.solution_plan_map
}

module "aks_cluster" {
  source                                   = "git::https://github.com/michaelburch/azure-terraform.git//modules/aks?ref=v0.0.1"
  name                                     = var.aks_cluster_name
  location                                 = var.location
  resource_group_name                      = azurerm_resource_group.rg.name
  dns_prefix                               = lower(var.aks_cluster_name)
  private_cluster_enabled                  = true
  sku_tier                                 = var.sku_tier
  vnet_subnet_id                           = module.network.subnet_ids[var.cluster_subnet_name]
  default_node_pool_node_taints            = var.default_node_pool_node_taints
  default_node_pool_enable_host_encryption = false
  default_node_pool_min_count              = 1
  default_node_pool_node_count             = 1
  tags                                     = var.tags
  log_analytics_workspace_id               = module.log_analytics_workspace.id
  tenant_id                                = data.azurerm_client_config.current.tenant_id
  admin_group_object_ids                   = var.admin_group_object_ids
  admin_username                           = var.admin_username
  ssh_public_key                           = file(var.ssh_public_key)
  ingress_application_gateway              = {enabled      = true           
                                              gateway_id   = null
                                              gateway_name = null
                                              subnet_cidr  = var.aks_app_gateway_subnet 
                                              subnet_id    = null}
  node_pools                               = [
    {
      name: "userpool1"
      node_sku: "Standard_F8s_v2"
      node_count: 2
    }
  ]
  depends_on                               = [module.network, module.log_analytics_workspace]

}
# If using AGIC and specifying a subnet cidr, the cluster identity will
# need contributor access to the cluster vnet to add the subnet
resource "azurerm_role_assignment" "agic_vnet_contributor" {
  count                = module.aks_cluster.ingress_identity_id != null ? 1 : 0
  scope                = module.network.vnet_id         
  role_definition_name = "Contributor"
  principal_id         = module.aks_cluster.ingress_identity_id
}
# Cluster Identity will be used for load balancers
resource "azurerm_role_assignment" "aks_vnet_contributor" {
  count                = module.aks_cluster.cluster_identity_id != null ? 1 : 0
  scope                = module.network.vnet_id         
  role_definition_name = "Contributor"
  principal_id         = module.aks_cluster.cluster_identity_id
}
# Route spokes through hub vnet
module "routetable" {
  source               = "git::https://github.com/michaelburch/azure-terraform.git//modules/route_table?ref=v0.0.1"
  depends_on           = [module.network]
  resource_group_name  = azurerm_resource_group.rg.name
  location             = var.location
  route_table_name     = "hub-nva-routes"
  nva_private_ip       = "192.168.24.132"
  subnets_to_associate = {
    (var.cluster_subnet_name) = {
      subscription_id      = data.azurerm_client_config.current.subscription_id
      resource_group_name  = azurerm_resource_group.rg.name
      virtual_network_name = module.network.name
    }
  }
}

module "eventhub" {
  source                       = "git::https://github.com/michaelburch/azure-terraform.git//modules/event_hub?ref=v0.0.2"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = var.location
  namespace_name               = "humiodemoeh"
  tags                         = var.tags
  allowed_subnets              = [module.network.subnet_ids["serverSubnet"], module.network.subnet_ids[var.cluster_subnet_name]]
  allowed_ips                  = ["192.168.16.0/22"]
  hubs = [
    {
      name : "logging"
      partition_count: 2
      message_retention: 1
    }
  ]
}
resource "azurerm_eventhub_consumer_group" "logstash" {
  name                = "logstash"
  namespace_name      = module.eventhub.name
  eventhub_name       = "logging"
  resource_group_name = azurerm_resource_group.rg.name
}

module "eh_private_dns_zone" {
  source                       = "git::https://github.com/michaelburch/azure-terraform.git//modules/private_dns_zone?ref=v0.0.1"
  name                         = "privatelink.servicebus.windows.net"
  resource_group_name          = azurerm_resource_group.rg.name
  virtual_networks_to_link     = {
    (module.network.name) = {
      subscription_id = data.azurerm_client_config.current.subscription_id
      resource_group_name = azurerm_resource_group.rg.name
    }
  }
}

module "eh_private_endpoint" {
  source                         = "github.com/michaelburch/azure-terraform.git//modules/private_endpoint?ref=v0.0.1"
  name                           = "${module.eventhub.name}PrivateEndpoint"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.rg.name
  subnet_id                      = module.network.subnet_ids["serverSubnet"]
  tags                           = var.tags
  private_connection_resource_id = module.eventhub.id
  is_manual_connection           = false
  subresource_name               = "namespace"
  private_dns_zone_group_name    = "EventHubPrivateDnsZoneGroup"
  private_dns_zone_group_ids     = [module.eh_private_dns_zone.id]
}