# The web app signs users in with the same MoJ-tenant (JusticeUK) app
# registration as courtstranscribe and batch-audio-transcription, so it needs
# that registration's client secret. As batch-audio-transcription-infra does
# (its data.tf / keyvault.tf), the secret is read from courtstranscribe's Key
# Vault at apply time and written into ours, rather than seeded by hand: a
# rotation in courtstranscribe reaches this app on the next apply.
#
# This needs, on the courtstranscribe side (a PlatOps / courtstranscribe-owner
# grant; nothing in this repo can give it):
#   - Reader on the vault for jenkins-<env>-mi, so the provider can resolve it;
#   - an access policy with secret Get for jenkins-<env>-mi;
#   - network access from the Jenkins agents (the vault's firewall is Deny by
#     default).
# Environments with no courtstranscribe vault configured skip the copy, and
# entra-client-secret must be seeded by hand there.
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
