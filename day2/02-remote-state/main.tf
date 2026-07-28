# Day 2 — Demo 02: リモート状態管理 (Azure Blob Backend)
# ===========================================
# Step 1: まずこのファイルでバックエンド用ストレージを作成
# Step 2: backend.tf で Azure Blob バックエンドを設定
# ===========================================

terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.2"
    }
  }

  # ──────────────────────────────────────────
  # Step 2: 下記のコメントを解除してリモート状態を有効化
  # ──────────────────────────────────────────
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "stterraformstate001"   # ← 一意な名前に変更
  #   container_name       = "tfstate"
  #   key                  = "workshop/demo.tfstate"
  # }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

variable "subscription_id" {
  type = string
}

variable "location" {
  type    = string
  default = "japaneast"
}

# ===========================================
# Step 1: バックエンド用ストレージの事前準備
# (Azure CLI でも可: setup-backend.sh を参照)
# ===========================================

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-terraform-state"
  location = var.location
}

resource "azurerm_storage_account" "tfstate" {
  name                     = "stterraformstate001" # ← グローバルで一意な名前に変更
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # セキュリティのベストプラクティス
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true # 状態ファイルのバージョン管理
  }

  tags = {
    purpose    = "terraform-state"
    managed_by = "terraform"
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# ===========================================
# 出力: backend 設定に必要な値
# ===========================================
output "backend_config" {
  value = {
    resource_group_name  = azurerm_resource_group.tfstate.name
    storage_account_name = azurerm_storage_account.tfstate.name
    container_name       = azurerm_storage_container.tfstate.name
    note                 = "backend ブロックの key にはプロジェクトごとのパスを指定"
  }
}
