# Azure OpenAI for transcribe-api's GPT-4o fallback (Gemini is primary). Same
# constraints as Speech in ai-services.tf: private, Entra-only, reached through
# a private endpoint in the AKS subscription, with its A record and VNet link in
# hmcts/azure-private-dns.
module "openai_services" {
  source = "git@github.com:hmcts/terraform-module-ai-services?ref=main"

  providers = {
    azurerm.private_dns = azurerm
  }

  env         = var.env
  product     = var.product
  project     = "cft"
  component   = "openai"
  common_tags = local.tags

  existing_resource_group_name    = azurerm_resource_group.shared_resource_group.name
  existing_cognitive_account_name = "${var.product}-openai-${var.env}"
  location                        = var.location

  create_ai_foundry        = false
  create_storage_account   = false
  create_cognitive_account = true
  enable_managed_network   = false

  cognitive_account_kind = "AIServices"
  cognitive_account_sku  = "S0"

  cognitive_account_local_auth_enabled                 = false
  public_network_access_cognitive                      = false
  cognitive_account_network_acls_default_action        = "Deny"
  cognitive_account_outbound_network_access_restricted = true

  # The deployment name is what the API calls (azure/gpt-4o). Regional
  # "Standard" keeps processing in UK South; 2024-11-20 is the gpt-4o version
  # offered on Standard there.
  cognitive_deployments = {
    "gpt-4o" = {
      model_name    = "gpt-4o"
      model_version = "2024-11-20"
      sku_name      = "Standard"
      sku_capacity  = var.openai_gpt4o_capacity
    }
  }
}

resource "azurerm_private_endpoint" "openai" {
  provider            = azurerm.aks
  name                = "${var.product}-openai-${var.env}-pe"
  resource_group_name = local.cft_aks_network_rg_name
  location            = var.location
  subnet_id           = data.azurerm_subnet.cft_private_endpoints.id
  tags                = local.tags

  private_service_connection {
    name                           = "${var.product}-openai-${var.env}-psc"
    is_manual_connection           = false
    private_connection_resource_id = module.openai_services.cognitive_account_id
    subresource_names              = ["account"]
  }
}

resource "azurerm_role_assignment" "openai_user" {
  scope                = module.openai_services.cognitive_account_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = one(module.vault.managed_identity_objectid)
}

resource "azurerm_key_vault_secret" "openai_endpoint" {
  name         = "azure-openai-endpoint"
  value        = one(module.openai_services.cognitive_account_endpoint)
  key_vault_id = module.vault.key_vault_id
  depends_on   = [module.vault]
}

# As speechPrivateEndpointDns in ai-services.tf. The A record uses the
# cognitiveservices.azure.com entry only.
output "openaiPrivateEndpointDns" {
  value = azurerm_private_endpoint.openai.custom_dns_configs
}
