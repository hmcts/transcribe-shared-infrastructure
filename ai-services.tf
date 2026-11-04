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

  # Mandated by Azure Policy, not a preference. hmcts/azure-policy's
  # allowed_ai_resources policy requires every Cognitive Services account to have
  # public network access disabled, network ACLs denying by default, outbound
  # access restricted, local auth disabled and a UK South location. Build #6 was
  # refused with RequestDisallowedByPolicy while this was public.
  #
  # Consequence: the account is reachable only through the private endpoint
  # below, and only once that endpoint has DNS (see there and the README).
  public_network_access_cognitive                      = false
  cognitive_account_network_acls_default_action        = "Deny"
  cognitive_account_outbound_network_access_restricted = true

  # With outbound restricted, Speech can reach only the hosts listed here.
  # Batch transcription fetches the audio in contentUrls itself, from this
  # product's storage account, so its blob host must be allowed. An empty list
  # gets "No permission to access this outbound connection" (403) on submit.
  # Speech reads the blob as its own identity; see storage.tf.
  cognitive_account_fqdns = ["${module.storage_account.storageaccount_name}.blob.core.windows.net"]
}

# The account is private (see above), so this endpoint is the only way to reach
# it. It is created here rather than through the module's own
# enable_managed_network option because the module puts the endpoint in the
# account's resource group, in the CNP infra subscription, while the subnet is
# in the AKS subscription — and a private endpoint must be in the same
# subscription as its virtual network. Same pattern as em-icp-api.
#
# No private_dns_zone_group: like em-icp-api, DNS is not managed here. The A
# record in the central privatelink.cognitiveservices.azure.com zone
# (core-infra-intsvc-rg) and the zone's link to cft-<env>-vnet come from
# hmcts/azure-private-dns (environments/privatelink/cognitive-services-private-
# link.yml) and are added by PR there, e.g. hmcts/azure-private-dns#1105 for
# aat. Without them the account's name resolves to its public IP and Speech
# returns 403.
resource "azurerm_private_endpoint" "speech" {
  provider            = azurerm.aks
  name                = "${var.product}-speech-${var.env}-pe"
  resource_group_name = local.cft_aks_network_rg_name
  location            = var.location
  subnet_id           = data.azurerm_subnet.cft_private_endpoints.id
  tags                = local.tags

  private_service_connection {
    name                           = "${var.product}-speech-${var.env}-psc"
    is_manual_connection           = false
    private_connection_resource_id = module.speech_services.cognitive_account_id
    subresource_names              = ["account"]
  }
}

module "log_analytics_workspace" {
  source      = "git@github.com:hmcts/terraform-module-log-analytics-workspace-id?ref=master"
  environment = var.env
}

# Speech's metrics carry no HTTP status codes; its RequestResponse logs do.
resource "azurerm_monitor_diagnostic_setting" "speech" {
  name                       = "${var.product}-speech-${var.env}"
  target_resource_id         = module.speech_services.cognitive_account_id
  log_analytics_workspace_id = module.log_analytics_workspace.workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# Data-plane access for the product's managed identity — the identity the AKS
# workload runs as. Control-plane roles do not cover token issuance, so without
# this the pod authenticates and is then refused by Speech itself.
#
# "Cognitive Services User", not the narrower "Cognitive Services Speech User":
# Jenkins' role-assignment permission (Role Based Access Control Administrator
# on the subscription) carries an ABAC condition allowing only listed roles
# (see the README). Speech User was not on it when build #2 was refused with
# "ABAC condition that is not fulfilled ... roleAssignments/write"; it has been
# added since. Cognitive Services User is on the list. It is broader (all data
# actions on the account), but it is scoped to this one Speech-only account,
# which the product owns outright.
resource "azurerm_role_assignment" "speech_user" {
  scope                = module.speech_services.cognitive_account_id
  role_definition_name = "Cognitive Services User"
  # one(): the module creates its managed identity with count, so the output is
  # a one-element tuple rather than a string.
  principal_id = one(module.vault.managed_identity_objectid)
}

resource "azurerm_key_vault_secret" "speech_endpoint" {
  name         = "azure-speech-endpoint"
  value        = one(module.speech_services.cognitive_account_endpoint)
  key_vault_id = module.vault.key_vault_id

  # Wait for the whole vault module, not just the vault. Jenkins' permission
  # to write secrets is granted by a separate resource inside the module (an
  # access policy). A secret only references key_vault_id, which Terraform
  # knows as soon as the vault exists, so without this it writes the secret in
  # parallel with that grant and is refused.
  depends_on = [module.vault]
}

resource "azurerm_key_vault_secret" "speech_resource_id" {
  name         = "azure-speech-resource-id"
  value        = module.speech_services.cognitive_account_id
  key_vault_id = module.vault.key_vault_id

  # Wait for the whole vault module, not just the vault. Jenkins' permission
  # to write secrets is granted by a separate resource inside the module (an
  # access policy). A secret only references key_vault_id, which Terraform
  # knows as soon as the vault exists, so without this it writes the secret in
  # parallel with that grant and is refused.
  depends_on = [module.vault]
}

output "speechAccountId" {
  value = module.speech_services.cognitive_account_id
}

output "speechEndpoint" {
  value = one(module.speech_services.cognitive_account_endpoint)
}

# For the A record in hmcts/azure-private-dns. The endpoint is in the AKS
# subscription, which the team can't read, so the apply log is the only source.
output "speechPrivateEndpointDns" {
  value = azurerm_private_endpoint.speech.custom_dns_configs
}
