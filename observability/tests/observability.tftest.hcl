# The observability module: workbooks always, alerts off by default, complete when on, and
# refusing to be created without a receiver. Runs offline with a mocked provider:
#   cd observability && terraform init -backend=false && terraform test

mock_provider "azurerm" {}

variables {
  application_insights_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Insights/components/ai"
  resource_group_name     = "rg"
  location                = "uksouth"
  product                 = "transcribe"
  env                     = "aat"
  availability_test_urls  = { web = "https://example.invalid/health" }
}

run "workbooks_and_tests_without_alerts" {
  command = plan

  assert {
    condition     = toset(keys(azurerm_application_insights_workbook.this)) == toset(["service-health", "dictation", "recording", "workload", "ai-usage"])
    error_message = "One workbook per view."
  }

  assert {
    condition     = length(azurerm_application_insights_standard_web_test.this) == 1
    error_message = "One availability test per URL."
  }

  assert {
    condition     = length(azurerm_monitor_scheduled_query_rules_alert_v2.this) == 0 && length(azurerm_monitor_metric_alert.availability_test) == 0 && length(azurerm_monitor_action_group.this) == 0
    error_message = "No alert rule or action group while alerts_enabled is false."
  }
}

# Every alert query file has a rule, and every rule a query file and a runbook section.
run "every_alert_query_has_a_rule" {
  command = plan

  assert {
    condition     = toset([for alert in local.alerts : "${alert.query}.kql"]) == fileset("${path.module}/kql", "alert_*.kql")
    error_message = "Each kql/alert_*.kql file is used by exactly the rules in local.alerts, and no rule names a missing file."
  }

  assert {
    condition     = alltrue([for key in keys(local.alerts) : strcontains(file("${path.module}/ALERTS.md"), "### ${key}\n")])
    error_message = "Every alert has its response section in ALERTS.md."
  }
}

run "on_with_receivers" {
  command = plan

  variables {
    alerts_enabled        = true
    service_alert_emails  = ["service-team@example.invalid"]
    security_alert_emails = ["security-team@example.invalid"]
  }

  assert {
    condition     = length(azurerm_monitor_scheduled_query_rules_alert_v2.this) == length(local.alerts) && length(azurerm_monitor_metric_alert.availability_test) == 1
    error_message = "Every alert in local.alerts, and one per availability test."
  }

  assert {
    condition     = toset(keys(azurerm_monitor_action_group.this)) == toset(["service", "security"])
    error_message = "One action group per receiving team."
  }

  assert {
    condition     = alltrue([for key in ["service-unavailable", "dependency-down", "ownership-violation", "poller-stalled"] : azurerm_monitor_scheduled_query_rules_alert_v2.this[key].severity == 1])
    error_message = "The critical alerts are severity 1."
  }

  assert {
    condition     = alltrue([for key, rule in azurerm_monitor_scheduled_query_rules_alert_v2.this : strcontains(rule.description, "ALERTS.md#${key}") && strcontains(rule.description, "Owner: ")])
    error_message = "Every alert names its owner and links to its response section."
  }

  assert {
    condition     = startswith(azurerm_monitor_scheduled_query_rules_alert_v2.this["service-unavailable"].criteria[0].query, "let min_requests = 20;\n// ALERT")
    error_message = "Parameters are prepended as let statements."
  }

  assert {
    condition     = endswith(azurerm_monitor_scheduled_query_rules_alert_v2.this["autosave-stalled"].criteria[0].query, "| project failed_pct, failures, sessions\n| where sessions >= 5")
    error_message = "The autosave alert counts only with enough active sessions."
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this["ai-usage-spike"].window_duration == "P2D" && azurerm_monitor_scheduled_query_rules_alert_v2.this["ai-token-spike"].window_duration == "P2D"
    error_message = "A log alert reads at most 2 days: the spike baseline is the day before."
  }

  assert {
    condition     = alltrue([for key, alert in local.alerts : alert.owner == (startswith(key, "ownership-violation") ? "security" : "service")])
    error_message = "The ownership-violation alerts go to Security, every other alert to the service team."
  }
}

run "controlled_test_override" {
  command = plan

  variables {
    alerts_enabled            = true
    service_alert_emails      = ["service-team@example.invalid"]
    security_alert_emails     = ["security-team@example.invalid"]
    alert_threshold_overrides = { "dependency-down" = 2, "availability-test" = 1 }
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this["dependency-down"].criteria[0].threshold == 2 && azurerm_monitor_scheduled_query_rules_alert_v2.this["service-unavailable"].criteria[0].threshold == 90
    error_message = "An override changes only its own rule."
  }

  assert {
    condition     = azurerm_monitor_metric_alert.availability_test["web"].application_insights_web_test_location_availability_criteria[0].failed_location_count == 1
    error_message = "The availability-test alert can be overridden too."
  }
}

