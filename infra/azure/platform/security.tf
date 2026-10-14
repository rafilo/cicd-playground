resource "azurerm_key_vault" "main" {
  name                          = "kv${var.prefix}${var.environment}${random_string.suffix.result}"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.main.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  public_network_access_enabled = false
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  tags                          = local.tags
}
resource "azurerm_private_dns_zone" "vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}
resource "azurerm_private_dns_zone_virtual_network_link" "vault" {
  name                  = "vault-vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.vault.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = local.tags
}
resource "azurerm_private_endpoint" "vault" {
  name                = "pe-${local.name}-vault"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  subnet_id           = azurerm_subnet.endpoints.id
  tags                = local.tags
  private_service_connection {
    name                           = "vault"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "vault"
    private_dns_zone_ids = [azurerm_private_dns_zone.vault.id]
  }
}
# Provisioning identity may write secrets, but the demo application cannot read
# the database administrator credential. Use a separate least-privilege DB user
# and per-secret Workload Identity grant when adding actual database code.
resource "azurerm_role_assignment" "secret_writer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
resource "azurerm_key_vault_secret" "postgres_admin" {
  name         = "postgres-admin-password"
  value        = random_password.postgres.result
  key_vault_id = azurerm_key_vault.main.id
  content_type = "PostgreSQL administrator password; not an application credential"
  depends_on   = [azurerm_private_endpoint.vault, azurerm_private_dns_zone_virtual_network_link.vault, azurerm_role_assignment.secret_writer]
}
resource "azurerm_monitor_diagnostic_setting" "vault" {
  name                       = "vault-audit"
  target_resource_id         = azurerm_key_vault.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  enabled_log { category_group = "allLogs" }
  enabled_metric { category = "AllMetrics" }
}

# Custom, reviewable governance policy; does not claim regulatory certification.
resource "azurerm_policy_definition" "tags" {
  name         = "${local.name}-required-tags"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Require ownership and cost tags on taggable resources"
  policy_rule = jsonencode({
    if = { anyOf = [for tag in ["owner", "environment", "cost_center", "managed_by"] : {
      field = "tags['${tag}']", exists = "false"
    }] }
    then = { effect = "deny" }
  })
}
resource "azurerm_resource_group_policy_assignment" "tags" {
  name                 = "required-tags"
  resource_group_id    = azurerm_resource_group.main.id
  policy_definition_id = azurerm_policy_definition.tags.id
  display_name         = "Require platform resource tags"
}
data "azurerm_policy_set_definition" "pod_security" {
  display_name = "Kubernetes cluster pod security baseline standards for Linux-based workloads"
}
resource "azurerm_resource_group_policy_assignment" "pod_security" {
  name                 = "pod-security"
  resource_group_id    = azurerm_resource_group.main.id
  policy_definition_id = data.azurerm_policy_set_definition.pod_security.id
  parameters           = jsonencode({ effect = { value = "audit" } })
  display_name         = "Audit Kubernetes pod security baseline"
}
