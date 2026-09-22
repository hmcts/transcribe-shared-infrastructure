# Azure Speech, provisioned through the platform's approved AI services module
# (terraform-module-ai-services is on the global Terraform whitelist; a bare
# azurerm_cognitive_account is not).
#
# Authentication is Entra-only: local_auth_enabled = false means the account
# issues no API keys at all, so there is no AZURE_SPEECH_KEY to leak or rotate.
# The API already supports this path — routes_dictation.py mints an
# "aad#<resourceId>#<token>" token from DefaultAzureCredential when
# AZURE_SPEECH_RESOURCE_ID is set, which is what the Speech SDK expects.
module "speech_services" {
  source = "git@github.com:hmcts/terraform-module-ai-services?ref=main"

  providers = {
    # Required alias. Unused here because enable_managed_network = false skips
    # every private-endpoint and DNS lookup.
    azurerm.private_dns = azurerm
  }

  env         = var.env
  product     = var.product
  project     = "cft"
  component   = "speech"
  common_tags = local.tags

  existing_resource_group_name    = azurerm_resource_group.shared_resource_group.name
  existing_cognitive_account_name = "${var.product}-speech-${var.env}"
  location                        = var.location

  create_ai_foundry        = false
  create_storage_account   = false
  create_cognitive_account = true
  enable_managed_network   = false

  cognitive_account_kind = "SpeechServices"
  cognitive_account_sku  = var.speech_account_sku

  # No API keys, ever.
  cognitive_account_local_auth_enabled = false

  # Reachability is a per-environment decision, not a constant — see the
  # variable's description for why this cannot simply be locked down yet.
  public_network_access_cognitive               = var.speech_public_network_access
  cognitive_account_network_acls_default_action = var.speech_public_network_access ? "Allow" : "Deny"
}

# Data-plane access for the product's managed identity, which is the identity
# the AKS workload runs as. Control-plane roles do not cover token issuance, so
# without this the pod authenticates and is then refused by Speech itself.
resource "azurerm_role_assignment" "speech_user" {
  scope                = module.speech_services.cognitive_account_id
  role_definition_name = "Cognitive Services Speech User"
  principal_id         = module.vault.managed_identity_objectid
}

# Consumed by the API through the chart's keyVaults block. The resource ID is
# what selects the Managed Identity path; there is deliberately no
# azure-speech-key counterpart.
resource "azurerm_key_vault_secret" "speech_endpoint" {
  name         = "azure-speech-endpoint"
  value        = one(module.speech_services.cognitive_account_endpoint)
  key_vault_id = module.vault.key_vault_id
}

resource "azurerm_key_vault_secret" "speech_resource_id" {
  name         = "azure-speech-resource-id"
  value        = module.speech_services.cognitive_account_id
  key_vault_id = module.vault.key_vault_id
}

output "speechAccountId" {
  value = module.speech_services.cognitive_account_id
}

output "speechEndpoint" {
  value = one(module.speech_services.cognitive_account_endpoint)
}
