output "resource_group_name" { value = azurerm_resource_group.main.name }
output "aks_name" { value = azurerm_kubernetes_cluster.main.name }
output "namespace" { value = local.namespace }
output "postgres_fqdn" { value = azurerm_postgresql_flexible_server.main.fqdn }
output "key_vault_name" { value = azurerm_key_vault.main.name }
output "oidc_issuer_url" { value = azurerm_kubernetes_cluster.main.oidc_issuer_url }
