# Day 2 — Demo 04: AVM モジュール参照 (version 固定)
# ===========================================
# Azure Verified Modules (AVM) を Terraform Registry から参照し、
# version 固定・一貫インターフェースをデモします。
#
# AVM 命名規則:
#   terraform-azurerm-avm-res-<rp>-<resource>      (Resource Module)
#   terraform-azurerm-avm-ptn-<pattern-name>        (Pattern Module)
#   terraform-azurerm-avm-utl-<utility-name>        (Utility Module)
#
# Registry: https://registry.terraform.io/namespaces/Azure
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
# リソースグループ
# -------------------------------------------------
resource "azurerm_resource_group" "demo" {
  name     = "rg-avm-demo"
  location = var.location
}

# ===========================================
# AVM Resource Module: Virtual Network
# Registry: Azure/avm-res-network-virtualnetwork/azurerm
# ===========================================
module "vnet" {
  source = "Azure/avm-res-network-virtualnetwork/azurerm"
  # ★ 重要 ★ AVM は 1.0 未満のモジュールが大半です。
  #   `~> 0.19`   は 0.19 以上 1.0 未満 = 破壊的変更を拾う（危険）
  #   `~> 0.19.0` は 0.19.0 以上 0.20 未満 = パッチのみ許容（安全）
  version = "~> 0.19.0"

  name = "vnet-avm-demo"
  # v0.8 以降 resource_group_name → parent_id（リソースグループの ID）に変更
  parent_id = azurerm_resource_group.demo.id
  location  = azurerm_resource_group.demo.location

  address_space = ["10.0.0.0/16"]

  # ── AVM 一貫インターフェース: subnets ──
  subnets = {
    web = {
      name             = "snet-web"
      address_prefixes = ["10.0.1.0/24"]
    }
    app = {
      name             = "snet-app"
      address_prefixes = ["10.0.2.0/24"]
    }
    db = {
      name             = "snet-db"
      address_prefixes = ["10.0.3.0/24"]
    }
  }

  # ── AVM 一貫インターフェース: tags ──
  tags = {
    environment = "demo"
    managed_by  = "terraform-avm"
  }
}

# ===========================================
# AVM Resource Module: Key Vault
# Registry: Azure/avm-res-keyvault-vault/azurerm
# ===========================================
data "azurerm_client_config" "current" {}

module "keyvault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "~> 0.10.0" # ← パッチのみ許容で固定

  name                = "kv-avm-demo-001"
  resource_group_name = azurerm_resource_group.demo.name
  location            = azurerm_resource_group.demo.location
  tenant_id           = data.azurerm_client_config.current.tenant_id

  # ── AVM 一貫インターフェース: role_assignments ──
  role_assignments = {
    admin = {
      role_definition_id_or_name = "Key Vault Administrator"
      principal_id               = data.azurerm_client_config.current.object_id
    }
  }

  # ── AVM 一貫インターフェース: diagnostic_settings ──
  # diagnostic_settings = {
  #   to_law = {
  #     workspace_resource_id = azurerm_log_analytics_workspace.demo.id
  #   }
  # }

  tags = {
    environment = "demo"
    managed_by  = "terraform-avm"
  }
}

# -------------------------------------------------
# 出力
# -------------------------------------------------
output "vnet_id" {
  value = module.vnet.resource_id
}

output "vnet_subnets" {
  value = { for k, v in module.vnet.subnets : k => v.resource_id }
}

output "keyvault_uri" {
  value = module.keyvault.uri
}

# ===========================================
# デモポイント:
#   1. AVM モジュールの命名規則 (avm-res-<rp>-<resource>)
#   2. version 固定: 1.0 未満のモジュールは `~> 0.19.0` （パッチのみ）で固定
#      → `~> 0.19` だと 0.99 まで上がり、破壊的変更で plan が壊れます
#   3. 一貫したインターフェース (tags, role_assignments, diagnostic_settings, lock など)
#   4. WAF セキュア既定値 (パブリックアクセス無効、RBAC 既定 etc.)
#   5. Terraform Registry で使い方・入出力を確認
# ===========================================
