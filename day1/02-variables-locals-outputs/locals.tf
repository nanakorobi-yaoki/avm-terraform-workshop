# ===========================================
# ローカル値 (locals.tf)
# 変数を組み合わせて命名規則を統一するパターン
# ===========================================

locals {
  # 命名プレフィックス: "{project}-{env}"
  name_prefix = "${var.project_name}-${var.environment}"

  # リソース名
  resource_group_name  = "rg-${local.name_prefix}"
  storage_account_name = "st${replace(local.name_prefix, "-", "")}001"

  # 共通タグ
  common_tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      managed_by  = "terraform"
      workshop    = "avm-terraform-vbd"
    },
    var.extra_tags
  )
}
