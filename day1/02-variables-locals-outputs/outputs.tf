# ===========================================
# 出力 (outputs.tf)
# apply 後に表示される値、他のモジュールから参照可能
# ===========================================

output "resource_group_name" {
  description = "作成されたリソースグループ名"
  value       = azurerm_resource_group.demo.name
}

output "resource_group_id" {
  description = "リソースグループの Azure Resource ID"
  value       = azurerm_resource_group.demo.id
}

output "storage_account_name" {
  description = "ストレージアカウント名"
  value       = azurerm_storage_account.demo.name
}

output "storage_account_primary_endpoint" {
  description = "ストレージアカウントのプライマリ Blob エンドポイント"
  value       = azurerm_storage_account.demo.primary_blob_endpoint
}

# ===========================================
# sensitive output — sensitive 変数を出力する場合
# ===========================================
output "db_password_demo" {
  description = "sensitive な出力の例（plan/apply でマスクされる）"
  value       = var.db_admin_password
  sensitive   = true
  # sensitive = true を付けないと、sensitive 変数を参照した時点でエラーになる。
  # 確認方法: terraform output db_password_demo → マスク表示
  #           terraform output -raw db_password_demo → 平文表示（要注意）
}

# ===========================================
# 複合型の出力 — object / tuple の中身確認
# ===========================================
output "network_config_summary" {
  description = "object 型変数の値を確認"
  value = {
    vnet_cidr   = var.network_config.vnet_address_space
    subnet      = var.network_config.subnet_name
    nsg_enabled = var.network_config.enable_nsg
    dns_servers = var.network_config.dns_servers
  }
}

output "deployment_info_summary" {
  description = "tuple 型変数の値を確認"
  value = {
    app_name = var.deployment_info[0]
    version  = var.deployment_info[1]
    enabled  = var.deployment_info[2]
  }
}
