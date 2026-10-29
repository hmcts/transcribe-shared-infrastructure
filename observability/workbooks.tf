# Views (App Insights workbooks), defined as code, over the queries in kql/:
#   service-health - both areas: availability, errors, dependencies (DIAAT-277);
#   dictation      - live dictation, submissions and documents (DIAAT-284);
#   recording      - the recording pipeline: uploads, queue, Speech, post-processing,
#                    storage (DIAAT-280 to 283);
#   workload       - volumes and capacity of both areas (DIAAT-284);
#   ai-usage       - LLM tokens and Speech audio by feature, and cost by usage share once
#                    the billing export exists (OBS-5).
# The measure behind every panel is in MEASURES.md.
#
# Access: each workbook is a resource in var.resource_group_name and reads the
# environment's Application Insights data. This module grants nothing (MEASURES.md,
# "Access").
#
# One Application Insights resource per environment and one module instance per
# environment, so the environment is which workbook you open (its name ends with it), and
# each workbook links to its siblings. The time-range parameter is the period filter;
# the queries are parameter-free.

locals {
  # Every .kql file in kql/, by file name without the extension.
  kql = { for file in fileset("${path.module}/kql", "*.kql") : trimsuffix(file, ".kql") => file("${path.module}/kql/${file}") }

  # Workbook names are GUIDs derived from the product, environment and view, so they are
  # stable and the IDs are known before the workbooks exist (for the links between them).
  # The keys are listed here, not taken from local.workbooks, which uses the links.
  workbook_keys = ["service-health", "dictation", "recording", "workload", "ai-usage"]
  workbook_names = {
    for key in local.workbook_keys :
    key => uuidv5("url", "https://hmcts.net/${var.product}/${var.env}/workbooks/${key}")
  }
  workbook_urls = {
    for key, name in local.workbook_names :
    key => "https://portal.azure.com/#resource/subscriptions/${split("/", var.application_insights_id)[2]}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Insights/workbooks/${name}/workbook"
  }
  workbook_links = join(" · ", [
    "[Service health](${local.workbook_urls["service-health"]})",
    "[Dictation](${local.workbook_urls["dictation"]})",
    "[Recording](${local.workbook_urls["recording"]})",
    "[Workload](${local.workbook_urls["workload"]})",
    "[AI usage](${local.workbook_urls["ai-usage"]})",
  ])

  # Series for a p50/p95 chart from a query with p50_ms and p95_ms columns.
  p50_p95 = "| mv-expand pct = pack_array(\"p50\", \"p95\") to typeof(string)\n| extend ms = iff(pct == \"p50\", p50_ms, p95_ms)"

  # OBS-5: cost by usage share. Usage telemetry has no prices; the cost comes from the
  # billing exports (PlatOps), which do not exist yet. Until var.billing_export_configured,
  # the cost panels are a note and no billing table is queried.
  empty_gcp_billing = "datatable(usage_start_time: datetime, service_description: string, sku_description: string, cost: real, currency: string) []"
  cost_allocation_query = join("", [
    "let usage_share = () {\n${trimspace(local.kql.ai_usage_share_daily)}\n};\n",
    replace(replace(replace(local.kql.cost_allocation,
      "AZURE_BILLING_EXPORT", var.azure_billing_export_source),
      "GCP_BILLING_EXPORT", trimspace(var.gcp_billing_export_source) != "" ? var.gcp_billing_export_source : local.empty_gcp_billing),
    "BILLING_RESOURCE_IDS", jsonencode([for id in var.billing_resource_ids : lower(id)])),
  ])
  cost_by_hearing_query = replace(replace(local.kql.recording_cost_by_hearing,
    "let cost_export = BILLING_EXPORT_TABLE;", "let cost_export = ${var.azure_billing_export_source};"),
  "let speech_resource_id = \"SPEECH_RESOURCE_ID\";", "let speech_resource_id = \"${lower(var.speech_resource_id)}\";")
  cost_requires_export = "**Cost allocation requires the billing export.** Usage is recorded without prices; cost is the actual cost from the Azure Cost Management export (and the GCP billing export for Vertex AI), split by each feature's share of usage. The exports do not exist yet: once PlatOps provide them, set billing_export_configured, azure_billing_export_source, billing_resource_ids and speech_resource_id on the observability module (cost_allocation.kql lists the expected columns)."

  # One entry per view: a title, intro paragraphs and one panel per section: a query and
  # its visualization or, with text, a note. Charts project the columns they plot.
  workbooks = {
    "service-health" = {
      title = "Service health"
      intro = [
        "Availability = share of server requests not answered with 5xx (4xx are client errors and count as available; health probes and synthetic traffic excluded). Target 99% or 99.5% a month, to be confirmed. Area is empty for shared paths (/health, /api/telemetry) and transcribe-web.",
        "Live dependency state: GET /api/health/dependencies on transcribe-api.",
      ]
      sections = [
        {
          name          = "endpoint-availability"
          title         = "Endpoint availability % by day, service and area"
          query         = "${local.kql.service_availability_endpoint}\n| project timestamp, series = strcat(cloud_RoleName, \" \", area), availability_pct"
          visualization = "timechart"
        },
        {
          name          = "journey-availability"
          title         = "Journey success % by day"
          query         = "${local.kql.service_availability_journey}\n| project timestamp, journey, success_pct"
          visualization = "timechart"
        },
        {
          name          = "journey-availability-table"
          title         = "Journey success: counts"
          query         = local.kql.service_availability_journey
          visualization = "table"
        },
        {
          name          = "synthetic-availability"
          title         = "Synthetic availability tests % by day"
          query         = "${local.kql.service_availability_synthetic}\n| project timestamp, test, availability_pct"
          visualization = "timechart"
        },
        {
          name          = "server-error-rate"
          title         = "HTTP 5xx rate % by hour, service and area"
          query         = "${local.kql.service_server_error_rate}\n| project timestamp, series = strcat(cloud_RoleName, \" \", area), server_error_pct"
          visualization = "timechart"
        },
        {
          name          = "dependency-up"
          title         = "Dependency up (1) or down (0), worst instance per 15 minutes"
          query         = local.kql.service_dependency_up
          visualization = "timechart"
        },
        {
          name          = "dependency-health-changes"
          title         = "Dependency health changes"
          query         = local.kql.service_dependency_health_changes
          visualization = "table"
        },
        {
          name          = "exceptions-by-type"
          title         = "Exceptions by type, service and area"
          query         = local.kql.service_exceptions_by_type
          visualization = "table"
        },
        {
          name          = "stage-metric"
          title         = "Stages: runs and average duration (metric)"
          query         = local.kql.service_stage_duration_metric
          visualization = "table"
        },
      ]
    }

    "dictation" = {
      title = "Dictation"
      intro = [
        "Readiness and latency of live dictation, session failures, autosave, submissions and document generation.",
        "Browser events are relayed by transcribe-api: a browser that closes before sending loses its events, so their counts are a lower bound. Percentiles come from events; metrics give averages.",
      ]
      sections = [
        {
          name          = "start-latency"
          title         = "Start to ready, start to first text (user starts) and resume to next text: p50 and p95, ms"
          query         = "${local.kql.dictation_latency}\n| where start_kind in (\"user\", \"resume\")\n${local.p50_p95}\n| project timestamp, series = strcat(measure, \" \", pct), ms"
          visualization = "timechart"
        },
        {
          name          = "reconnect-latency"
          title         = "Reconnects: start to ready and start to first text, p95 ms"
          query         = "${local.kql.dictation_latency}\n| where start_kind == \"reconnect\"\n| project timestamp, measure, p95_ms"
          visualization = "timechart"
        },
        {
          name          = "latency-metric"
          title         = "Token fetch, ready, first text and resume: average ms (metric)"
          query         = "${local.kql.dictation_latency_metric}\n| project timestamp, event, avg_ms"
          visualization = "timechart"
        },
        {
          name          = "session-outcomes"
          title         = "Dictation sessions by outcome per day"
          query         = "${local.kql.dictation_session_outcomes}\n| summarize sessions = sum(sessions) by timestamp, outcome"
          visualization = "barchart"
        },
        {
          name          = "session-failures"
          title         = "Session failures by code"
          query         = local.kql.dictation_session_failures
          visualization = "table"
        },
        {
          name          = "speech-cancellations"
          title         = "Speech cancellations by reason and error code"
          query         = local.kql.dictation_speech_cancellations
          visualization = "table"
        },
        {
          name          = "autosave-failures"
          title         = "Autosave failures, stalls and recoveries per day"
          query         = "${local.kql.dictation_autosave_failures}\n| project timestamp, series = strcat(event, iff(isempty(failure_kind), \"\", strcat(\" \", failure_kind))), events"
          visualization = "barchart"
        },
        {
          name          = "submissions"
          title         = "Submissions by outcome per day (server stage and browser)"
          query         = "${local.kql.dictation_submissions}\n| summarize submissions = sum(submissions) by timestamp, series = strcat(source, \" \", outcome)"
          visualization = "barchart"
        },
        {
          name          = "submission-failures"
          title         = "Submission failures by code"
          query         = "${local.kql.dictation_submissions}\n| where outcome != \"success\"\n| summarize submissions = sum(submissions) by source, outcome, code\n| order by submissions desc"
          visualization = "table"
        },
        {
          name          = "document-outcomes"
          title         = "Document generation by journey and outcome per day"
          query         = "${local.kql.dictation_document_generation}\n| summarize runs = sum(runs) by timestamp, series = strcat(journey, \" \", outcome)"
          visualization = "barchart"
        },
        {
          name          = "document-duration"
          title         = "Document generation duration (successful runs): p50 and p95, ms"
          query         = "${local.kql.dictation_document_generation}\n| where outcome == \"success\"\n${local.p50_p95}\n| project timestamp, series = strcat(journey, \" \", pct), ms"
          visualization = "timechart"
        },
        {
          name          = "document-failures"
          title         = "Document generation failures by code"
          query         = "${local.kql.dictation_document_generation}\n| where outcome != \"success\"\n| summarize runs = sum(runs) by journey, outcome, code\n| order by runs desc"
          visualization = "table"
        },
        {
          name          = "template-versions"
          title         = "Document template versions in use"
          query         = local.kql.dictation_document_template_versions
          visualization = "table"
        },
      ]
    }

    "recording" = {
      title = "Recording"
      intro = [
        "Hearing recordings from upload to transcript: uploads, the job queue, Azure Speech batch jobs, post-processing and storage.",
        "Events come from transcribe-api (uploads, job submission) and transcribe-api-worker (the batch poller). \"Queue\" means unfinished transcription jobs in the database, not a message queue.",
      ]
      sections = [
        {
          name          = "journey-availability"
          title         = "Recording job availability % by day (jobs reaching a transcript)"
          query         = "${local.kql.recording_availability_journey}\n| project day, cloud_RoleName, availability_pct"
          visualization = "timechart"
        },
        {
          name          = "availability-durations"
          title         = "Time to transcript available and end to end: p50 and p95, minutes"
          query         = local.kql.recording_availability_durations
          visualization = "timechart"
        },
        {
          name          = "upload-outcomes"
          title         = "Uploads by outcome and error code"
          query         = local.kql.recording_upload_outcomes
          visualization = "table"
        },
        {
          name          = "upload-size"
          title         = "Upload size (MiB) by format: p50, p95, max"
          query         = local.kql.recording_upload_size
          visualization = "table"
        },
        {
          name          = "upload-duration"
          title         = "Upload processing time p50 and p95, seconds (excludes the network transfer)"
          query         = "${local.kql.recording_upload_duration}\n| project day, p50_s, p95_s"
          visualization = "timechart"
        },
        {
          name          = "queue-jobs"
          title         = "Jobs waiting, running and stuck"
          query         = local.kql.recording_queue_jobs
          visualization = "timechart"
        },
        {
          name          = "queue-oldest-waiting"
          title         = "Oldest waiting job, minutes"
          query         = local.kql.recording_queue_oldest_waiting
          visualization = "timechart"
        },
        {
          name          = "queue-wait"
          title         = "Queue wait p50 and p95, minutes"
          query         = "${local.kql.recording_queue_wait}\n| project day, p50_min, p95_min"
          visualization = "timechart"
        },
        {
          name          = "poller-heartbeat"
          title         = "Job poller heartbeat: seconds since the last successful poll"
          query         = local.kql.recording_poller_heartbeat
          visualization = "timechart"
        },
        {
          name          = "stuck-jobs"
          title         = "Stuck jobs"
          query         = local.kql.recording_stuck_jobs
          visualization = "table"
        },
        {
          name          = "speech-processing"
          title         = "Azure Speech processing time p50 and p95, minutes"
          query         = "${local.kql.recording_speech_processing}\n| project day, p50_min, p95_min"
          visualization = "timechart"
        },
        {
          name          = "speech-calls"
          title         = "Azure Speech calls by operation"
          query         = local.kql.recording_speech_calls
          visualization = "table"
        },
        {
          name          = "speech-failures"
          title         = "Azure Speech call failures by operation and code, per hour"
          query         = local.kql.recording_speech_failures
          visualization = "timechart"
        },
        {
          name          = "speech-throttled"
          title         = "Azure Speech throttling (HTTP 429) per hour"
          query         = local.kql.recording_speech_throttled
          visualization = "timechart"
        },
        {
          name          = "speech-error-codes"
          title         = "Azure Speech error codes"
          query         = local.kql.recording_speech_error_codes
          visualization = "table"
        },
        {
          name          = "retries"
          title         = "Retries by operation and code"
          query         = local.kql.recording_retries
          visualization = "table"
        },
        {
          name          = "failures-by-source"
          title         = "Failed jobs by failure source per day"
          query         = local.kql.recording_failures_by_source
          visualization = "barchart"
        },
        {
          name          = "failed-jobs"
          title         = "Failed jobs by stage, code and source"
          query         = local.kql.recording_failed_jobs
          visualization = "table"
        },
        {
          name          = "stage-durations"
          title         = "Post-processing stages: runs, failures and duration"
          query         = local.kql.recording_stage_durations
          visualization = "table"
        },
        {
          name          = "stage-failures"
          title         = "Post-processing stage failures"
          query         = local.kql.recording_stage_failures
          visualization = "table"
        },
        {
          name          = "postprocess-degraded"
          title         = "Transcripts with degraded speaker processing, per day"
          query         = local.kql.recording_postprocess_degraded
          visualization = "barchart"
        },
        {
          name          = "storage-failures"
          title         = "Storage and database write failures"
          query         = local.kql.recording_storage_failures
          visualization = "table"
        },
        {
          name          = "job-duration-metric"
          title         = "Job time by phase (metric)"
          query         = local.kql.recording_job_duration_metric
          visualization = "table"
        },
        {
          name          = "transcripts-available"
          title         = "Transcripts available per day"
          query         = local.kql.recording_transcripts_available
          visualization = "table"
        },
        {
          name          = "webhooks"
          title         = "Webhooks delivered and not delivered per day"
          query         = local.kql.recording_webhooks
          visualization = "barchart"
        },
      ]
    }

    "workload" = {
      title = "Workload and capacity"
      intro = [
        "Active and finished work in both areas. Dictation concurrency is estimated from session and job journeys (there is no server-side session count).",
        "Not available: jobs waiting for the dictation upload poller, and the audio duration of live dictation (Speech-connected time is the proxy). Browser recordings are consent-gated analytics: a partial sample.",
      ]
      sections = [
        {
          name          = "throughput"
          title         = "Throughput per hour, both areas (event counter)"
          query         = local.kql.workload_throughput
          visualization = "timechart"
        },
        {
          name          = "active-sessions"
          title         = "Concurrent dictation sessions (estimate): peak per hour"
          query         = "${local.kql.dictation_workload_active_sessions}\n| summarize peak_active_sessions = max(active_sessions) by timestamp = bin(timestamp, 1h)"
          visualization = "timechart"
        },
        {
          name          = "active-jobs"
          title         = "Dictation uploaded-audio jobs in progress (estimate): peak per hour"
          query         = "${local.kql.dictation_workload_active_jobs}\n| summarize peak_active_jobs = max(active_jobs) by timestamp = bin(timestamp, 1h)"
          visualization = "timechart"
        },
        {
          name          = "daily-volume-chart"
          title         = "Dictation sessions, submissions, documents and uploaded-audio jobs per day"
          query         = "${local.kql.dictation_workload_daily_volume}\n| project timestamp, sessions_started, submissions, documents, upload_jobs"
          visualization = "barchart"
        },
        {
          name          = "daily-volume"
          title         = "Dictation daily volume (all columns)"
          query         = local.kql.dictation_workload_daily_volume
          visualization = "table"
        },
        {
          name          = "dictation-hours"
          title         = "Dictation hours per day: session time and Speech-connected time"
          query         = "${local.kql.dictation_workload_hours}\n| project timestamp, session_hours, speech_hours"
          visualization = "barchart"
        },
        {
          name          = "upload-jobs"
          title         = "Dictation uploaded-audio jobs by outcome per day"
          query         = "${local.kql.dictation_workload_upload_jobs}\n| where measure startswith \"jobs \""
          visualization = "barchart"
        },
        {
          name          = "upload-stage-durations"
          title         = "Dictation uploaded audio: transcription and minutes generation, p50 and p95, seconds"
          query         = "${local.kql.dictation_workload_upload_jobs}\n| where not(measure startswith \"jobs \")"
          visualization = "timechart"
        },
        {
          name          = "recording-throughput"
          title         = "Recording jobs completed per hour"
          query         = local.kql.workload_recording_throughput
          visualization = "timechart"
        },
        {
          name          = "recording-jobs-per-day"
          title         = "Recording jobs created and finished per day"
          query         = local.kql.recording_workload_jobs_per_day
          visualization = "barchart"
        },
        {
          name          = "recording-audio-hours"
          title         = "Recording audio hours per day: uploaded and transcribed"
          query         = local.kql.recording_workload_audio_hours
          visualization = "barchart"
        },
        {
          name          = "speech-utilisation"
          title         = "Azure Speech batch concurrency utilisation % (only when SPEECH_CONCURRENT_JOBS_LIMIT is set)"
          query         = local.kql.recording_speech_utilisation
          visualization = "timechart"
        },
        {
          name          = "browser-recordings"
          title         = "Browser recordings per day (PARTIAL: consent-gated analytics only)"
          query         = local.kql.workload_browser_recordings
          visualization = "table"
        },
      ]
    }

    "ai-usage" = {
      title = "AI usage"
      intro = [
        "LLM tokens and Azure Speech audio, by feature, for both areas (OBS-5). Usage only: no prices are recorded. Cost is the actual cost from the billing exports, split by each feature's share of usage (the last panels).",
        "Live dictation hours are the browser-reported Speech session time, an estimate. Dictation uploads (fast) and recording jobs (batch) are what Azure Speech reported. Formulas and caveats: the ai_*.kql and cost_*.kql files.",
      ]
      sections = [
        {
          name          = "tokens-by-feature"
          title         = "LLM tokens per day by feature"
          query         = "${local.kql.ai_tokens_daily}\n| summarize tokens = sum(tokens) by timestamp, feature"
          visualization = "barchart"
        },
        {
          name          = "tokens-by-model"
          title         = "LLM tokens by provider, model, feature and token type"
          query         = "${local.kql.ai_tokens_daily}\n| summarize tokens = sum(tokens), calls = sum(calls) by provider, model, feature, token_type, fallback\n| order by tokens desc"
          visualization = "table"
        },
        {
          name          = "fallback-rate"
          title         = "Fallback and error rate of LLM calls by feature"
          query         = local.kql.ai_fallback_rate
          visualization = "table"
        },
        {
          name          = "llm-errors"
          title         = "Failed LLM calls by error type"
          query         = local.kql.ai_errors_by_type
          visualization = "table"
        },
        {
          name          = "audio-hours"
          title         = "Azure Speech audio hours per day by mode and feature (realtime: browser estimate)"
          query         = "${local.kql.ai_audio_hours_daily}\n| summarize audio_hours = sum(audio_hours) by timestamp, series = strcat(mode, \" \", feature)"
          visualization = "barchart"
        },
        {
          name          = "batch-duration-source"
          title         = "Recording jobs by source of their audio seconds (azure, estimate, none)"
          query         = local.kql.ai_batch_duration_source
          visualization = "barchart"
        },
        {
          name          = "usage-trend"
          title         = "Daily usage against its trailing 7-day average (ratio; choose 8 days or more)"
          query         = "${local.kql.ai_usage_trend}\n| project timestamp, usage_measure, ratio"
          visualization = "timechart"
        },
        {
          name          = "usage-share"
          title         = "Usage share by feature per day (the input to cost allocation)"
          query         = local.kql.ai_usage_share_daily
          visualization = "table"
        },
        {
          name          = "hearing-share"
          title         = "Recording audio hours per hearing"
          query         = local.kql.recording_ai_hearing_share
          visualization = "table"
        },
        var.billing_export_configured ? {
          name          = "cost-allocation"
          title         = "Actual cost allocated to features by usage share, per day"
          query         = local.cost_allocation_query
          visualization = "table"
          } : {
          name  = "cost-allocation"
          title = "Actual cost allocated to features by usage share"
          text  = local.cost_requires_export
        },
        var.billing_export_configured ? {
          name          = "cost-by-hearing"
          title         = "Azure Speech batch cost allocated to recording hearings, per day"
          query         = local.cost_by_hearing_query
          visualization = "table"
          } : {
          name  = "cost-by-hearing"
          title = "Azure Speech batch cost allocated to recording hearings"
          text  = local.cost_requires_export
        },
      ]
    }
  }

  workbook_json = {
    for key, view in local.workbooks : key => {
      version = "Notebook/1.0"
      items = concat(
        [
          {
            type = 1
            name = "intro"
            content = {
              json = join("\n\n", concat(
                ["## ${view.title} (${var.env})"],
                view.intro,
                ["Views (${var.env}): ${local.workbook_links}"],
              ))
            }
          },
          {
            type = 9
            name = "parameters"
            content = {
              version = "KqlParameterItem/1.0"
              style   = "pills"
              parameters = [
                {
                  id         = "8d1b2f4e-6c39-4f1a-9a57-2a6f7f0c2e77"
                  version    = "KqlParameterItem/1.0"
                  name       = "TimeRange"
                  label      = "Time range"
                  type       = 4
                  isRequired = true
                  value      = { durationMs = 604800000 }
                  typeSettings = {
                    allowCustom = true
                    selectableValues = [
                      { durationMs = 86400000 },
                      { durationMs = 604800000 },
                      { durationMs = 2592000000 },
                    ]
                  }
                },
              ]
            }
          },
        ],
        [
          for section in view.sections : try(section.text, null) != null ? {
            type    = 1
            name    = section.name
            content = { json = "### ${section.title}\n\n${section.text}" }
            } : {
            type = 3
            name = section.name
            content = {
              version                  = "KqlItem/1.0"
              title                    = section.title
              query                    = section.query
              size                     = 0
              queryType                = 0
              resourceType             = "microsoft.insights/components"
              timeContextFromParameter = "TimeRange"
              visualization            = section.visualization
            }
          }
        ],
      )
      fallbackResourceIds = [var.application_insights_id]
      "$schema"           = "https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json"
    }
  }
}

resource "azurerm_application_insights_workbook" "this" {
  for_each = var.workbooks_enabled ? toset(local.workbook_keys) : toset([])

  name                = local.workbook_names[each.key]
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "${var.product} ${lower(local.workbooks[each.key].title)} (${var.env})"
  source_id           = lower(var.application_insights_id)
  category            = "workbook"
  data_json           = jsonencode(local.workbook_json[each.key])
  tags                = var.tags
}
