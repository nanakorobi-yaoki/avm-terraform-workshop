# =============================================================================
# TFLint 設定
# =============================================================================
# 実行:
#   tflint --init          # プラグインの取得（初回のみ）
#   tflint --recursive     # モジュールを含めて検査
# =============================================================================

config {
  # 呼び出し元モジュールも検査対象にする
  call_module_type = "local"
  force            = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# -----------------------------------------------------------------------------
# Azure 固有ルール（存在しない VM サイズ、無効な SKU 等を検出）
# -----------------------------------------------------------------------------
plugin "azurerm" {
  enabled = true
  version = "0.27.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# -----------------------------------------------------------------------------
# 命名規則の強制
# -----------------------------------------------------------------------------
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

# 変数に description を必須化（納品ドキュメント自動生成の前提）
rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

# 変数に type を必須化
rule "terraform_typed_variables" {
  enabled = true
}

# -----------------------------------------------------------------------------
# バージョン固定の強制（AVM 利用時に特に重要）
# -----------------------------------------------------------------------------
rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

# module に version 指定が無い場合に警告
rule "terraform_module_pinned_source" {
  enabled = true
  style   = "flexible"
}

# -----------------------------------------------------------------------------
# 未使用の宣言を検出
# -----------------------------------------------------------------------------
rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_deprecated_interpolation" {
  enabled = true
}
