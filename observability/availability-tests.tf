# Synthetic availability (DIAAT-277): App Insights standard availability tests.
#
# Only for URLs that Azure's public test agents can reach and that answer 200 without
# sign-in: whether any CNP URL qualifies is a PlatOps question, so the root passes none
# yet. Results go to availabilityResults (kql/service_availability_synthetic.kql); the
# alert is in alerts.tf.

resource "azurerm_application_insights_standard_web_test" "this" {
  for_each = var.availability_test_urls

  name                    = "${var.product}-${each.key}-${var.env}"
  description             = "GET ${each.key} health, expects 200 (DIAAT-277)."
  resource_group_name     = var.resource_group_name
  location                = var.location
  application_insights_id = var.application_insights_id
  geo_locations           = var.availability_test_locations
  frequency               = var.availability_test_frequency
  timeout                 = 30
  enabled                 = true
  retry_enabled           = true

  request {
    url                              = each.value
    http_verb                        = "GET"
    follow_redirects_enabled         = false # a redirect to sign-in is a failure, not a pass
    parse_dependent_requests_enabled = false
  }

  validation_rules {
    expected_status_code        = 200
    ssl_check_enabled           = true
    ssl_cert_remaining_lifetime = 7
  }

  # No hidden-link tag here: azurerm 4.x adds it on create and update and removes it from
  # state on read, so declaring it would show a diff on every plan.
  tags = var.tags
}
