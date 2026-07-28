# ===========================================
# 再利用可能モジュール: Storage Account
# ===========================================

variable "name" {
  description = "ストレージアカウント名"
  type        = string
}

variable "resource_group_name" {
  description = "リソースグループ名"
  type        = string
}

variable "location" {
  description = "Azure リージョン"
  type        = string
}

variable "account_tier" {
  description = "ストレージ SKU ティア"
  type        = string
  default     = "Standard"
}

variable "replication_type" {
  description = "レプリケーション種別"
  type        = string
  default     = "LRS"
}

variable "containers" {
  description = "作成する Blob コンテナのリスト"
  type = list(object({
    name        = string
    access_type = optional(string, "private")
  }))
  default = []
}

variable "tags" {
  description = "タグ"
  type        = map(string)
  default     = {}
}
