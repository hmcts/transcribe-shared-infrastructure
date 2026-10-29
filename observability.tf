# DIAAT-205: the transcribe product's workbooks, alert rules and availability tests, over
# the environment's Application Insights resource. The queries and what each view and
# alert means are in observability/ (README.md, MEASURES.md, ALERTS.md).
#
# Alerts stay off (observability_alerts_enabled) until PlatOps decide the route and allow
# the resource types. No availability test is created until PlatOps confirm which URLs
# Azure's public test agents can reach.
module "observability" {
  source = "./observability"

  application_insights_id = module.application_insights.id
  resource_group_name     = azurerm_resource_group.shared_resource_group.name
  location                = azurerm_resource_group.shared_resource_group.location
  product                 = var.product
  env                     = var.env
  tags                    = local.tags

  workbooks_enabled      = var.observability_workbooks_enabled
  availability_test_urls = var.observability_availability_test_urls

  # Webhook receivers wait for the route decision: their URLs carry a token, so they will
  # come from Key Vault, never from tfvars (this repository is public).
  alerts_enabled            = var.observability_alerts_enabled
  service_alert_emails      = var.observability_service_alert_emails
  security_alert_emails     = var.observability_security_alert_emails
  alert_thresholds          = var.observability_alert_thresholds
  alert_threshold_overrides = var.observability_alert_threshold_overrides

  # Cost by usage share (OBS-5) is shown once the billing export exists; until then the
  # cost panels are a note.
  billing_export_configured   = var.observability_billing_export_configured
  azure_billing_export_source = var.observability_azure_billing_export_source
  gcp_billing_export_source   = var.observability_gcp_billing_export_source
  billing_resource_ids = [
    module.openai_services.cognitive_account_id,
    module.speech_services.cognitive_account_id,
  ]
  speech_resource_id = module.speech_services.cognitive_account_id
}
