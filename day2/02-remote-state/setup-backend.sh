#!/bin/bash
# ===========================================
# バックエンド用 Azure Storage の事前セットアップ
# ===========================================
# このスクリプトは Azure CLI で状態管理用のストレージを作成します。
# Terraform の backend ブロックに必要な情報を出力します。

set -euo pipefail

RESOURCE_GROUP="rg-terraform-state"
LOCATION="japaneast"
STORAGE_ACCOUNT="stterraformstate001"  # ← 一意な名前に変更してください
CONTAINER="tfstate"

echo "=== リソースグループ作成 ==="
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION"

echo "=== ストレージアカウント作成 ==="
az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --allow-blob-public-access false

echo "=== Blob コンテナ作成 ==="
az storage container create \
  --name "$CONTAINER" \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode login

echo ""
echo "=== backend 設定 ==="
cat <<EOF
terraform {
  backend "azurerm" {
    resource_group_name  = "$RESOURCE_GROUP"
    storage_account_name = "$STORAGE_ACCOUNT"
    container_name       = "$CONTAINER"
    key                  = "workshop/demo.tfstate"
  }
}
EOF
