# Alerts (DIAAT-285), defined as code. What each alert means, who owns it and how to
# respond: ALERTS.md, one section per alert, linked from the rule.
#
# Off by default (var.alerts_enabled = false): the route (Dynatrace, a Slack action group
# or our own action groups) and whether scheduled query rules, metric alerts and action
# groups are allowed on CNP are PlatOps questions. While off, nothing below is created.
#
# Every alert is one entry of local.alerts: a scheduled query over kql/<query>.kql, except
# the availability-test alert (a metric alert per availability test). The rule's window is
# the query's time range. params are prepended as `let <name> = <value>;`.
#
# AC3: every alert query ends with a `| project` of safe columns (tests/check_kql_names.py).
# A rule's measure and dimensions must be among them (precondition below), so nothing
# unvetted reaches a notification.
#
# Severity: 1 critical (act now), 2 warning (act within the working day), 3 informational,
# 4 test. Thresholds: var.alert_thresholds, provisional until there is baseline data.

locals {
  t = var.alert_thresholds

  # One entry per alert, keyed by its section in ALERTS.md. owner: the action group.
  alerts = {
    # --- Service, both areas -------------------------------------------------------
    "service-unavailable" = {
      query       = "alert_service_unavailable"
      params      = { min_requests = local.t.endpoint_min_requests }
      severity    = 1
      description = "Service unavailable: under ${local.t.endpoint_availability_pct}% of a service's requests in an area answered without 5xx over 15 minutes (at least ${local.t.endpoint_min_requests} requests)."
      measure     = "availability_pct"
      aggregation = "Minimum"
      operator    = "LessThan"
      threshold   = local.t.endpoint_availability_pct
      dimensions  = ["cloud_RoleName", "area"]
      window      = "PT15M"
      frequency   = "PT5M"
      owner       = "service"
    }
    "server-errors" = {
      query       = "alert_service_server_errors"
      params      = { min_requests = local.t.endpoint_min_requests }
      severity    = 2
      description = "Elevated 5xx rate: over ${local.t.server_error_pct}% of a service's requests in an area over 30 minutes (at least ${local.t.endpoint_min_requests} requests)."
      measure     = "server_error_pct"
      aggregation = "Maximum"
      operator    = "GreaterThan"
      threshold   = local.t.server_error_pct
      dimensions  = ["cloud_RoleName", "area"]
      window      = "PT30M"
      frequency   = "PT10M"
      owner       = "service"
    }
    "dependency-down" = {
      query       = "alert_service_dependency_down"
      params      = {}
      severity    = 1
      description = "Core dependency down: every health check of the database or Blob Storage failed for ${local.t.dependency_down_minutes} minutes (service.dependency.up = 0)."
      measure     = "up"
      aggregation = "Maximum"
      operator    = "LessThan"
      threshold   = 1
      dimensions  = ["dependency"]
      window      = "PT${local.t.dependency_down_minutes}M"
      frequency   = "PT5M"
      owner       = "service"
    }
    "ownership-violation" = {
      query       = "alert_service_ownership_violation"
      params      = {}
      severity    = 1
      description = "A user reached, or tried to reach, a record they do not own (security.ownership_violation, outcome blocked or detected)."
      measure     = "violations"
      aggregation = "Total"
      operator    = "GreaterThan"
      threshold   = local.t.ownership_violations
      dimensions  = ["area", "outcome", "resource_type", "action"]
      window      = "PT10M"
      frequency   = "PT5M"
      owner       = "security"
    }
    "ownership-violation-test" = {
      query       = "alert_service_ownership_violation_test"
      params      = {}
      severity    = 4
      description = "[TEST] No action needed: the controlled test of the Security route (security.outcome = test)."
      measure     = "violations"
      aggregation = "Total"
      operator    = "GreaterThan"
      threshold   = 0
      dimensions  = ["outcome"]
      window      = "PT5M"
      frequency   = "PT5M"
      owner       = "security"
    }
    # A log alert's query reads at most 2 days, so the spike baseline is the day before.
    "ai-usage-spike" = {
      query       = "alert_service_ai_usage_spike"
      params      = { min_baseline_hours = local.t.ai_usage_min_baseline_hours }
      severity    = 2
      description = "Azure Speech usage spike: a feature's audio hours in the last 24 hours over ${local.t.ai_usage_spike_ratio}x the 24 hours before (or ${local.t.ai_usage_min_baseline_hours} h, whichever is larger). Usage, not cost."
      measure     = "spike_ratio"
      aggregation = "Maximum"
      operator    = "GreaterThan"
      threshold   = local.t.ai_usage_spike_ratio
      dimensions  = ["feature"]
      window      = "P2D"
      frequency   = "PT6H"
      owner       = "service"
    }
    "ai-token-spike" = {
      query       = "alert_service_ai_token_spike"
      params      = { min_baseline_tokens = local.t.ai_usage_min_baseline_tokens }
      severity    = 2
      description = "LLM token spike: a feature's tokens in the last 24 hours over ${local.t.ai_usage_spike_ratio}x the 24 hours before (or ${local.t.ai_usage_min_baseline_tokens} tokens, whichever is larger). Usage, not cost."
      measure     = "spike_ratio"
      aggregation = "Maximum"
      operator    = "GreaterThan"
      threshold   = local.t.ai_usage_spike_ratio
      dimensions  = ["feature"]
      window      = "P2D"
      frequency   = "PT6H"
      owner       = "service"
    }

    # --- Dictation -----------------------------------------------------------------
    "dictation-session-failures" = {
      query       = "alert_dictation_session_failures"
      params      = {}
      severity    = 2
      description = "Repeated dictation session failures: ${local.t.dictation_session_failures} or more sessions ended in error over 30 minutes."
      measure     = "failures"
      aggregation = "Total"
      operator    = "GreaterThanOrEqual"
      threshold   = local.t.dictation_session_failures
      dimensions  = []
      window      = "PT30M"
      frequency   = "PT10M"
      owner       = "service"
    }
    "speech-failures" = {
      query       = "alert_dictation_speech_failures"
      params      = {}
      severity    = 2
      description = "Azure Speech failures in live dictation (connection, throttling, timeout): ${local.t.speech_failures} or more with one error code over 30 minutes."
      measure     = "failures"
      aggregation = "Total"
      operator    = "GreaterThanOrEqual"
      threshold   = local.t.speech_failures
      dimensions  = ["error_code"]
      window      = "PT30M"
      frequency   = "PT10M"
      owner       = "service"
    }
    "speech-unhealthy" = {
      query       = "alert_dictation_speech_unhealthy"
      params      = {}
      severity    = 2
      description = "Live dictation Speech connections unhealthy: ${local.t.speech_unhealthy} or more sessions over 30 minutes."
      measure     = "failures"
      aggregation = "Total"
      operator    = "GreaterThanOrEqual"
      threshold   = local.t.speech_unhealthy
      dimensions  = []
      window      = "PT30M"
      frequency   = "PT10M"
      owner       = "service"
    }
    "no-speech" = {
      query       = "alert_dictation_no_speech"
      params      = {}
      severity    = 2
      description = "Dictation sessions capturing no speech: ${local.t.no_speech} or more over 30 minutes."
      measure     = "failures"
      aggregation = "Total"
      operator    = "GreaterThanOrEqual"
      threshold   = local.t.no_speech
      dimensions  = []
      window      = "PT30M"
      frequency   = "PT10M"
      owner       = "service"
    }
    "autosave-stalled" = {
      query       = "alert_dictation_autosave_stalled"
      params      = {}
      append      = "| where sessions >= ${local.t.autosave_min_sessions}"
      severity    = 2
      description = "Autosave failing: autosave stalled in over ${local.t.autosave_stalled_pct}% of active dictation sessions over 30 minutes (at least ${local.t.autosave_min_sessions} sessions)."
      measure     = "failed_pct"
      aggregation = "Maximum"
      operator    = "GreaterThan"
      threshold   = local.t.autosave_stalled_pct
      dimensions  = []
      window      = "PT30M"
      frequency   = "PT10M"
      owner       = "service"
    }
    "submission-failures" = {
      query       = "alert_dictation_submission_failures"
      params      = {}
      severity    = 2
      description = "Dictation submissions failing on the server (storage, database, document): ${local.t.submission_failures} or more over 30 minutes."
      measure     = "failures"
      aggregation = "Total"
      operator    = "GreaterThanOrEqual"
      threshold   = local.t.submission_failures
      dimensions  = []
      window      = "PT30M"
      frequency   = "PT10M"
      owner       = "service"
    }
    "document-generation-failures" = {
      query       = "alert_dictation_document_generation_failures"
      params      = {}
      severity    = 2
      description = "Document generation failing: ${local.t.document_failures} or more failed runs over 30 minutes."
      measure     = "failures"
      aggregation = "Total"
      operator    = "GreaterThanOrEqual"
      threshold   = local.t.document_failures
      dimensions  = []
      window      = "PT30M"
      frequency   = "PT10M"
      owner       = "service"
    }
    "upload-job-failures" = {
      query       = "alert_dictation_upload_job_failures"
      params      = {}
      severity    = 2
      description = "Dictation uploaded-audio jobs failing (transcription, minutes, document, email): ${local.t.upload_job_failures} or more jobs ended in error over 1 hour."
      measure     = "failures"
      aggregation = "Total"
      operator    = "GreaterThanOrEqual"
      threshold   = local.t.upload_job_failures
      dimensions  = []
      window      = "PT1H"
      frequency   = "PT15M"
      owner       = "service"
    }
    "upload-jobs-stuck" = {
      query       = "alert_dictation_upload_jobs_stuck"
      params      = {}
      severity    = 2
      description = "Dictation uploaded-audio job stuck: a job started in the last 6 hours has not finished after ${local.t.upload_job_stuck_minutes} minutes."
      measure     = "oldest_waiting_min"
      aggregation = "Maximum"
      operator    = "GreaterThan"
      threshold   = local.t.upload_job_stuck_minutes
      dimensions  = []
      window      = "PT6H"
      frequency   = "PT30M"
      owner       = "service"
    }

    # --- Recording -----------------------------------------------------------------
    "poller-stalled" = {
      query       = "alert_recording_poller_stalled"
      params      = {}
      severity    = 1
      description = "Recording job polling stopped: no worker has completed a poll for ${local.t.poller_stalled_seconds} seconds (transcription.poller.last_success_age)."
      measure     = "last_success_age_s"
      aggregation = "Minimum"
      operator    = "GreaterThan"
      threshold   = local.t.poller_stalled_seconds
      dimensions  = []
      window      = "PT10M"
      frequency   = "PT5M"
      owner       = "service"
    }
    "stuck-jobs" = {
      query       = "alert_recording_stuck_jobs"
      params      = {}
      severity    = 2
      description = "More than ${local.t.stuck_jobs} recording job(s) waited or ran longer than their stuck threshold (transcription.jobs.stuck)."
      measure     = "stuck"
      aggregation = "Maximum"
      operator    = "GreaterThan"
      threshold   = local.t.stuck_jobs
      dimensions  = ["state"]
      window      = "PT15M"
      frequency   = "PT5M"
      owner       = "service"
    }
    "oldest-waiting" = {
      query       = "alert_recording_oldest_waiting"
      params      = {}
      severity    = 2
      description = "The oldest recording job not yet started by Azure Speech has waited more than ${local.t.oldest_waiting_minutes} minutes."
      measure     = "oldest_waiting_min"
      aggregation = "Maximum"
      operator    = "GreaterThan"
      threshold   = local.t.oldest_waiting_minutes
      dimensions  = []
      window      = "PT15M"
      frequency   = "PT5M"
      owner       = "service"
    }
    "failed-jobs" = {
      query       = "alert_recording_failed_jobs"
      params      = { min_jobs = local.t.failed_jobs_min }
      severity    = 2
      description = "More than ${local.t.failed_jobs_pct}% of the recording jobs finished in the last hour ended in error from one source (application, dependency or queue), with at least ${local.t.failed_jobs_min} jobs finished."
      measure     = "failed_pct"
      aggregation = "Maximum"
      operator    = "GreaterThan"
      threshold   = local.t.failed_jobs_pct
      dimensions  = ["source"]
      window      = "PT1H"
      frequency   = "PT15M"
      owner       = "service"
    }
    "speech-timeouts-throttling" = {
      query       = "alert_recording_speech_timeouts_throttling"
      params      = {}
      severity    = 2
      description = "More than ${local.t.speech_timeouts_throttling} recording Azure Speech calls timed out or were throttled (HTTP 429) in 30 minutes."
      measure     = "failures"
      aggregation = "Total"
      operator    = "GreaterThan"
      threshold   = local.t.speech_timeouts_throttling
      dimensions  = ["error_code"]
      window      = "PT30M"
      frequency   = "PT10M"
      owner       = "service"
    }
    "speech-connection-failures" = {
      query       = "alert_recording_speech_connection_failures"
      params      = {}
      severity    = 2
      description = "More than ${local.t.speech_connection_failures} recording Azure Speech calls failed to connect, broke off or got a 5xx in 30 minutes."
      measure     = "failures"
      aggregation = "Total"
      operator    = "GreaterThan"
      threshold   = local.t.speech_connection_failures
      dimensions  = ["error_code"]
      window      = "PT30M"
      frequency   = "PT10M"
      owner       = "service"
    }
    "storage-failed" = {
      query       = "alert_recording_storage_failed"
      params      = {}
      severity    = 2
      description = "More than ${local.t.storage_failures} database or blob write(s) failed in the recording pipeline in 15 minutes (job.storage_failed, upload blob writes)."
      measure     = "failures"
      aggregation = "Total"
      operator    = "GreaterThan"
      threshold   = local.t.storage_failures
      dimensions  = ["operation", "error_code"]
      window      = "PT15M"
      frequency   = "PT5M"
      owner       = "service"
    }
    "upload-failures" = {
      query       = "alert_recording_upload_failures"
      params      = {}
      severity    = 3
      description = "More than ${local.t.upload_failures} recording uploads failed with the same outcome and code in the last hour."
      measure     = "failures"
      aggregation = "Total"
      operator    = "GreaterThan"
      threshold   = local.t.upload_failures
      dimensions  = ["outcome", "error_code"]
      window      = "PT1H"
      frequency   = "PT15M"
      owner       = "service"
    }
  }

  # The rule's threshold: its own, or a temporary controlled-test override.
  alert_threshold = {
    for key, alert in local.alerts : key => lookup(var.alert_threshold_overrides, key, alert.threshold)
  }

  # The columns each alert query returns: its final `| project`, the single line
  # tests/check_kql_names.py vets for AC3 (the last line starting with it).
  alert_columns = {
    for key, alert in local.alerts : key => [
      for column in split(",", reverse(regexall("(?m)^\\|\\s*project\\s+(.+)$", local.kql[alert.query]))[0][0]) : trimspace(column)
    ]
  }

  alert_query = {
    for key, alert in local.alerts : key => join("\n", concat(
      [for name, value in alert.params : "let ${name} = ${value};"],
      [trimspace(local.kql[alert.query])],
      compact([try(alert.append, "")]),
    ))
  }

  # Action groups, one per receiving team. The webhook URLs are sensitive, so they are
  # kept out of the for_each map.
  action_groups = {
    service  = { short_name = "trsvc-${var.env}", team = var.service_owner_team, emails = var.service_alert_emails }
    security = { short_name = "trsec-${var.env}", team = var.security_owner_team, emails = var.security_alert_emails }
  }
  alert_webhooks = {
    service  = var.service_alert_webhook_url
    security = var.security_alert_webhook_url
  }

  alert_properties = {
    for key, alert in local.alerts : key => {
      owner   = local.action_groups[alert.owner].team
      runbook = "${var.alert_runbook_url}#${key}"
    }
  }
}

