# Day 1 — Demo 03: 式と組み込み関数 / Terraform Console / Dynamic Blocks
# ===========================================
# Terraform の式・関数・条件式・for 式をデモします。
# terraform console で対話的に試すことも可能です。
#
# 深掘りトピック:
#   - dynamic ブロック（繰り返し構造の動的生成）
#   - for 式のフィルタリング（if 付き）
#   - try() / can() によるエラーハンドリング
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

variable "environments" {
  description = "作成する環境のリスト"
  type        = list(string)
  default     = ["dev", "stg", "prod"]
}

variable "enable_premium_storage" {
  description = "Premium ストレージを有効にするか"
  type        = bool
  default     = false
}

variable "subnet_cidrs" {
  description = "サブネット CIDR のマップ"
  type        = map(string)
  default = {
    web = "10.0.1.0/24"
    app = "10.0.2.0/24"
    db  = "10.0.3.0/24"
  }
}

# -------------------------------------------------
# dynamic ブロック用の変数
# -------------------------------------------------
variable "nsg_rules" {
  description = "NSG ルールのリスト（dynamic ブロックで展開）"
  type = list(object({
    name                       = string
    priority                   = number
    direction                  = string
    access                     = string
    protocol                   = string
    source_port_range          = string
    destination_port_range     = string
    source_address_prefix      = string
    destination_address_prefix = string
  }))
  default = [
    {
      name                       = "allow-https"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    },
    {
      name                       = "allow-http"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    },
    {
      name                       = "deny-all-inbound"
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    },
  ]
}

# -------------------------------------------------
# ローカル値：式と関数を活用
# -------------------------------------------------
locals {
  # 文字列関数: upper, lower, title, format, join
  upper_location = upper(var.location)
  formatted_name = format("rg-demo-%s-%s", "workshop", var.location)
  joined_envs    = join(", ", var.environments)

  # コレクション関数: length, keys, values, lookup, contains
  env_count    = length(var.environments)
  subnet_names = keys(var.subnet_cidrs)
  has_prod     = contains(var.environments, "prod")

  # 条件式 (三項演算子)
  storage_tier = var.enable_premium_storage ? "Premium" : "Standard"
  storage_kind = var.enable_premium_storage ? "BlockBlobStorage" : "StorageV2"

  # for 式：リストの変換
  upper_environments = [for env in var.environments : upper(env)]

  # for 式：マップの変換
  subnet_info = {
    for name, cidr in var.subnet_cidrs :
    name => {
      cidr   = cidr
      prefix = tonumber(split("/", cidr)[1])
    }
  }

  # 数値関数: min, max, ceil, floor
  min_prefix = min([for _, info in local.subnet_info : info.prefix]...)
  max_prefix = max([for _, info in local.subnet_info : info.prefix]...)

  # 日付/時刻
  current_timestamp = timestamp()

  # テンプレート（heredoc）
  description = <<-EOT
    ワークショップデモ環境
    作成日: ${local.current_timestamp}
    環境数: ${local.env_count}
  EOT

  # ===========================================
  # for 式 + if フィルタ — 条件に合う要素だけ抽出
  # ===========================================
  non_prod_envs = [for env in var.environments : env if env != "prod"]
  # → ["dev", "stg"]

  # for + if でマップをフィルタ（/24 より狭いサブネットだけ抽出）
  small_subnets = {
    for name, cidr in var.subnet_cidrs :
    name => cidr
    if tonumber(split("/", cidr)[1]) >= 24
  }

  # ===========================================
  # try() / can() — エラーハンドリング
  # ===========================================
  # try(expr1, expr2, ..., fallback) → 最初に成功した式の値を返す
  # can(expr) → 式が成功すれば true、エラーなら false

  # 安全なマップ参照（キーが無くてもエラーにならない）
  web_cidr = try(var.subnet_cidrs["web"], "10.0.0.0/24")
  dmz_cidr = try(var.subnet_cidrs["dmz"], "not-defined")

  # can() で入力検証ロジック
  is_valid_cidr = can(cidrhost(var.subnet_cidrs["web"], 0))
}

# -------------------------------------------------
# 条件付きリソース: count を使ったパターン
# -------------------------------------------------
resource "azurerm_resource_group" "demo" {
  name     = local.formatted_name
  location = var.location
}

# for_each でサブネット用のリソースグループを環境ごとに作成
resource "azurerm_resource_group" "per_env" {
  for_each = toset(var.environments)

  name     = "rg-demo-${each.value}"
  location = var.location

  tags = {
    environment = each.value
    is_prod     = each.value == "prod" ? "true" : "false"
  }
}

# ===========================================
# Dynamic ブロック — 繰り返し構造の動的生成
# ===========================================
# NSG の security_rule は複数定義できるが、数が変数に依存する場合
# dynamic ブロックで変数リストから自動展開する。
#
# dynamic "BLOCK_NAME" {
#   for_each = COLLECTION
#   content { ... BLOCK_NAME.value.xxx ... }
# }

resource "azurerm_network_security_group" "demo" {
  name                = "nsg-dynamic-demo"
  resource_group_name = azurerm_resource_group.demo.name
  location            = var.location

  # ── dynamic で security_rule を変数から展開 ──
  dynamic "security_rule" {
    for_each = var.nsg_rules
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      source_port_range          = security_rule.value.source_port_range
      destination_port_range     = security_rule.value.destination_port_range
      source_address_prefix      = security_rule.value.source_address_prefix
      destination_address_prefix = security_rule.value.destination_address_prefix
    }
  }

  tags = {
    note = "dynamic ブロックデモ — ${length(var.nsg_rules)} ルール展開"
  }
}

# -------------------------------------------------
# 出力: 関数の結果を確認
# -------------------------------------------------
output "demo_expressions" {
  value = {
    upper_location     = local.upper_location
    formatted_name     = local.formatted_name
    joined_envs        = local.joined_envs
    env_count          = local.env_count
    subnet_names       = local.subnet_names
    has_prod           = local.has_prod
    storage_tier       = local.storage_tier
    upper_environments = local.upper_environments
    subnet_info        = local.subnet_info
    cidr_prefix_range  = "${local.min_prefix}-${local.max_prefix}"
  }
}

output "demo_advanced_expressions" {
  value = {
    non_prod_envs  = local.non_prod_envs
    small_subnets  = local.small_subnets
    web_cidr       = local.web_cidr
    dmz_cidr       = local.dmz_cidr
    is_valid_cidr  = local.is_valid_cidr
    nsg_rule_count = length(var.nsg_rules)
  }
}

# ===========================================
# terraform console デモ手順:
#   $ terraform console
#   > upper("hello")
#   > format("rg-%s-%s", "demo", "japaneast")
#   > length(["a","b","c"])
#   > contains(["dev","stg","prod"], "prod")
#   > cidrsubnet("10.0.0.0/16", 8, 1)
#   > [for s in ["dev","stg","prod"] : upper(s)]
#   > {for k, v in {a=1, b=2} : upper(k) => v * 10}
#
# 追加デモ — for + if / try / can:
#   > [for s in ["dev","stg","prod"] : s if s != "prod"]
#   > try({"a"="1"}["b"], "default")
#   > can(cidrhost("10.0.0.0/24", 0))
#   > can(cidrhost("not-a-cidr", 0))
# ===========================================
#   > var.enable_premium_storage ? "Premium" : "Standard"
#   > exit
# ===========================================
