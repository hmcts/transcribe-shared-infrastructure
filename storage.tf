# Audio uploads and staged transcription output. Shared by both components:
# the API writes and reads, and preview environments use the same account with
# per-environment containers.
module "storage_account" {
  source = "git@github.com:hmcts/cnp-module-storage-account?ref=master"

  env                       = var.env
  storage_account_name      = "${replace(var.product, "-", "")}${var.env}"
  resource_group_name       = azurerm_resource_group.shared_resource_group.name
  location                  = var.location
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  enable_https_traffic_only = true

  common_tags = local.tags

  containers = [
    {
      name        = "audio"
      access_type = "private"
    },
    {
      name        = "transcriptions"
      access_type = "private"
    },
  ]
}

resource "azurerm_key_vault_secret" "storage_account_name" {
  name         = "azure-storage-account-name"
  value        = module.storage_account.storageaccount_name
  key_vault_id = module.vault.key_vault_id
}
