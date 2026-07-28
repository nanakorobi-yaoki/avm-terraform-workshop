# Day 1 — Demo 03: AVM Databricks Workspace
# ===========================================
# Azure Verified Modules (AVM) を使って
# Azure Databricks ワークスペースをデプロイします。
#
# AVM モジュール:
#   Registry: https://registry.terraform.io/modules/Azure/avm-res-databricks-workspace/azurerm/latest
#   GitHub:   https://github.com/Azure/terraform-azurerm-avm-res-databricks-workspace
#
# デモポイント:
#   - AVM モジュールの基本的な使い方（source + version）
#   - 一貫インターフェース（tags / diagnostic_settings）
#   - Databricks ワークスペースの SKU 選択（trial / standard / premium）
#   - VNet インジェクション（オプション）
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
# 変数
# -------------------------------------------------
variable "subscription_id" {
  description = "Azure サブスクリプション ID"
  type        = string
}

variable "location" {
  description = "Azure リージョン"
  type        = string
  default     = "japaneast"
}

variable "environment" {
  description = "環境名"
  type        = string
  default     = "dev"
}

# -------------------------------------------------
# ローカル値
# -------------------------------------------------
locals {
  name_prefix = "avm-dbw-demo-${var.environment}"

  common_tags = {
    project     = "avm-terraform-workshop"
    environment = var.environment
    managed_by  = "terraform-avm"
    demo        = "day1-databricks"
  }
}

# -------------------------------------------------
# リソースグループ
# -------------------------------------------------
resource "azurerm_resource_group" "demo" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}

# -------------------------------------------------
# Log Analytics（diagnostic_settings 用）
# -------------------------------------------------
resource "azurerm_log_analytics_workspace" "demo" {
  name                = "law-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.demo.name
  location            = azurerm_resource_group.demo.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

# ===========================================
# AVM Module: Azure Databricks Workspace
# Registry: Azure/avm-res-databricks-workspace/azurerm
# ===========================================
module "databricks" {
  source  = "Azure/avm-res-databricks-workspace/azurerm"
  version = "~> 0.5.0" # 1.0 未満のモジュールはパッチのみ許容で固定

  name                = "dbw-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.demo.name
  location            = azurerm_resource_group.demo.location

  # ── SKU (pricing tier) ──
  # "trial"    → 14 日間無料トライアル
  # "standard" → 標準機能
  # "premium"  → Unity Catalog / RBAC / 監査ログ等
  sku = "premium"

  # ── AVM 一貫インターフェース: tags ──
  tags = local.common_tags

  # ── AVM 一貫インターフェース: diagnostic_settings ──
  diagnostic_settings = {
    to_law = {
      name                  = "diag-databricks"
      workspace_resource_id = azurerm_log_analytics_workspace.demo.id
    }
  }

  # ── AVM 一貫インターフェース: lock ──
  # lock = {
  #   kind = "CanNotDelete"
  #   name = "lock-databricks"
  # }

  # ── VNet インジェクション（オプション）──
  # custom_parameters = {
  #   virtual_network_id                                  = "/subscriptions/.../virtualNetworks/vnet-dbw"
  #   public_subnet_name                                  = "snet-dbw-public"
  #   private_subnet_name                                 = "snet-dbw-private"
  #   public_subnet_network_security_group_association_id  = "..."
  #   private_subnet_network_security_group_association_id = "..."
  # }
}

# -------------------------------------------------
# 出力
# -------------------------------------------------
output "databricks_workspace_url" {
  description = "Databricks ワークスペースの URL"
  value       = module.databricks.databricks_workspace_url
}

output "databricks_workspace_id" {
  description = "Databricks ワークスペースの Azure Resource ID"
  value       = module.databricks.databricks_id
}

output "resource_group_name" {
  description = "リソースグループ名"
  value       = azurerm_resource_group.demo.name
}

# ===========================================
# デモ手順:
#   1. terraform init    — AVM モジュールを Registry からダウンロード
#   2. terraform plan    — Databricks Workspace + RG + LAW の作成プレビュー
#   3. terraform apply   — リソース作成（約 2-3 分）
#   4. terraform output  — ワークスペース URL を確認
#   5. ブラウザで URL にアクセス → Databricks UI を確認
#   6. terraform destroy — クリーンアップ
#
# ポイント:
#   - source + version で AVM モジュールを参照
#   - tags / diagnostic_settings は他の AVM モジュールと同じ構文
#   - sku = "premium" で Unity Catalog 対応
#   - VNet インジェクションはコメントアウトで紹介（時間があれば解説）
# ===========================================
