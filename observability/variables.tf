variable "application_insights_id" {
  description = "Resource ID of the environment's Application Insights resource. The workbooks, alert rules and availability tests read it."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the workbooks, alert rules, action groups and availability tests. Who can open a workbook is decided by RBAC on this group (MEASURES.md, \"Access\")."
  type        = string
}

variable "location" {
  description = "Azure region of the Application Insights resource."
  type        = string
}

variable "product" {
  description = "Product name, used in resource names and titles."
  type        = string
}

variable "env" {
  description = "Environment name (aat, perftest, ithc, demo, prod), shown in titles and used in resource names."
  type        = string
}

variable "tags" {
  description = "Tags for the created resources."
  type        = map(string)
  default     = {}
}

variable "workbooks_enabled" {
  description = "Create the workbooks (workbooks.tf). Off only where the workbook resource type is not allowed."
  type        = bool
  default     = true
}

# --- Availability tests (DIAAT-277, availability-tests.tf) --------------------------------

variable "availability_test_urls" {
  description = "Standard availability tests to create: name => URL answering 200 without sign-in. Only URLs that Azure's public test agents can reach (a PlatOps question on CNP). Empty: none."
  type        = map(string)
  default     = {}
}

variable "availability_test_locations" {
  description = "Availability test agent locations (Azure geo location IDs). Default: UK South, UK West, North Europe, West Europe, France Central."
  type        = list(string)
  default     = ["emea-ru-msa-edge", "emea-se-sto-edge", "emea-gb-db3-azr", "emea-nl-ams-azr", "emea-fr-pra-edge"]
}

variable "availability_test_frequency" {
  description = "Seconds between availability test runs from each location (300, 600 or 900)."
  type        = number
  default     = 300

  validation {
    condition     = contains([300, 600, 900], var.availability_test_frequency)
    error_message = "availability_test_frequency must be 300, 600 or 900."
  }
}

# --- Alerts (DIAAT-285, alerts.tf, ALERTS.md) ----------------------------------------------

variable "alerts_enabled" {
  description = "Create the alert rules and action groups (DIAAT-285). Off until PlatOps decide the route and allow the resource types (ALERTS.md). While false, no alert rule or action group is created."
  type        = bool
  default     = false
}

variable "service_owner_team" {
  description = "Team that receives and owns the service alerts, named in each rule. Placeholder until PlatOps confirm it."
  type        = string
  default     = "Service team (to be confirmed by PlatOps)"
}

variable "security_owner_team" {
  description = "Team that receives and owns the security alerts. Placeholder until PlatOps confirm it."
  type        = string
  default     = "Security (to be confirmed by PlatOps)"
}

variable "service_alert_emails" {
  description = "Email receivers of the service action group: team mailboxes, not individuals. This or a webhook is required when alerts_enabled."
  type        = list(string)
  default     = []
}

variable "security_alert_emails" {
  description = "Email receivers of the Security action group: team mailboxes, not individuals. This or a webhook is required when alerts_enabled."
  type        = list(string)
  default     = []
}

variable "service_alert_webhook_url" {
  description = "Optional webhook receiver of the service action group (for example Dynatrace or the incident tool), common alert schema. Empty: none."
  type        = string
  default     = ""
  sensitive   = true
}

variable "security_alert_webhook_url" {
  description = "Optional webhook receiver of the Security action group, common alert schema. Empty: none."
  type        = string
  default     = ""
  sensitive   = true
}

variable "alert_runbook_url" {
  description = "Where the response instructions live; each alert links to <url>#<alert name>."
  type        = string
  default     = "https://github.com/hmcts/transcribe-shared-infrastructure/blob/master/observability/ALERTS.md"
}

variable "alert_thresholds" {
  description = "Alert thresholds. PROVISIONAL: set in technical refinement, before baseline data. Where the heritage areas differed, the default is the dictation value; ALERTS.md lists both, to be agreed."
  type = object({
    availability_test_failed_locations = optional(number, 2)      # of 5 test locations, over 5 min
    endpoint_availability_pct          = optional(number, 90)     # below this, over 15 min (recording had 95)
    endpoint_min_requests              = optional(number, 20)     # requests in the window before the availability and 5xx alerts count (recording had 10)
    server_error_pct                   = optional(number, 2)      # 5xx share, over 30 min (recording had 5 over 1 h)
    dependency_down_minutes            = optional(number, 10)     # every health check failed for this long
    ownership_violations               = optional(number, 0)      # more than this, over 10 min
    ai_usage_spike_ratio               = optional(number, 3)      # last 24 h over the 24 h before, audio hours or tokens
    ai_usage_min_baseline_hours        = optional(number, 2)      # floor of the audio-hours baseline (recording had 1)
    ai_usage_min_baseline_tokens       = optional(number, 200000) # floor of the token baseline
    ui_errors                          = optional(number, 20)     # client-side errors of one type and source, over 1 h (new: provisional)
    dictation_session_failures         = optional(number, 5)      # sessions ended in error, over 30 min
    speech_failures                    = optional(number, 3)      # live dictation Speech failures per error code, over 30 min
    speech_unhealthy                   = optional(number, 3)      # sessions whose Speech connection went unhealthy, over 30 min
    no_speech                          = optional(number, 5)      # sessions that captured no speech, over 30 min
    autosave_stalled_pct               = optional(number, 10)     # share of active sessions, over 30 min
    autosave_min_sessions              = optional(number, 5)      # active sessions before the autosave alert counts
    submission_failures                = optional(number, 2)      # server-side failed submissions, over 30 min
    document_failures                  = optional(number, 2)      # failed document generation runs, over 30 min
    upload_job_failures                = optional(number, 3)      # dictation uploaded-audio jobs ended in error, over 1 h
    upload_job_stuck_minutes           = optional(number, 120)    # oldest unfinished dictation uploaded-audio job
    upload_transfer_failures           = optional(number, 3)      # dictation files the browser could not send to storage, over 1 h (new: provisional)
    poller_stalled_seconds             = optional(number, 600)    # since the recording poller's last successful poll
    stuck_jobs                         = optional(number, 0)      # more than this many recording jobs stuck
    oldest_waiting_minutes             = optional(number, 20)     # oldest recording job not yet started by Speech
    failed_jobs_pct                    = optional(number, 10)     # share of finished recording jobs failed from one source, over 1 h
    failed_jobs_min                    = optional(number, 5)      # finished jobs before the failed-jobs rate counts
    speech_timeouts_throttling         = optional(number, 5)      # recording Speech calls timed out or throttled, over 30 min
    speech_connection_failures         = optional(number, 5)      # recording Speech calls failed to connect, over 30 min
    storage_failures                   = optional(number, 0)      # more than this many recording writes failed, over 15 min
    upload_failures                    = optional(number, 10)     # recording uploads failed with one outcome and code, over 1 h
  })
  default = {}

  # The window is PT<n>M, evaluated every 5 minutes: an allowed log alert window of 5 minutes or more.
  validation {
    condition     = contains([5, 10, 15, 30, 45], var.alert_thresholds.dependency_down_minutes)
    error_message = "alert_thresholds.dependency_down_minutes must be 5, 10, 15, 30 or 45."
  }

  validation {
    condition     = var.alert_thresholds.availability_test_failed_locations >= 1 && var.alert_thresholds.availability_test_failed_locations <= length(var.availability_test_locations)
    error_message = "alert_thresholds.availability_test_failed_locations must be between 1 and the number of availability_test_locations."
  }
}

variable "alert_threshold_overrides" {
  description = "Temporary per-alert thresholds for the controlled tests (ALERTS.md, \"Controlled tests\"): alert name => threshold. Remove each one after its test."
  type        = map(number)
  default     = {}

  # An override for an alert that does not exist would silently do nothing.
  validation {
    condition     = alltrue([for key in keys(var.alert_threshold_overrides) : contains(local.alert_names, key)])
    error_message = "alert_threshold_overrides: every key must be an alert name in alerts.tf (or availability-test)."
  }
}

# --- Cost allocation (OBS-5, workbooks.tf "ai-usage", MEASURES.md) -------------------------

variable "billing_export_configured" {
  description = "The billing exports the AI usage workbook allocates cost from exist (PlatOps). While false, the cost panels say \"requires the billing export\" and no billing table is queried. When true, set azure_billing_export_source, billing_resource_ids and speech_resource_id."
  type        = bool
  default     = false
}

variable "azure_billing_export_source" {
  description = "KQL table expression holding the Azure Cost Management export (actual cost, daily), as queried from Application Insights, for example workspace(\"<workspace resource ID>\").AzureCostExport_CL. Expected columns: cost_allocation.kql."
  type        = string
  default     = ""
}

variable "gcp_billing_export_source" {
  description = "Optional KQL table expression holding the GCP billing export (Vertex AI cost), copied into Log Analytics. Empty: GCP cost is not allocated. Expected columns: cost_allocation.kql."
  type        = string
  default     = ""
}

variable "billing_resource_ids" {
  description = "Azure resource IDs whose cost is allocated to features: this environment's Azure OpenAI and Speech accounts."
  type        = list(string)
  default     = []
}

variable "speech_resource_id" {
  description = "Resource ID of this environment's Azure Speech account: its batch meters are allocated to recording hearings (recording_cost_by_hearing.kql)."
  type        = string
  default     = ""

  validation {
    condition     = !var.billing_export_configured || (trimspace(var.azure_billing_export_source) != "" && length(var.billing_resource_ids) > 0 && trimspace(var.speech_resource_id) != "")
    error_message = "billing_export_configured: set azure_billing_export_source, billing_resource_ids and speech_resource_id (see cost_allocation.kql)."
  }
}
