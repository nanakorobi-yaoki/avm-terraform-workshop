# ===========================================
# terraform.tfvars — 変数に値を代入
# ===========================================
# このファイルは自動的に読み込まれます。
# 他のファイル名 (例: prod.tfvars) を使う場合は
#   terraform plan -var-file="prod.tfvars"
# と指定します。
#
# ⚠ 実行前にご自身のサブスクリプション ID に置き換えてください。
#   az account show --query id -o tsv
# 現場のプロジェクトでは、実値を含む tfvars はコミットせず、
# 環境変数 TF_VAR_subscription_id または CI の Secret で渡すことを推奨します。

subscription_id = "00000000-0000-0000-0000-000000000000"

project_name = "tfworkshop"
environment  = "dev"
location     = "japaneast"

extra_tags = {
  owner = "your-name"
}
