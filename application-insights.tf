module "application_insights" {
  source = "git@github.com:hmcts/terraform-module-application-insights?ref=main"

  env     = var.env
  product = var.product
  name    = var.product

  resource_group_name = azurerm_resource_group.shared_resource_group.name
  common_tags         = local.tags

  daily_data_cap_in_gb = var.daily_data_cap_in_gb
}

# Both components read this at BUILD time: Jenkinsfile_CNP declares
# secret('AppInsightsConnectionString', 'APP_INSIGHTS_CONNECTION_STRING') and
# substitutes it into values.{env}.template.yaml. The name must stay exactly as
# spelled here or the pipeline fails resolving the secret.
#
# It cannot travel by the usual mounted-file route: the OpenTelemetry distro
# baked into the HMCTS base images reads the connection string from the process
# environment before any application code runs.
resource "azurerm_key_vault_secret" "app_insights_connection_string" {
  name         = "AppInsightsConnectionString"
  value        = module.application_insights.connection_string
  key_vault_id = module.vault.key_vault_id
}
