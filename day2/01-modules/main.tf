# Day 2 — Demo 01: モジュールの作成と利用
# ===========================================
# ローカルモジュールを呼び出してリソースを作成します。
# 依存関係（depends_on / 暗黙的参照）もデモします。
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

variable "subscription_id" {
  type = string
}

variable "location" {
  type    = string
  default = "japaneast"
}

# -------------------------------------------------
# リソースグループ（モジュールの前に作成される = 暗黙的依存関係）
# -------------------------------------------------
resource "azurerm_resource_group" "demo" {
  name     = "rg-module-demo"
  location = var.location
}

# -------------------------------------------------
# モジュール呼び出し: ストレージアカウント
# -------------------------------------------------
module "storage_app" {
  source = "./modules/storage"

  name                = "stmoduledemoapp001"
  resource_group_name = azurerm_resource_group.demo.name # ← 暗黙的依存
  location            = azurerm_resource_group.demo.location

  containers = [
    { name = "data" },
    { name = "logs" },
  ]

  tags = {
    role       = "application"
    managed_by = "terraform"
  }
}

# 2 つ目のモジュール呼び出し（同じモジュールを再利用）
module "storage_backup" {
  source = "./modules/storage"

  name                = "stmoduledemobackup01"
  resource_group_name = azurerm_resource_group.demo.name
  location            = azurerm_resource_group.demo.location
  replication_type    = "GRS" # バックアップは GRS

  containers = [
    { name = "backups" },
  ]

  tags = {
    role       = "backup"
    managed_by = "terraform"
  }
}

# -------------------------------------------------
# 出力: モジュールの output を参照
# -------------------------------------------------
output "app_storage_name" {
  value = module.storage_app.storage_account_name
}

output "app_storage_containers" {
  value = module.storage_app.container_names
}

output "backup_storage_name" {
  value = module.storage_backup.storage_account_name
}

# ===========================================
# デモ手順:
#   1. modules/storage/ の構成を確認（variables / main / outputs）
#   2. terraform init   — モジュールを初期化
#   3. terraform plan   — モジュール呼び出しの依存グラフを確認
#   4. terraform apply  — 2つのストレージアカウントが作成される
#   5. terraform output — モジュール出力を確認
# ===========================================
