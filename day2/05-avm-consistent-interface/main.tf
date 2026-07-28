# Day 2 — Demo 05: AVM 一貫インターフェース実演
# ===========================================
# すべての AVM モジュールが共通して持つインターフェースを
# 複数リソースで横断的にデモします。
#
# 一貫インターフェース一覧:
#   - tags                : すべてのリソースに共通タグ
#   - lock                : リソースロック (CanNotDelete / ReadOnly)
#   - role_assignments    : RBAC ロール割り当て
#   - diagnostic_settings : 診断設定 (Log Analytics / Event Hub / Storage)
#   - managed_identities  : マネージド ID (SystemAssigned / UserAssigned)
#   - private_endpoints   : プライベートエンドポイント
#   - customer_managed_key: CMK 暗号化
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
# 共通リソース
# -------------------------------------------------
resource "azurerm_resource_group" "demo" {
  name     = "rg-avm-interface-demo"
  location = var.location
}

data "azurerm_client_config" "current" {}

resource "azurerm_log_analytics_workspace" "demo" {
  name                = "law-avm-interface-demo"
  resource_group_name = azurerm_resource_group.demo.name
  location            = azurerm_resource_group.demo.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# ===========================================
# AVM: Key Vault — 全一貫インターフェース適用
# ===========================================
module "keyvault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "~> 0.10.0" # 1.0 未満のモジュールはパッチのみ許容で固定

  name                = "kv-avmintf-demo-001"
  resource_group_name = azurerm_resource_group.demo.name
  location            = azurerm_resource_group.demo.location
  tenant_id           = data.azurerm_client_config.current.tenant_id

  # ── 1. tags ──
  tags = {
    environment = "demo"
    managed_by  = "terraform-avm"
    interface   = "consistent"
  }

  # ── 2. lock ──
  lock = {
    kind = "CanNotDelete"
    name = "lock-keyvault-demo"
  }

  # ── 3. role_assignments ──
  role_assignments = {
    admin = {
      role_definition_id_or_name = "Key Vault Administrator"
      principal_id               = data.azurerm_client_config.current.object_id
    }
  }

  # ── 4. diagnostic_settings ──
  diagnostic_settings = {
    to_law = {
      name                  = "diag-keyvault-to-law"
      workspace_resource_id = azurerm_log_analytics_workspace.demo.id
    }
  }

  # ── 5. enable_telemetry ──
  # AVM は展開統計を Microsoft に送信します（リソース内容・顧客データは含みません）。
  # 厳格なセキュリティポリシーのエンドユーザー向けには false で一括無効化できます。
  # これも全 AVM モジュール共通のインターフェースです。
  enable_telemetry = true
}

# ===========================================
# AVM: Virtual Network — 同じインターフェースパターン
# ===========================================
module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.19.0" # 1.0 未満のモジュールはパッチのみ許容で固定

  name          = "vnet-avmintf-demo"
  parent_id     = azurerm_resource_group.demo.id # v0.8 以降 resource_group_name → parent_id
  location      = azurerm_resource_group.demo.location
  address_space = ["10.0.0.0/16"]

  subnets = {
    default = {
      name             = "snet-default"
      address_prefixes = ["10.0.0.0/24"]
    }
  }

  # ── 同じ tags インターフェース ──
  tags = {
    environment = "demo"
    managed_by  = "terraform-avm"
    interface   = "consistent"
  }

  # ── 同じ lock インターフェース ──
  lock = {
    kind = "CanNotDelete"
    name = "lock-vnet-demo"
  }

  # ── 同じ diagnostic_settings インターフェース ──
  diagnostic_settings = {
    to_law = {
      name                  = "diag-vnet-to-law"
      workspace_resource_id = azurerm_log_analytics_workspace.demo.id
    }
  }

  # ── 同じ enable_telemetry インターフェース ──
  enable_telemetry = true
}

# ===========================================
# デモポイント:
#   1. Key Vault も VNet も同じ interface 名
#      (tags, lock, role_assignments, diagnostic_settings, enable_telemetry)
#   2. どの AVM モジュールでも学習コスト同じ → チーム生産性向上
#   3. WAF に沿ったセキュア既定値がモジュール内部で適用済み
#   4. 「モジュールを切り替えてもコードの構造は変わらない」
#   5. ただし 1.0 未満のモジュールはマイナー更新で引数名が変わることがある
#      → `~> 0.19.0` のようにパッチのみ許容で固定する
# ===========================================
