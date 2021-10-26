output "name" {
  description = "Specifies the name of the eventhub namepsace"
  value       = azurerm_eventhub_namespace.namespace.name
}

output "id" {
  description = "Specifies the resource id eventhub namespace"
  value       = azurerm_eventhub_namespace.namespace.id
}

output "connection_string" {
    description = "default primary connection string"
    value = azurerm_eventhub_namespace.namespace.default_primary_connection_string
}