# Day 1 — Demo 04: Import & Data Source & Moved Blocks
# ===========================================
# 既存リソースの取り込み (import) と
# データソースによる既存リソースの参照をデモします。
#
# 深掘りトピック:
#   - moved ブロック（リファクタリング時のリソースアドレス変更）
#   - terraform plan -generate-config-out（リソースブロック自動生成）
#   - import ブロック (宣言的 import) vs CLI import (命令的)
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

# ===========================================
# Part 1: Data Source — 既存リソースの参照
# ===========================================

# サブスクリプション情報を取得
data "azurerm_subscription" "current" {}

# クライアント設定を取得
data "azurerm_client_config" "current" {}

# 既存のリソースグループを参照（事前に作成済みである必要あり）
# data "azurerm_resource_group" "existing" {
#   name = "rg-existing-resources"
# }

output "subscription_info" {
  value = {
    subscription_id   = data.azurerm_subscription.current.subscription_id
    display_name      = data.azurerm_subscription.current.display_name
    tenant_id         = data.azurerm_client_config.current.tenant_id
    current_object_id = data.azurerm_client_config.current.object_id
  }
}

# ===========================================
# Part 2: terraform import — 既存リソースの取り込み
# ===========================================

# Step 1: まず Azure CLI でリソースグループを手動作成
#   az group create -n rg-import-demo -l japaneast

# Step 2: Terraform にリソースブロックを定義
resource "azurerm_resource_group" "imported" {
  name     = "rg-import-demo"
  location = var.location

  tags = {
    managed_by = "terraform"
    imported   = "true"
  }
}

# Step 3-A: CLI で import を実行 (従来方式)
#   terraform import azurerm_resource_group.imported /subscriptions/<SUB_ID>/resourceGroups/rg-import-demo

# Step 3-B: import ブロックを使用 (Terraform 1.5+ 推奨方式)
# import {
#   to = azurerm_resource_group.imported
#   id = "/subscriptions/<SUB_ID>/resourceGroups/rg-import-demo"
# }

# Step 4: import 後に plan を実行して差分を確認
#   terraform plan
#   → tags の追加差分が表示される → apply で同期

# ===========================================
# Part 3: terraform plan -generate-config-out (1.5+)
# ===========================================
# import ブロックだけ書いて、リソースブロックを自動生成:
#
# import {
#   to = azurerm_resource_group.auto_generated
#   id = "/subscriptions/<SUB_ID>/resourceGroups/rg-import-demo"
# }
#
# 実行手順:
#   terraform plan -generate-config-out=generated.tf
#   → generated.tf に resource ブロックが自動生成される
#   → 生成されたコードを確認・調整してから apply
#
# ⚠ 注意: 生成コードはそのままでは不完全な場合がある。
#   - 不要な属性（computed 値）が含まれる
#   - lifecycle や変数化は手動で追加が必要
#   - レビュー後に apply するのがベストプラクティス

# ===========================================
# Part 4: moved ブロック — リファクタリング (Terraform 1.1+)
# ===========================================
# リソースのアドレス（名前）を変更したい場合、
# moved ブロックを使うと destroy + create せずに状態だけ移動できる。
#
# 例: azurerm_resource_group.imported → azurerm_resource_group.main にリネーム
#
# moved {
#   from = azurerm_resource_group.imported
#   to   = azurerm_resource_group.main
# }
#
# resource "azurerm_resource_group" "main" {
#   name     = "rg-import-demo"
#   location = var.location
#   tags = {
#     managed_by = "terraform"
#     imported   = "true"
#   }
# }
#
# 使用シナリオ:
#   - リソース名の変更（例: "demo" → "main"）
#   - モジュール化（例: azurerm_storage_account.demo → module.storage.azurerm_storage_account.this）
#   - for_each への移行（例: resource.name → resource.name["key"]）
#
# デモ手順:
#   1. まず azurerm_resource_group.imported を apply して作成
#   2. moved ブロックを追加し、resource 名を main に変更
#   3. terraform plan → "moved" と表示される（destroy なし！）
#   4. terraform apply → 状態ファイル内のアドレスだけ更新
#   5. moved ブロックは apply 後に削除可能（1回限りの指示）

# ===========================================
# デモ手順:
#   1. az group create -n rg-import-demo -l japaneast
#   2. import ブロックのコメントを解除して ID を設定
#   3. terraform plan -generate-config-out=generated.tf
#   4. 生成された generated.tf を確認
#   5. terraform apply で状態を同期
#   6. terraform state list で確認
#   7. terraform state show azurerm_resource_group.imported
# ===========================================
