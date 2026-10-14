resource "azurerm_user_assigned_identity" "aks" {
  name                = "id-${local.name}-aks"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.tags
}
resource "azurerm_role_assignment" "aks_network" {
  scope                = azurerm_subnet.aks.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${local.name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_kubernetes_cluster" "main" {
  name                              = "aks-${local.name}"
  location                          = var.location
  resource_group_name               = azurerm_resource_group.main.name
  dns_prefix                        = local.name
  private_cluster_enabled           = true
  local_account_disabled            = true
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  azure_policy_enabled              = true
  automatic_upgrade_channel         = "patch"
  node_os_upgrade_channel           = "NodeImage"
  sku_tier                          = "Standard"
  tags                              = local.tags

  default_node_pool {
    name                 = "system"
    vm_size              = var.node_vm_size
    vnet_subnet_id       = azurerm_subnet.aks.id
    auto_scaling_enabled = true
    min_count            = 2
    max_count            = 4
    node_count           = 2
    tags                 = local.tags
    upgrade_settings { max_surge = "33%" }
  }
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }
  azure_active_directory_role_based_access_control {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled = true
  }
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "calico"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.41.0.0/16"
    dns_service_ip      = "10.41.0.10"
    load_balancer_sku   = "standard"
  }
  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.main.id
    msi_auth_for_monitoring_enabled = true
  }
  key_vault_secrets_provider { secret_rotation_enabled = true }
  lifecycle { ignore_changes = [default_node_pool[0].node_count] }
  depends_on = [azurerm_role_assignment.aks_network]
}

# Human platform administrators only. Application CI gets namespace scope below.
resource "azurerm_role_assignment" "platform_admin" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = var.platform_admin_group_id
}
resource "azurerm_role_assignment" "credentials" {
  for_each             = toset([var.platform_admin_group_id, var.app_deployer_object_id])
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = each.value
}
resource "azurerm_role_assignment" "app_deployer" {
  scope                = "${azurerm_kubernetes_cluster.main.id}/namespaces/${local.namespace}"
  role_definition_name = "Azure Kubernetes Service RBAC Writer"
  principal_id         = var.app_deployer_object_id
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "aks-audit"
  target_resource_id         = azurerm_kubernetes_cluster.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  enabled_log { category_group = "allLogs" }
  enabled_metric { category = "AllMetrics" }
}
