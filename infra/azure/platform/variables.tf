variable "subscription_id" { type = string }
variable "platform_admin_group_id" {
  description = "Existing Entra group object ID; receives AKS RBAC Cluster Admin."
  type        = string
}
variable "app_deployer_object_id" {
  description = "Existing Entra user/SP object ID for the separate application Terraform stage."
  type        = string
}
variable "location" {
  type    = string
  default = "australiaeast"
}
variable "prefix" {
  type    = string
  default = "cicdlearn"
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,11}$", var.prefix))
    error_message = "Use 3-12 lowercase alphanumeric characters, starting with a letter."
  }
}
variable "environment" {
  type    = string
  default = "dev"
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Use dev, test or prod."
  }
}
variable "owner" {
  type    = string
  default = "platform-team"
}
variable "cost_center" {
  type    = string
  default = "learning"
}
variable "node_vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}

locals {
  name      = "${var.prefix}-${var.environment}"
  namespace = "cicd-azure"
  tags = {
    environment = var.environment
    owner       = var.owner
    cost_center = var.cost_center
    managed_by  = "terraform"
  }
}
