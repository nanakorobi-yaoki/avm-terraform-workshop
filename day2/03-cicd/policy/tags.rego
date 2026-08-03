# =============================================================================
# Policy as Code — 必須タグの強制
# =============================================================================
# 実行:
#   terraform show -json tfplan > tfplan.json
#   conftest test tfplan.json --policy policy/
#
# デモの見せ場: タグを 1 つ消した PR がここで止まる
# =============================================================================
package main

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# -----------------------------------------------------------------------------
# 全リソースに必須のタグ
#   costCenter : 課金按分（案件ごとの原価管理）
#   environment: 環境識別
#   owner      : 障害時の連絡先
# -----------------------------------------------------------------------------
required_tags := {"costCenter", "environment", "owner"}

# タグをサポートしないリソースタイプは除外
tag_exempt_types := {
    "azurerm_role_assignment",
    "azurerm_management_lock",
    "azurerm_subnet",
    "azurerm_storage_container",
    "azurerm_key_vault_secret",
    "azurerm_monitor_diagnostic_setting",
    "random_string",
    "random_password",
}

# 作成・更新されるリソースのみ検査（削除は対象外）
resources_under_change contains r if {
    some r in input.resource_changes
    some action in r.change.actions
    action in {"create", "update"}
    not r.type in tag_exempt_types
    object.get(r.change.after, "tags", null) != null
}

deny contains msg if {
    some r in resources_under_change
    tags := object.get(r.change.after, "tags", {})
    missing := required_tags - {k | some k, _ in tags}
    count(missing) > 0
    msg := sprintf(
        "%s: 必須タグが不足しています %v",
        [r.address, sort(missing)],
    )
}

# -----------------------------------------------------------------------------
# environment タグの値を検証
# -----------------------------------------------------------------------------
allowed_environments := {"dev", "stg", "prod", "demo"}

deny contains msg if {
    some r in resources_under_change
    env := r.change.after.tags.environment
    not env in allowed_environments
    msg := sprintf(
        "%s: environment タグの値 '%s' は不正です。許可値: %v",
        [r.address, env, sort(allowed_environments)],
    )
}

# -----------------------------------------------------------------------------
# 警告レベル: owner タグがメールアドレス形式か
# -----------------------------------------------------------------------------
warn contains msg if {
    some r in resources_under_change
    owner := r.change.after.tags.owner
    not regex.match(`^[^@\s]+@[^@\s]+\.[^@\s]+$`, owner)
    msg := sprintf(
        "%s: owner タグ '%s' はメールアドレス形式が推奨です",
        [r.address, owner],
    )
}
