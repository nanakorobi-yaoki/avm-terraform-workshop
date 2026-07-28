# Day 2 — Demo 06: マルチティア構成 & AVM from scratch
# ===========================================
# AVM モジュールを組み合わせて本番に近い
# マルチティアアーキテクチャを構築します。
#
# 構成: VNet → NSG → Web (App Service) → DB (SQL) → Key Vault
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
  type = string
}

variable "location" {
  type    = string
  default = "japaneast"
}

variable "project_name" {
  type    = string
  default = "multitier"
}

variable "environment" {
  type    = string
  default = "dev"
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    project      = var.project_name
    environment  = var.environment
    managed_by   = "terraform-avm"
    architecture = "multi-tier"
  }
}

data "azurerm_client_config" "current" {}

# -------------------------------------------------
# リソースグループ
# -------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}

# -------------------------------------------------
# Log Analytics (監視基盤)
# -------------------------------------------------
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

# ===========================================
# Tier 1: ネットワーク層 (AVM VNet)
# ===========================================
module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.19.0" # 1.0 未満のモジュールはパッチのみ許容で固定

  name          = "vnet-${local.name_prefix}"
  parent_id     = azurerm_resource_group.main.id # v0.8 以降 resource_group_name → parent_id
  location      = azurerm_resource_group.main.location
  address_space = ["10.0.0.0/16"]

  subnets = {
    web = {
      name             = "snet-web"
      address_prefixes = ["10.0.1.0/24"]
      delegation = [{
        name = "appservice"
        service_delegation = {
          name = "Microsoft.Web/serverFarms"
        }
      }]
    }
    app = {
      name             = "snet-app"
      address_prefixes = ["10.0.2.0/24"]
    }
    db = {
      name             = "snet-db"
      address_prefixes = ["10.0.3.0/24"]
    }
    pe = {
      name             = "snet-privateendpoints"
      address_prefixes = ["10.0.4.0/24"]
    }
  }

  diagnostic_settings = {
    to_law = {
      name                  = "diag-vnet"
      workspace_resource_id = azurerm_log_analytics_workspace.main.id
    }
  }

  tags = local.common_tags
}

# ===========================================
# Tier 2: セキュリティ層 (AVM Key Vault)
# ===========================================
module "keyvault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "~> 0.10.0" # 1.0 未満のモジュールはパッチのみ許容で固定

  name                = "kv-${local.name_prefix}-001"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tenant_id           = data.azurerm_client_config.current.tenant_id

  role_assignments = {
    admin = {
      role_definition_id_or_name = "Key Vault Administrator"
      principal_id               = data.azurerm_client_config.current.object_id
    }
  }

  diagnostic_settings = {
    to_law = {
      name                  = "diag-keyvault"
      workspace_resource_id = azurerm_log_analytics_workspace.main.id
    }
  }

  lock = {
    kind = "CanNotDelete"
    name = "lock-keyvault"
  }

  tags = local.common_tags
}

# ===========================================
# Tier 3: NSG (ネットワークセキュリティ)
# ===========================================
module "nsg_web" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "~> 0.4.0" # 1.0 未満のモジュールはパッチのみ許容で固定

  name                = "nsg-web-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  security_rules = {
    allow_https_inbound = {
      name                       = "AllowHTTPS"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "Internet"
      destination_address_prefix = "*"
    }
    deny_all_inbound = {
      name                       = "DenyAllInbound"
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }

  diagnostic_settings = {
    to_law = {
      name                  = "diag-nsg-web"
      workspace_resource_id = azurerm_log_analytics_workspace.main.id
    }
  }

  tags = local.common_tags
}

# -------------------------------------------------
# 出力
# -------------------------------------------------
output "architecture_summary" {
  value = {
    resource_group = azurerm_resource_group.main.name
    vnet_id        = module.vnet.resource_id
    keyvault_name  = module.keyvault.name
    nsg_web_id     = module.nsg_web.resource_id
    subnets        = { for k, v in module.vnet.subnets : k => v.resource_id }
    log_analytics  = azurerm_log_analytics_workspace.main.id
  }
}

