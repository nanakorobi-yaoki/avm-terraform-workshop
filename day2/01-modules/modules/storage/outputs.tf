# ===========================================
# Storage Module — outputs.tf
# ===========================================

output "storage_account_id" {
  description = "ストレージアカウントの ID"
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "ストレージアカウント名"
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "プライマリ Blob エンドポイント"
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_access_key" {
  description = "プライマリアクセスキー"
  value       = azurerm_storage_account.this.primary_access_key
  sensitive   = true
}

output "container_names" {
  description = "作成されたコンテナ名のリスト"
  value       = [for c in azurerm_storage_container.this : c.name]
}
