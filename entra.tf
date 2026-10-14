# Copies the shared app registration's client secret from courtstranscribe's
# vault, as batch-audio-transcription-infra does. Access is granted by
# courtstranscribe's auth_secret_readers.
provider "azurerm" {
  features {}
  alias                           = "courtstranscribe"
  subscription_id                 = coalesce(try(var.courtstranscribe_key_vault.subscription_id, null), var.aks_subscription_id)
  resource_provider_registrations = "none"
}

data "azurerm_key_vault" "courtstranscribe" {
  count               = var.courtstranscribe_key_vault == null ? 0 : 1
  provider            = azurerm.courtstranscribe
  name                = var.courtstranscribe_key_vault.name
  resource_group_name = var.courtstranscribe_key_vault.resource_group_name
}

data "azurerm_key_vault_secret" "entra_client_secret" {
  count        = var.courtstranscribe_key_vault == null ? 0 : 1
  provider     = azurerm.courtstranscribe
  name         = "microsoft-provider-authentication-secret"
  key_vault_id = data.azurerm_key_vault.courtstranscribe[0].id
}

resource "azurerm_key_vault_secret" "entra_client_secret" {
  count        = var.courtstranscribe_key_vault == null ? 0 : 1
  name         = "entra-client-secret"
  value        = data.azurerm_key_vault_secret.entra_client_secret[0].value
  content_type = "text/plain"
  key_vault_id = module.vault.key_vault_id
  depends_on   = [module.vault]
}
