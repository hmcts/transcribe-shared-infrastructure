# DIAAT-205: the transcribe product's workbooks, alert rules and availability tests, over
# the environment's Application Insights resource (observability-*.tf). The queries and
# what each view and alert means are in observability/ (README.md, MEASURES.md, ALERTS.md).
#
# The resources sit in the root, not in a local module, so the CNP Terraform allow-list
# checks each resource type. This file is their only link to the rest of the root:
# observability/tests/run-terraform-tests.sh replaces it with a harness.
#
# Alerts stay off (observability_alerts_enabled) until PlatOps decide the route. No
# availability test is created until PlatOps confirm which URLs Azure's public test agents
# can reach.
locals {
  obs_application_insights_id = module.application_insights.id
  obs_resource_group_name     = azurerm_resource_group.shared_resource_group.name
  obs_location                = azurerm_resource_group.shared_resource_group.location

  # Cost by usage share (OBS-5): the AI accounts whose cost is allocated to features, and
  # the Speech account whose batch meters are allocated to recording hearings.
  obs_billing_resource_ids = [
    module.openai_services.cognitive_account_id,
    module.speech_services.cognitive_account_id,
  ]
  obs_speech_resource_id = module.speech_services.cognitive_account_id
}
