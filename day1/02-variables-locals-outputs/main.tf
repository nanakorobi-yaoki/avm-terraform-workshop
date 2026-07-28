# Day 1 — Demo 02: 変数・ローカル値・出力
# ===========================================
# variable / locals / output の使い分けをデモします
# ===========================================

terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.2"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# -------------------------------------------------
# リソースグループ
# -------------------------------------------------
resource "azurerm_resource_group" "demo" {
  name     = local.resource_group_name
  location = var.location

  tags = local.common_tags
}

# -------------------------------------------------
# ストレージアカウント
# -------------------------------------------------
resource "azurerm_storage_account" "demo" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.demo.name
  location                 = azurerm_resource_group.demo.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type

  tags = local.common_tags
}
