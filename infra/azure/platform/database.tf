resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}
resource "random_password" "postgres" {
  length           = 32
  special          = true
  override_special = "!#%*-_=+?"
}
resource "azurerm_postgresql_flexible_server" "main" {
  name                          = "psql-${local.name}-${random_string.suffix.result}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = var.location
  version                       = "16"
  delegated_subnet_id           = azurerm_subnet.database.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false
  administrator_login           = "platformadmin"
  administrator_password        = random_password.postgres.result
  sku_name                      = "GP_Standard_D2s_v3"
  storage_mb                    = 32768
  backup_retention_days         = 14
  geo_redundant_backup_enabled  = false
  tags                          = local.tags
  dynamic "high_availability" {
    for_each = var.environment == "prod" ? [1] : []
    content { mode = "ZoneRedundant" }
  }
  lifecycle { prevent_destroy = true }
  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}
resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = "appdb"
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
resource "azurerm_postgresql_flexible_server_configuration" "tls" {
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "ON"
}
resource "azurerm_monitor_diagnostic_setting" "postgres" {
  name                       = "postgres-audit"
  target_resource_id         = azurerm_postgresql_flexible_server.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  enabled_log { category_group = "allLogs" }
  enabled_metric { category = "AllMetrics" }
}
