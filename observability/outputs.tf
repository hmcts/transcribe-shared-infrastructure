output "workbook_urls" {
  description = "Portal link of each workbook, by view."
  value       = local.workbook_urls
}

output "alert_rule_ids" {
  description = "Scheduled query alert rule IDs, by alert name. Empty while alerts_enabled is false."
  value       = { for key, rule in azurerm_monitor_scheduled_query_rules_alert_v2.this : key => rule.id }
}

output "availability_test_ids" {
  description = "Standard availability test IDs, by name."
  value       = { for key, test in azurerm_application_insights_standard_web_test.this : key => test.id }
}