resource "azurerm_monitor_action_group" "this" {
  for_each = { for key, group in local.action_groups : key => group if var.alerts_enabled }

  name                = "${var.product}-${each.key}-alerts-${var.env}"
  resource_group_name = var.resource_group_name
  short_name          = substr(each.value.short_name, 0, 12)
  location            = "global"

  dynamic "email_receiver" {
    for_each = each.value.emails
    content {
      name                    = "email-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  # Whether a webhook is set is not secret; its URL is (it usually carries a token).
  dynamic "webhook_receiver" {
    for_each = nonsensitive(local.alert_webhooks[each.key] != "") ? ["webhook"] : []
    content {
      name                    = "webhook"
      service_uri             = local.alert_webhooks[each.key]
      use_common_alert_schema = true
    }
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = length(each.value.emails) > 0 || nonsensitive(local.alert_webhooks[each.key] != "")
      error_message = "alerts_enabled: the ${each.key} action group needs at least one receiver (email or webhook). See ALERTS.md."
    }
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "this" {
  for_each = { for key, alert in local.alerts : key => alert if var.alerts_enabled }

  name                    = "${var.product}-${each.key}-${var.env}"
  display_name            = "${var.product} ${each.key} (${var.env})"
  description             = "${each.value.description} Owner: ${local.alert_properties[each.key].owner}. Response: ${local.alert_properties[each.key].runbook}"
  resource_group_name     = var.resource_group_name
  location                = var.location
  scopes                  = [var.application_insights_id]
  severity                = each.value.severity
  evaluation_frequency    = each.value.frequency
  window_duration         = each.value.window
  enabled                 = true
  auto_mitigation_enabled = true

  criteria {
    query                   = local.alert_query[each.key]
    time_aggregation_method = each.value.aggregation
    metric_measure_column   = each.value.measure
    operator                = each.value.operator
    threshold               = local.alert_threshold[each.key]

    dynamic "dimension" {
      for_each = each.value.dimensions
      content {
        name     = dimension.value
        operator = "Include"
        values   = ["*"]
      }
    }

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups     = [azurerm_monitor_action_group.this[each.value.owner].id]
    custom_properties = local.alert_properties[each.key]
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = alltrue([for column in concat(each.value.dimensions, [each.value.measure]) : contains(local.alert_columns[each.key], column)])
      error_message = "Alert ${each.key}: its measure and dimensions must be columns of the final '| project' of kql/${each.value.query}.kql (the AC3-vetted output)."
    }
  }
}

# Service unavailable from outside: an availability test failing from several locations
# at once (Microsoft's recommended availability alert), one rule per test.
resource "azurerm_monitor_metric_alert" "availability_test" {
  for_each = { for name, test in azurerm_application_insights_standard_web_test.this : name => test.id if var.alerts_enabled }

  name                = "${var.product}-${each.key}-unavailable-${var.env}"
  description         = "Service unavailable: the ${each.key} availability test failed from ${local.availability_test_threshold} or more locations within ${local.availability_alert_window}. Owner: ${var.service_owner_team}. Response: ${var.alert_runbook_url}#availability-test"
  resource_group_name = var.resource_group_name
  scopes              = [each.value, var.application_insights_id]
  severity            = 1
  frequency           = "PT1M"
  window_size         = local.availability_alert_window
  auto_mitigate       = true

  application_insights_web_test_location_availability_criteria {
    web_test_id           = each.value
    component_id          = var.application_insights_id
    failed_location_count = local.availability_test_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.this["service"].id
    webhook_properties = {
      owner   = var.service_owner_team
      runbook = "${var.alert_runbook_url}#availability-test"
    }
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = local.availability_test_threshold >= 1 && local.availability_test_threshold <= length(var.availability_test_locations)
      error_message = "The availability-test threshold (or its override) must be between 1 and the number of availability_test_locations, or the alert can never fire."
    }
  }
}

locals {
  alert_names                 = concat(keys(local.alerts), ["availability-test"])
  availability_test_threshold = lookup(var.alert_threshold_overrides, "availability-test", local.t.availability_test_failed_locations)
  # Long enough to hold a run from every location: one test frequency at least.
  availability_alert_window = { 300 = "PT5M", 600 = "PT15M", 900 = "PT15M" }[var.availability_test_frequency]
}

