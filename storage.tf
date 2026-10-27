# Audio uploads and staged transcription output. Shared by both components:
# the API writes and reads, and preview environments use the same account with
# per-environment containers.
module "storage_account" {
  source = "git@github.com:hmcts/cnp-module-storage-account?ref=master"

  env                       = var.env
  storage_account_name      = "${replace(var.product, "-", "")}${var.env}"
  resource_group_name       = azurerm_resource_group.shared_resource_group.name
  location                  = var.location
  account_kind              = "StorageV2"
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  enable_https_traffic_only = true

  common_tags = local.tags

  # See network.tf for why.
  sa_subnets = local.all_valid_subnets

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

  # Wait for the whole vault module, not just the vault. Jenkins' permission
  # to write secrets is granted by a separate resource inside the module (an
  # access policy). A secret only references key_vault_id, which Terraform
  # knows as soon as the vault exists, so without this it writes the secret in
  # parallel with that grant and is refused.
  depends_on = [module.vault]
}

# The API reads and writes audio with DefaultAzureCredential — the product's
# managed identity — and mints user-delegation SAS URLs for the browser's
# dictation uploads and downloads, which also needs a blob data role. Nothing
# granted one, so every upload and read would have failed at runtime with 403.
# Speech batch transcription does not use a SAS: the API passes Speech a plain
# blob URL, and Speech reads it as its own identity (see below).
resource "azurerm_role_assignment" "app_blob_contributor" {
  scope                = module.storage_account.storageaccount_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = one(module.vault.managed_identity_objectid)
}

# Speech batch transcription reads the audio blob in contentUrls as its own
# system-assigned identity: the API sends a plain URL, with no SAS. This is
# Azure's "trusted Azure services" route. The module's firewall already has
# bypass = AzureServices, which lets Speech through when its identity holds a
# data role, and the blob host is in Speech's outbound allowlist
# (ai-services.tf). Without this grant, storage refuses Speech. Read-only:
# Speech never writes here.
resource "azurerm_role_assignment" "speech_blob_reader" {
  scope                = module.storage_account.storageaccount_id
  role_definition_name = "Storage Blob Data Reader"
  # one(): the module returns the identity as a one-element list.
  principal_id = one(module.speech_services.cognitive_account_identity)
}
