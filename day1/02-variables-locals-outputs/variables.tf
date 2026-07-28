# ===========================================
# 変数定義 (variables.tf)
# ===========================================
# 深掘りトピック:
#   - 変数の優先順位（precedence）
#   - sensitive 変数
#   - 複合型 (object / tuple / optional)
#   - 複数 validation ブロック
#
# ── 変数の優先順位（高 → 低）──
#   1. -var / -var-file コマンドライン引数
#   2. *.auto.tfvars / *.auto.tfvars.json（アルファベット順）
#   3. terraform.tfvars / terraform.tfvars.json
#   4. 環境変数 TF_VAR_<name>
#   5. variable ブロックの default 値
#   6. 対話入力プロンプト（default 未設定時）
# ===========================================

variable "subscription_id" {
  description = "Azure サブスクリプション ID"
  type        = string
}

variable "project_name" {
  description = "プロジェクト名（リソース命名に使用）"
  type        = string
  default     = "tfworkshop"

  validation {
    condition     = length(var.project_name) >= 3 && length(var.project_name) <= 20
    error_message = "プロジェクト名は 3～20 文字で指定してください。"
  }
}

variable "environment" {
  description = "環境名 (dev / stg / prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stg", "prod"], var.environment)
    error_message = "environment は dev, stg, prod のいずれかを指定してください。"
  }
}

variable "location" {
  description = "Azure リージョン"
  type        = string
  default     = "japaneast"
}

variable "storage_account_tier" {
  description = "ストレージアカウントの SKU ティア"
  type        = string
  default     = "Standard"
}

variable "storage_replication_type" {
  description = "レプリケーション種別"
  type        = string
  default     = "LRS"
}

variable "extra_tags" {
  description = "追加タグ（任意）"
  type        = map(string)
  default     = {}
}

# ===========================================
# sensitive 変数 — plan / apply 出力でマスクされる
# ===========================================
variable "db_admin_password" {
  description = "データベース管理者パスワード（デモ用）"
  type        = string
  default     = "P@ssw0rd-Demo-Only!"
  sensitive   = true
  # sensitive = true の効果:
  #   - terraform plan/apply の出力で "(sensitive value)" と表示
  #   - terraform.tfstate には平文で保存される（要注意！）
  #   - output で参照する場合も sensitive = true が必要
}

# ===========================================
# 複合型: object — 構造化データを 1 変数で受け取る
# ===========================================
variable "network_config" {
  description = "ネットワーク設定（object 型デモ）"
  type = object({
    vnet_address_space = string
    subnet_name        = string
    subnet_prefix      = string
    enable_nsg         = bool
    dns_servers        = optional(list(string), []) # ← optional() で省略可能＋デフォルト値
  })
  default = {
    vnet_address_space = "10.0.0.0/16"
    subnet_name        = "snet-default"
    subnet_prefix      = "10.0.1.0/24"
    enable_nsg         = true
    # dns_servers は optional なので省略可能
  }

  validation {
    condition     = can(cidrhost(var.network_config.vnet_address_space, 0))
    error_message = "vnet_address_space は有効な CIDR 表記で指定してください。"
  }
}

# ===========================================
# 複合型: tuple — 固定長・異種型のリスト
# ===========================================
variable "deployment_info" {
  description = "デプロイ情報 [名前, バージョン, 有効フラグ] の tuple"
  type        = tuple([string, number, bool])
  default     = ["webapp", 3, true]
  # tuple は要素数と各型が固定:
  #   var.deployment_info[0] → "webapp"  (string)
  #   var.deployment_info[1] → 3         (number)
  #   var.deployment_info[2] → true      (bool)
}

# ===========================================
# nullable — null を許可するか（Terraform 1.1+）
# ===========================================
variable "optional_description" {
  description = "リソースの説明文（null 許可）"
  type        = string
  default     = null
  nullable    = true
  # nullable = true (デフォルト) → null を代入可能
  # nullable = false → null 代入で validation エラー
}
