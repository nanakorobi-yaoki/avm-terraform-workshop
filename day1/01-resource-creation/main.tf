# Day 1 — Demo 01: 基本リソース作成 + ライフサイクル + 状態ファイル
# ===========================================
# このデモでは Terraform の基本ワークフローを体験します:
#   terraform init → terraform plan → terraform apply
#
# 作成するリソース:
#   - Resource Group
#   - Storage Account (lifecycle メタ引数付き)
#
# 深掘りトピック:
#   - lifecycle メタ引数 (prevent_destroy / ignore_changes / create_before_destroy / replace_triggered_by)
#   - Provider エイリアス（マルチリージョン）
#   - terraform.tfstate ファイルの構造を確認
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

# サブスクリプション ID はコードに直接書かず、変数として外出しします。
#   terraform plan -var="subscription_id=<SUB_ID>"
#   もしくは環境変数  TF_VAR_subscription_id / ARM_SUBSCRIPTION_ID
variable "subscription_id" {
  description = "デプロイ先の Azure サブスクリプション ID"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id は GUID 形式で指定してください。"
  }
}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true # キーではなく Azure AD 認証を使用（ポリシー対応）
}

# ===========================================
# Provider エイリアス — マルチリージョンデプロイ
# ===========================================
# 同一プロバイダを別リージョンで使う場合に alias を定義。
# リソース側で provider = azurerm.westus と指定して切り替える。
provider "azurerm" {
  alias = "westus"
  features {}
  subscription_id = var.subscription_id
}

# -------------------------------------------------
# Step 1: リソースグループの作成
# -------------------------------------------------
resource "azurerm_resource_group" "demo" {
  name     = "rg-terraform-demo-day1"
  location = "japaneast"

  tags = {
    environment = "demo"
    workshop    = "avm-terraform-vbd"
  }
}

# Provider エイリアスを使ったマルチリージョン例
# resource "azurerm_resource_group" "demo_west" {
#   provider = azurerm.westus
#   name     = "rg-terraform-demo-day1-westus"
#   location = "westus"
#   tags     = azurerm_resource_group.demo.tags
# }

# -------------------------------------------------
# Step 2: ストレージアカウントの作成 + lifecycle メタ引数
# -------------------------------------------------
resource "azurerm_storage_account" "demo" {
  name                     = "stterraformdemo0721" # ← グローバルで一意な名前
  resource_group_name      = azurerm_resource_group.demo.name
  location                 = azurerm_resource_group.demo.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # サブスクリプションポリシー対応（セキュリティ強化設定）
  shared_access_key_enabled       = false
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false

  tags = azurerm_resource_group.demo.tags

  # ===========================================
  # lifecycle メタ引数 (全リソースタイプで共通)
  # ===========================================
  lifecycle {
    # ── prevent_destroy ──
    # true にすると terraform destroy / 変更による再作成をブロック。
    # 本番 DB・Key Vault など誤削除を防ぎたいリソースに有効。
    # prevent_destroy = true

    # ── ignore_changes ──
    # 指定した属性の差分を plan で無視する。
    # Azure Portal や別チームが tags を変更しても Terraform が上書きしない。
    ignore_changes = [
      tags["updated_by"],
      tags["last_modified"],
    ]

    # ── create_before_destroy ──
    # 名前変更など「置き換え」が必要なとき、新リソースを先に作ってから旧リソースを削除。
    # ダウンタイムを最小化する。
    create_before_destroy = true

    # ── replace_triggered_by ──(Terraform 1.2+）
    # 指定リソース/属性が変わったら、このリソースも強制的に再作成。
    # replace_triggered_by = [azurerm_resource_group.demo.tags]
  }
}

# ===========================================
# デモ手順:
#   1. terraform init    — プロバイダをダウンロード
#   2. terraform plan    — 変更内容をプレビュー
#   3. terraform apply   — リソースを作成
#   4. terraform show    — 作成済みリソースを確認
#   5. terraform destroy — クリーンアップ
#
# 追加デモ — 状態ファイル (terraform.tfstate) の確認:
#   6. cat terraform.tfstate | jq .  — JSON 構造を確認
#      注目ポイント:
#        - "resources" 配列: 管理対象リソース一覧
#        - 各リソースの "instances[].attributes": 実リソースの全属性
#        - "serial": 状態ファイルのバージョン番号（apply ごとに増加）
#        - "lineage": この状態ファイルの一意 ID（リモート状態と照合に使用）
#   7. terraform state list            — 管理リソース一覧
#   8. terraform state show <address>  — 特定リソースの詳細
#
# 追加デモ — lifecycle の動作確認:
#   9. tags に "updated_by" を追加して plan → ignore_changes で差分なし
#  10. ストレージ名を変更して plan → create_before_destroy の動作確認
#  11. prevent_destroy = true にして destroy → エラーを確認
# ===========================================
