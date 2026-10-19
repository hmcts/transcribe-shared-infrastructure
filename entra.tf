# Copies the BenchNotes app registration's client secret into this vault as
# entra-client-secret. The registration is created by hmcts/central-app-registration,
# which keeps the secret in central-app-reg-kv and lets this pipeline's Jenkins
# identity read it (kv_reader_service_principals).
provider "azurerm" {
  features {}
  alias                           = "entra_secret_source"
  subscription_id                 = coalesce(try(var.entra_client_secret_source.subscription_id, null), var.aks_subscription_id)
  resource_provider_registrations = "none"
}

data "azurerm_key_vault" "entra_secret_source" {
  count               = var.entra_client_secret_source == null ? 0 : 1
  provider            = azurerm.entra_secret_source
  name                = var.entra_client_secret_source.key_vault_name
  resource_group_name = var.entra_client_secret_source.resource_group_name
}

data "azurerm_key_vault_secret" "entra_client_secret" {
  count        = var.entra_client_secret_source == null ? 0 : 1
  provider     = azurerm.entra_secret_source
  name         = var.entra_client_secret_source.secret_name
  key_vault_id = data.azurerm_key_vault.entra_secret_source[0].id
}

resource "azurerm_key_vault_secret" "entra_client_secret" {
  count        = var.entra_client_secret_source == null ? 0 : 1
  name         = "entra-client-secret"
  value        = data.azurerm_key_vault_secret.entra_client_secret[0].value
  content_type = "text/plain"
  key_vault_id = module.vault.key_vault_id
  depends_on   = [module.vault]
}
