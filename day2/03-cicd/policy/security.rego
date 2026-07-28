# =============================================================================
# Policy as Code — セキュリティベースライン
# =============================================================================
# AVM のセキュア既定値を「使っていること」を検証するポリシー。
# AVM を使っていても、明示的に上書きして緩めることは可能なため、
# 組織として譲れない一線を conftest で守ります。
#
# 実行:
#   terraform show -json tfplan > tfplan.json
#   conftest test tfplan.json --policy policy/
# =============================================================================
package main

import future.keywords.contains
import future.keywords.if
import future.keywords.in

resources_under_change contains r if {
    some r in input.resource_changes
    some action in r.change.actions
    action in {"create", "update"}
}

# -----------------------------------------------------------------------------
# Storage Account: パブリックアクセス禁止 / HTTPS 必須 / TLS 1.2 以上
# -----------------------------------------------------------------------------
deny contains msg if {
    some r in resources_under_change
    r.type == "azurerm_storage_account"
    r.change.after.allow_nested_items_to_be_public == true
    msg := sprintf("%s: Blob のパブリックアクセスは禁止です", [r.address])
}

deny contains msg if {
    some r in resources_under_change
    r.type == "azurerm_storage_account"
    r.change.after.https_traffic_only_enabled == false
    msg := sprintf("%s: HTTPS 通信のみを有効にしてください", [r.address])
}

deny contains msg if {
    some r in resources_under_change
    r.type == "azurerm_storage_account"
    r.change.after.min_tls_version != "TLS1_2"
    msg := sprintf(
        "%s: min_tls_version は TLS1_2 にしてください (現在: %v)",
        [r.address, r.change.after.min_tls_version],
    )
}

# -----------------------------------------------------------------------------
# Key Vault: 論理削除・purge 保護
# -----------------------------------------------------------------------------
deny contains msg if {
    some r in resources_under_change
    r.type == "azurerm_key_vault"
    r.change.after.purge_protection_enabled == false
    msg := sprintf("%s: purge_protection_enabled を true にしてください", [r.address])
}

# -----------------------------------------------------------------------------
# NSG: インターネットからの管理ポート開放を禁止
# -----------------------------------------------------------------------------
management_ports := {"22", "3389"}
any_source := {"*", "0.0.0.0/0", "Internet", "any"}

deny contains msg if {
    some r in resources_under_change
    r.type == "azurerm_network_security_rule"
    r.change.after.access == "Allow"
    r.change.after.direction == "Inbound"
    r.change.after.source_address_prefix in any_source
    r.change.after.destination_port_range in management_ports
    msg := sprintf(
        "%s: インターネットから管理ポート %s への許可は禁止です。Bastion / JIT を使用してください",
        [r.address, r.change.after.destination_port_range],
    )
}

# -----------------------------------------------------------------------------
# パブリック IP の作成を原則禁止（例外はタグで明示）
# -----------------------------------------------------------------------------
deny contains msg if {
    some r in resources_under_change
    r.type == "azurerm_public_ip"
    tags := object.get(r.change.after, "tags", {})
    object.get(tags, "allowPublicIp", "false") != "true"
    msg := sprintf(
        "%s: パブリック IP の作成には tags.allowPublicIp = \"true\" による明示的な承認が必要です",
        [r.address],
    )
}

# -----------------------------------------------------------------------------
# 警告: 診断設定が 1 つも定義されていない
#   AVM の diagnostic_settings 引数の利用を促します
# -----------------------------------------------------------------------------
diagnostics_recommended := {
    "azurerm_key_vault",
    "azurerm_storage_account",
    "azurerm_network_security_group",
}

has_any_diagnostic_setting if {
    some d in input.resource_changes
    d.type == "azurerm_monitor_diagnostic_setting"
}

warn contains msg if {
    some r in resources_under_change
    r.type in diagnostics_recommended
    not has_any_diagnostic_setting
    msg := sprintf(
        "%s: 診断設定が 1 つも定義されていません。AVM の diagnostic_settings の利用を推奨します",
        [r.address],
    )
}