# ===========================================
# デモポイント:
#   1. AVM モジュールの組み合わせでエンタープライズ構成を素早く構築
#   2. すべてのモジュールで同じ diagnostic_settings / tags / lock
#   3. WAF セキュア既定値 → NSG Deny All、Key Vault RBAC 等
#   4. version 固定でチーム全体の再現性を確保
#   5. 次のステップ: AI 支援 IaC (Copilot で Terraform を加速)
# ===========================================

# ===========================================
# 参考: よく使われる AVM モジュール一覧 (座学で紹介)
# ===========================================
# Registry: https://registry.terraform.io/namespaces/Azure
# 全モジュール索引: https://aka.ms/avm/index
#
# ── Resource Modules (avm-res-*) ──────────────────────
#
# | カテゴリ        | モジュール名                                          | 用途                           |
# |----------------|------------------------------------------------------|-------------------------------|
# | コンピュート     | avm-res-compute-virtualmachine                       | Windows / Linux VM            |
# | コンピュート     | avm-res-containerservice-managedcluster              | AKS クラスタ                   |
# | コンピュート     | avm-res-web-site                                     | App Service / Function App    |
# | ネットワーク     | avm-res-network-virtualnetwork                       | VNet + サブネット               |
# | ネットワーク     | avm-res-network-networksecuritygroup                 | NSG + ルール                   |
# | ネットワーク     | avm-res-network-publicipaddress                      | パブリック IP                   |
# | ネットワーク     | avm-res-network-privateendpoint                      | プライベートエンドポイント        |
# | ネットワーク     | avm-res-network-applicationgateway                   | Application Gateway / WAF v2  |
# | ストレージ      | avm-res-storage-storageaccount                        | Storage Account               |
# | データベース     | avm-res-sql-server                                    | Azure SQL Server + DB         |
# | データベース     | avm-res-dbforpostgresql-flexibleserver                | PostgreSQL Flexible Server    |
# | セキュリティ     | avm-res-keyvault-vault                                | Key Vault                     |
# | セキュリティ     | avm-res-managedidentity-userassignedidentity          | User Assigned Managed Identity|
# | 監視           | avm-res-operationalinsights-workspace                 | Log Analytics Workspace       |
# | ガバナンス      | avm-res-resources-resourcegroup                       | Resource Group                |
#
# ── Pattern Modules (avm-ptn-*) ──────────────────────
#
# | モジュール名                              | 用途                                      |
# |-----------------------------------------|------------------------------------------|
# | avm-ptn-virtualnetworkgateway            | VPN / ExpressRoute Gateway               |
# | avm-ptn-alz                              | Azure Landing Zone (CAF) 全体構成         |
# | avm-ptn-hubnetworking                    | Hub-Spoke ネットワークトポロジ              |
# | avm-ptn-virtualwan                       | Virtual WAN トポロジ                       |
#
# ── Utility Modules (avm-utl-*) ──────────────────────
#
# | モジュール名                              | 用途                                      |
# |-----------------------------------------|------------------------------------------|
# | avm-utl-naming                           | Azure 命名規則ヘルパー                     |
# | avm-utl-interfaces                       | 一貫インターフェース定義（内部利用）          |
#
# ── 探し方 ──
#   1. https://aka.ms/avm/index で Status = "Published" をフィルタ
#   2. Terraform Registry で "avm" を検索
#   3. GitHub: https://github.com/Azure?q=terraform-azurerm-avm
#
# ── 金子さんチームへの推奨 ──
#   - 社内標準化の第一歩: VNet + NSG + Storage + Key Vault で基盤テンプレート作成
#   - AKS 利用時: avm-res-containerservice-managedcluster を version 固定で導入
#   - Pattern Module (Hub-Spoke / ALZ) で Landing Zone を標準化
# ===========================================
