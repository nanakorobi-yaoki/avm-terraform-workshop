# =============================================================================
# Day 2 — Demo 07: パラメータ受け渡しの再設計（Excel パラメータシートの代替）
# =============================================================================
# Session 1 でいただいたご質問への回答デモ。
#
# ポイント:
#   - パラメータは YAML に外出し（コードとパラメータの分離 = Excel と同じ利点）
#   - Git で差分が見える / PR でレビューできる（Excel にはできない）
#   - JSON Schema で検証（Excel の入力規則に相当）
#   - 納品用 Excel は tools/gen_param_sheet.py で自動生成
#
# 実行:
#   terraform init
#   terraform plan -var="customer=contoso" -var="env=prod"
# =============================================================================

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
  description = "Azure サブスクリプション ID"
  type        = string
}

variable "customer" {
  description = "顧客識別子（params/<customer>-<env>.yaml を読み込む）"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.customer))
    error_message = "customer は英小文字・数字・ハイフンのみ、2〜20 文字で指定してください。"
  }
}

variable "env" {
  description = "環境識別子"
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prod"], var.env)
    error_message = "env は dev / stg / prod のいずれかを指定してください。"
  }
}

# =============================================================================
# ★ ここが肝: YAML を読み込んでパラメータとして使う
#    エンドユーザー様が編集するのは params/*.yaml だけ
# =============================================================================
locals {
  param_file = "${path.module}/params/${var.customer}-${var.env}.yaml"
  p          = yamldecode(file(local.param_file))

  # 全リソース共通のタグ（Policy as Code の必須タグを満たす）
  common_tags = merge(
    {
      environment = var.env
      customer    = var.customer
      costCenter  = local.p.costCenter
      owner       = local.p.owner
      managed_by  = "terraform"
    },
    try(local.p.additionalTags, {})
  )
}

# -----------------------------------------------------------------------------
# パラメータの整合性チェック（Excel には無い安全網）
#
# ★ check と precondition の使い分け ★
#   check        … 失敗しても「警告」止まり。plan / apply は成功する（終了コード 0）。
#                  「気づけるとよい」助言レベルの検証に使う。
#   precondition … 失敗すると plan がその場でエラー終了する。
#                  「絶対に通してはいけない」業務ルールはこちらで守る。
# -----------------------------------------------------------------------------
check "parameter_advisory" {
  assert {
    condition     = length(local.p.network.subnets) > 0
    error_message = "network.subnets が空です。最低 1 つのサブネットを定義することを推奨します。"
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.customer}-${var.env}"
  location = local.p.location
  tags     = local.common_tags

  # ★ ここは警告ではなく plan を「停止」させる ★
  lifecycle {
    precondition {
      condition     = can(cidrhost(local.p.network.addressSpace[0], 0))
      error_message = "network.addressSpace[0] が有効な CIDR ではありません: ${local.p.network.addressSpace[0]}"
    }

    precondition {
      condition     = var.env != "prod" || local.p.enablePrivateEndpoint
      error_message = "本番環境では enablePrivateEndpoint を true にしてください。"
    }
  }
}

# =============================================================================
# AVM モジュールに YAML の値を渡す
# =============================================================================
module "vnet" {
  source = "Azure/avm-res-network-virtualnetwork/azurerm"
  # 注意: AVM は 1.0 未満のモジュールが多く、`~> 0.19` と書くと 0.99 まで許容され
  #       破壊的変更を拾ってしまいます。パッチのみ許容する `~> 0.19.0` で固定します。
  version = "~> 0.19.0"

  name = "vnet-${var.customer}-${var.env}"
  # v0.8 以降、resource_group_name ではなく親リソースの ID を渡します
  parent_id = azurerm_resource_group.this.id
  location  = azurerm_resource_group.this.location

  address_space = local.p.network.addressSpace

  # YAML の subnets 定義をそのまま渡す
  subnets = {
    for k, v in local.p.network.subnets : k => {
      name             = v.name
      address_prefixes = v.addressPrefixes
    }
  }

  tags = local.common_tags
}

# =============================================================================
# 出力 — 納品パラメータシート生成の入力にもなる
# =============================================================================
output "parameter_summary" {
  description = "適用されたパラメータのサマリ（納品書類の自動生成に使用）"
  value = {
    customer       = var.customer
    environment    = var.env
    location       = local.p.location
    parameter_file = local.param_file
    resource_group = azurerm_resource_group.this.name
    vnet_name      = module.vnet.name
    address_space  = local.p.network.addressSpace
    subnet_count   = length(local.p.network.subnets)
    tags           = local.common_tags
  }
}