run "override_of_an_unknown_alert_fails" {
  command = plan

  variables {
    alert_threshold_overrides = { "no-such-alert" = 1 }
  }

  expect_failures = [var.alert_threshold_overrides]
}

run "on_without_receivers_fails" {
  command = plan

  variables {
    alerts_enabled = true
  }

  expect_failures = [azurerm_monitor_action_group.this]
}

run "availability_test_has_no_hidden_link_tag" {
  command = plan

  variables {
    tags = { environment = "aat" }
  }

  # azurerm 4.x adds the hidden-link tag itself and removes it from state on read:
  # declaring it would show a diff on every plan.
  assert {
    condition     = alltrue([for test in azurerm_application_insights_standard_web_test.this : test.tags["environment"] == "aat" && !anytrue([for key in keys(test.tags) : startswith(key, "hidden-link")])])
    error_message = "Availability tests carry var.tags only, with no hidden-link tag."
  }
}

# OBS-5: no billing table is queried until the export exists.
run "cost_panels_need_the_billing_export" {
  command = plan

  assert {
    condition = alltrue([
      length(split("requires the billing export", azurerm_application_insights_workbook.this["ai-usage"].data_json)) == 3,
      !strcontains(azurerm_application_insights_workbook.this["ai-usage"].data_json, "AZURE_BILLING_EXPORT"),
      !strcontains(azurerm_application_insights_workbook.this["ai-usage"].data_json, "BILLING_EXPORT_TABLE"),
    ])
    error_message = "While billing_export_configured is false, both cost panels are a note and no billing table is queried."
  }
}

run "cost_panels_with_the_billing_export" {
  command = plan

  variables {
    billing_export_configured   = true
    azure_billing_export_source = "workspace(\"/subscriptions/0/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/ws\").AzureCostExport_CL"
    billing_resource_ids        = ["/subscriptions/0/resourceGroups/rg/providers/Microsoft.CognitiveServices/accounts/Speech"]
    speech_resource_id          = "/subscriptions/0/resourceGroups/rg/providers/Microsoft.CognitiveServices/accounts/Speech"
  }

  assert {
    condition = alltrue([
      strcontains(azurerm_application_insights_workbook.this["ai-usage"].data_json, "let azure_billing = workspace("),
      strcontains(azurerm_application_insights_workbook.this["ai-usage"].data_json, "let cost_export = workspace("),
      strcontains(azurerm_application_insights_workbook.this["ai-usage"].data_json, "microsoft.cognitiveservices/accounts/speech"),
      strcontains(azurerm_application_insights_workbook.this["ai-usage"].data_json, "let usage_share = () {\\n"),
      !strcontains(azurerm_application_insights_workbook.this["ai-usage"].data_json, "requires the billing export"),
      !strcontains(azurerm_application_insights_workbook.this["ai-usage"].data_json, "dynamic(BILLING_RESOURCE_IDS)"),
      !strcontains(azurerm_application_insights_workbook.this["ai-usage"].data_json, "let cost_export = BILLING_EXPORT_TABLE"),
      !strcontains(azurerm_application_insights_workbook.this["ai-usage"].data_json, "SPEECH_RESOURCE_ID\\\""),
    ])
    error_message = "With the export configured, both cost panels query it, for the listed resources only."
  }
}

run "billing_export_needs_its_source" {
  command = plan

  variables {
    billing_export_configured = true
  }

  expect_failures = [var.speech_resource_id]
}

run "workbooks_can_be_switched_off" {
  command = plan

  variables {
    workbooks_enabled = false
  }

  assert {
    condition     = length(azurerm_application_insights_workbook.this) == 0
    error_message = "No workbook where the resource type is not allowed."
  }
}

run "dependency_down_window_must_be_allowed" {
  command = plan

  variables {
    alert_thresholds = { dependency_down_minutes = 20 }
  }

  expect_failures = [var.alert_thresholds]
}

run "availability_alert_window_follows_the_test_frequency" {
  command = plan

  variables {
    alerts_enabled              = true
    service_alert_emails        = ["service-team@example.invalid"]
    security_alert_emails       = ["security-team@example.invalid"]
    availability_test_frequency = 900
  }

  assert {
    condition     = azurerm_monitor_metric_alert.availability_test["web"].window_size == "PT15M"
    error_message = "The window holds a run from every location."
  }
}

run "availability_override_above_the_locations_fails" {
  command = plan

  variables {
    alerts_enabled            = true
    service_alert_emails      = ["service-team@example.invalid"]
    security_alert_emails     = ["security-team@example.invalid"]
    alert_threshold_overrides = { "availability-test" = 6 }
  }

  expect_failures = [azurerm_monitor_metric_alert.availability_test]
}
