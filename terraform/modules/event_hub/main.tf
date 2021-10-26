
resource "azurerm_eventhub_namespace" "namespace" {
  name                = var.namespace_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  capacity            = var.capacity
  tags                = var.tags
  network_rulesets    = [ 
    { 
      default_action = "Deny"
      trusted_service_access_enabled = true
      virtual_network_rule = [
        for subnet in var.allowed_subnets: {
          subnet_id                                       = subnet
          ignore_missing_virtual_network_service_endpoint = true
        }
      ]
      ip_rule = [
        for ip in var.allowed_ips: {
          ip_mask = ip
          action  = "Allow"
        }
      ]
    }
   ]
}

resource "azurerm_eventhub" "hub" {
  for_each = { for hub in var.hubs : hub.name => hub }

  name                                           = each.key
  resource_group_name                            = var.resource_group_name
  namespace_name                                 = azurerm_eventhub_namespace.namespace.name
  partition_count                                = each.value.partition_count 
  message_retention                              = each.value.message_retention

}