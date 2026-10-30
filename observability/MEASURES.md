# Measures (OBS-8)

The catalogue of the measures behind the transcribe product's views, for both areas of
transcribe-api: dictation and recording. Each measure is one query file in `kql/`. Each file starts
with a `//` comment giving the measure, the formula, the source and the caveats. The file is
authoritative; this page summarises it. Alert queries are in [ALERTS.md](ALERTS.md); the
validation procedure is in [VALIDATION.md](VALIDATION.md).

| Ticket | What | Section |
|---|---|---|
| DIAAT-277 | Availability: endpoint, journey, synthetic, dependencies, errors, poller heartbeat | [Service](#service-diaat-277) |
| DIAAT-284 | Dictation views and workload | [Dictation](#dictation-diaat-284), [Workload](#workload-diaat-284) |
| DIAAT-280, DIAAT-281, DIAAT-282, DIAAT-283 | Recording pipeline: upload, queue, Speech, post-processing, storage, availability | [Recording](#recording-diaat-280-to-283) |
| OBS-5 | AI usage and cost allocation | [AI usage](#ai-usage-obs-5), [Cost](#cost-obs-5) |

## How to read the measures

- **One Application Insights resource per environment** (aat, perftest, ithc, demo, prod). To see
  an environment, query its resource. No query splits by environment.
- **The time range comes from the caller** (a workbook, an alert window, or Logs). The files take
  no parameters, except the cost queries' placeholders.
- **Workbooks** (`workbooks.tf`): service health, dictation, recording, workload and AI usage, one
  set per environment. Each panel is one of these files, sometimes with a `project` for its chart.
  Until they are created (PlatOps must allow the resource type), run the files in Logs.
- **Services** (`cloud_RoleName`): `transcribe-api` (the API pods), `transcribe-api-worker` (the
  pollers and the jobs they run), `transcribe-web` (the Next.js server). Browser events reach App
  Insights through `transcribe-api`'s `POST /api/telemetry`.
- **Sampling is 100%.** Events (`customEvents`) and metrics (`customMetrics`) are complete while the
  app can export. The queries still `sum(itemCount)` where they count events.
- **Browser events are a lower bound.** A browser that closes before it sends its batch loses its
  events.
- **Percentiles come from events.** App Insights stores only the count, sum, minimum and maximum of a
  histogram metric (no buckets), so metrics give counts, averages and maxima, and p50/p95 come from
  `hmcts.duration_ms` on events.
- **Gauges are aggregated with max, never sum.** Each replica reports the same database-wide value.

### The area rule

`hmcts.area` (`dictation` or `recording`) is set by transcribe-api on every request, event, log and
span of an area. Shared code has none (the top-level `/health`, the dependency checker, the browser
relay). Relayed browser events carry none either, so every query for one area filters on
`hmcts.area` and falls back to the journey type's prefix (`dictation.session` is `dictation`).
Requests fall back to the mount point: `/api/v1/*` is recording, the rest of `/api/*` dictation.
Metrics never carry `hmcts.area`: a metric is either one area's own (the `transcription.*` metrics
are recording's) or split by journey type or feature. Event names that both areas emit
(`job.finished`, `transcript.available`, the `upload.*` stage events,
`security.ownership_violation`, `audit.write_failed`) always need the filter.
`tests/check_kql_names.py` fails a `dictation_*` or `recording_*` file that does not filter. The
full rule is in [README.md](README.md#telling-the-areas-apart).

## Service (DIAAT-277)

Cross-area. Targets: 99% or 99.5% over a calendar month, **still to be confirmed** (DIAAT-277 AC3).

| Measure | Query file | Formula | Source | Caveats |
|---|---|---|---|---|
| Endpoint availability % | `kql/service_availability_endpoint.kql` | Per day, service and area: 100 × (requests − unavailable) / requests. Unavailable = 5xx, or failed with no status (0 or missing) | `requests` | 4xx count as available. Health and version probes and synthetic traffic excluded. Area empty for shared paths and transcribe-web. A day with no requests has no row |
| Journey availability % | `kql/service_availability_journey.kql` | Per day and journey: 100 × succeeded / counted. `dictation.session`: success or cancelled out of all four outcomes. `dictation.submission`, `dictation.transcription`, `recording.job`: success out of success + error | `dictation.session_ended`; `submission.*`; `job.finished` split by area | `failure` (client rejection) and `cancelled` are excluded and shown as `excluded`. Lost browser events lower the volume, not the rate. Jobs that never finish have no `job.finished` |
| Synthetic availability % | `kql/service_availability_synthetic.kql` | Per test and day: 100 × successful runs / runs | `availabilityResults` (standard web tests) | Every location's run counts once. A redirect to sign-in is a failure. No tests exist yet: which URLs the test agents can reach is a PlatOps question |
| HTTP server error rate | `kql/service_server_error_rate.kql` | Per hour, service and area: server errors / requests | `requests` | Same definition and exclusions as endpoint availability |
| Exceptions by type | `kql/service_exceptions_by_type.kql` | Exceptions per type, service and area, with last seen | `exceptions` | Type and stack only, never the message. Area empty for shared code |
| Dependency health | `kql/service_dependency_up.kql` | `min(service.dependency.up)` per 15 minutes and dependency (`database`, `storage`, `speech`) | Gauge from the checker in transcribe-api, every `DEPENDENCY_HEALTH_INTERVAL_SECONDS`, Speech at most every 5 minutes | 0 means at least one API instance saw it down. No points: not checked |
| Dependency health changes | `kql/service_dependency_health_changes.kql` | Each up/down transition, newest first, with `hmcts.error.code` | `dependency.health_changed` | Codes: `dependency.timeout`, `dependency.auth_failed`, `dependency.unreachable`, `dependency.error`. Never a host or message |
| Stage runs and average duration | `kql/service_stage_duration_metric.kql` | Per day, area, stage, journey and outcome: runs = Σ count; avg = Σ sum / Σ count; max | Metric `hmcts.stage.duration` | Area from the journey type; `speech_token` and `minutes_edit` outside a journey count as dictation. No percentiles |
| Recording poller heartbeat | `kql/recording_poller_heartbeat.kql` | Max of `transcription.poller.last_success_age` per 15 minutes and worker instance | Gauge from transcribe-api-worker | Rises past a few poll intervals (30 s) only when the loop is stuck or every poll fails. Dictation's poller has no heartbeat |
| Recording journey availability by failure source | `kql/recording_availability_journey.kql` | Per day and service: 100 × succeeded / (succeeded + unavailable), with failures by `hmcts.failure.source` | `job.finished` (recording) | Client failures excluded and shown as `client_failures`. A missing source counts as unavailable. The cross-area figure is `service_availability_journey.kql` |

## Dictation (DIAAT-284)

Events from transcribe-web (OBS-4: DIAAT-278, DIAAT-300) relayed by `POST /api/telemetry`, and
server events from transcribe-api (DIAAT-276, DIAAT-279).

| Measure | Query file | Formula | Source | Caveats |
|---|---|---|---|---|
| Start to ready, start to first text, resume to next text (p50/p95) | `kql/dictation_latency.kql` | Percentiles of `hmcts.duration_ms` per hour, measure and start kind (user, reconnect, resume, unknown) | Browser `speech.session_started`, `speech.first_result`, `dictation.resume_first_result`; start kind from `dictation.session_requested` | First text includes the time before the user speaks. A throttled background tab can stretch durations |
| Dictation timings, averages | `kql/dictation_latency_metric.kql` | Per hour and event: avg and max ms, samples | Metric `hmcts.event.duration` (`event` dimension), incl. `speech.token_fetched` | Averages and maxima only. No area filter: the four event names are dictation's only |
| Sessions by outcome | `kql/dictation_session_outcomes.kql` | Sessions per day, outcome, code and end reason | `dictation.session_ended` | Outcomes: success, cancelled (nothing lost), failure (`dictation.no_transcript`), error. Lower bound |
| Session failures by code | `kql/dictation_session_failures.kql` | Failed sessions per code, outcome and end reason; share of all sessions; mean Speech sessions and autosave failures | `dictation.session_ended`, outcome failure or error | Cancelled sessions are not failures |
| Speech cancellations | `kql/dictation_speech_cancellations.kql` | Events and distinct sessions per event, reason and Speech error code | `speech.canceled`, `speech.unhealthy` | `EndOfStream` and `CancelledByUser` are usually benign. dcount has about 1% error |
| Autosave failures | `kql/dictation_autosave_failures.kql` | Events and distinct sessions per day, event and failure kind | `live_draft.save_failed`, `.autosave_stalled`, `.save_recovered`; `dictation.session_ended` with `autosave.failed` | `auth` is sign-in expiry, not a storage fault |
| Submissions by outcome | `kql/dictation_submissions.kql` | Per day, source (server, browser), outcome and code: count, p50/p95 duration | Server `submission.*` (journey `dictation.submission`); browser `dictation.submission_finished` | The browser sees requests that never reached the API. Browser counts are a lower bound |
| Document generation | `kql/dictation_document_generation.kql` | Runs per day, journey, outcome and code; p50/p95 of stage time | `document_generation.*` (decision document; uploaded-audio document) | Codes: `document.render_failed`, `document.store_failed`, `document.not_generated`. Documents users can open: `document.available` |
| Template versions in use | `kql/dictation_document_template_versions.kql` | Per template and version: runs, failed, first and last seen | `document_generation.completed`/`.failed` with `document.template_version` | Two versions overlapping means instances on different releases. A run that failed before loading has `unknown` |

## Recording (DIAAT-280 to 283)

Events and metrics from transcribe-api (uploads, job submission) and transcribe-api-worker (the
batch poller). Events keep `hmcts.area == "recording"`; the `transcription.*` metrics are
recording's own.

| Measure | Query file | Formula | Source | Caveats |
|---|---|---|---|---|
| Uploads by outcome and code | `kql/recording_upload_outcomes.kql` | Count by outcome and code; share of all recording uploads | `upload.completed`, `upload.failed` (`POST /api/v1/uploads`) | `upload.validation_failed` is not counted again. Requests refused before the handler (401, 429) have no stage events |
| Upload size | `kql/recording_upload_size.kql` | p50, p95, max MiB by format and outcome | `file.size_bytes`, `audio.format` on upload events | Size as received, before transcoding. Rejected types have format `unknown` |
| Upload processing time | `kql/recording_upload_duration.kql` | p50/p95 seconds of `hmcts.duration_ms` per day | `upload.completed` | Excludes the network transfer from the browser and rejected uploads |
| Waiting, running and stuck jobs | `kql/recording_queue_jobs.kql` | Max per 15 minutes and series | Gauges `transcription.jobs.waiting`, `.running`, `.stuck` (`job.state`) | "Queue" means unfinished rows in `transcription_job`, not a message queue |
| Oldest waiting job | `kql/recording_queue_oldest_waiting.kql` | Max of `transcription.jobs.oldest_waiting_age` / 60 per 15 minutes | Gauge | Jobs already reported stuck are left out. 0 when nothing waits |
| Queue wait (p50/p95) | `kql/recording_queue_wait.kql` | Percentiles of `hmcts.duration_ms` / 60000 per day | `speech.job_running` | A job Azure finishes between two polls is never seen running and is missing. Includes up to one poll interval |
| Stuck jobs | `kql/recording_stuck_jobs.kql` | One row per `job.stuck`, newest first | `job.stuck` (state, source, time stuck, job ID, Speech job ID) | Observation only. Thresholds `JOB_STUCK_WAITING_SECONDS` (30 min) and `JOB_STUCK_RUNNING_SECONDS` (3 h) |
| Speech processing time (p50/p95) | `kql/recording_speech_processing.kql` | Percentiles of `job.processing_ms` / 60000 per day | `job.finished` | Missing for jobs that never reached Azure, or that Azure finished between two polls |
| Speech calls by operation | `kql/recording_speech_calls.kql` | Per operation: calls, avg and max ms, failures, failure %, throttled | Metrics `transcription.speech.call.duration`, `.call.failures`, `transcription.speech.throttled` | Each retry is a call. A 404 on delete is success. Live dictation Speech sessions are not here |
| Speech call failures | `kql/recording_speech_failures.kql` | Failures per hour, operation and code | `transcription.speech.call.failures` | Calls, not jobs |
| Speech throttling | `kql/recording_speech_throttled.kql` | HTTP 429s per hour and operation | `transcription.speech.throttled` | No rows means no throttling |
| Retries | `kql/recording_retries.kql` | Retries by operation and code | `transcription.job.retries` | A retry that then succeeds is still counted |
| Azure Speech error codes | `kql/recording_speech_error_codes.kql` | Events by event, Speech code and HTTP status | `job.finished`, `job.retried`, `job.poll_failed` with `speech.error_code` | Azure's code only, never its message. Absent when Azure sent no parsable code |
| Failed jobs by failure source | `kql/recording_failures_by_source.kql` | Jobs not successful, per day, source and outcome | Counter `transcription.jobs.finished` | `failure` (client) is shown here but excluded from availability |
| Failed jobs by stage, code and source | `kql/recording_failed_jobs.kql` | Failed jobs by where they failed (last `<stage>.failed`, `speech_processing`, or `unknown`), code, source, Speech code, outcome | `job.finished` joined to stage events by job ID | A stage failure before the time range shows as `unknown` |
| Post-processing stages | `kql/recording_stage_durations.kql` | Per stage: runs, failed, failure %, p50/p95 (events), max (metric) | `hmcts.stage.duration` limited to recording's stages; `<stage>.completed` | Attempts, not jobs. No stitching step |
| Post-processing stage failures | `kql/recording_stage_failures.kql` | Failures by stage, outcome and code, with last seen | `<stage>.failed` | `result_processing.failed` repeats the step's code and is left out |
| Degraded speaker processing | `kql/recording_postprocess_degraded.kql` | Transcripts per day by skipped step | `transcript.postprocess_degraded` | The job still succeeds |
| Storage failures | `kql/recording_storage_failures.kql` | Failures by operation and code, with last seen | `job.storage_failed`; `upload.failed` with `storage.write_failed` (as `upload.blob_write`) | Counts attempts: a failed save is retried |
| Time to available and end to end (p50/p95) | `kql/recording_availability_durations.kql` | Percentiles in minutes per day | `transcript.available` (to available), `job.finished` success (end to end) | End to end starts at job creation, after the upload |
| Job time by phase (metric) | `kql/recording_job_duration_metric.kql` | Per phase and outcome: jobs, avg and max minutes | `transcription.job.duration` (`phase`) | No percentiles. Use it to check the event-based figures are complete |
| Transcripts available | `kql/recording_transcripts_available.kql` | Count per day; average segments and speakers | `transcript.available` | Counts only, never text or names. Not a quality measure |
| Webhooks | `kql/recording_webhooks.kql` | Delivered and not delivered per day and notification | `webhook.delivered`, `webhook.delivery_failed` | `POST /api/v1/jobs` sets no callback URL, so no rows is expected |

## Workload (DIAAT-284)

| Measure | Query file | Formula | Source | Caveats |
|---|---|---|---|---|
| Concurrent dictation sessions (estimate) | `kql/dictation_workload_active_sessions.kql` | Sessions whose start-to-end overlaps each 5-minute slot | All `dictation.session` journey events; end from `dictation.session_ended` duration | Lower bound. Includes paused sessions. Capped at 12 hours. No server-side session count exists |
| Uploaded-audio jobs in progress (estimate) | `kql/dictation_workload_active_jobs.kql` | Jobs whose start-to-end overlaps each 5-minute slot | `transcription.started`, `job.finished` (dictation) | Capped at 6 hours. Jobs waiting for the poller are not visible |
| Dictation workload per day | `kql/dictation_workload_daily_volume.kql` | Sessions started, ended, submitted; submissions and successes; documents; upload jobs and successes | Session, submission, `document.available`, `job.finished` events | Browser counts are a lower bound |
| Dictation hours | `kql/dictation_workload_hours.kql` | Σ session length and Σ Speech-connected time per day, in hours | `dictation.session_ended`, `speech.session_stopped` | Proxies: no audio duration is recorded for live dictation. The relay caps one duration at 24 hours |
| Uploaded-audio jobs and stage time | `kql/dictation_workload_upload_jobs.kql` | Jobs per day by outcome and code; p50/p95 seconds of transcription and minutes generation | `job.finished`, `transcription.completed`, `minutes_generation.completed` | No audio duration, so no time per audio hour |
| Throughput, both areas | `kql/workload_throughput.kql` | Events per hour and event name | Counter `hmcts.events` | `job.finished` here is both areas together (metrics carry no area) |
| Recording throughput | `kql/workload_recording_throughput.kql` | Successful jobs per hour | `transcription.jobs.finished` | Low throughput with nothing waiting is not a capacity problem |
| Recording jobs per day | `kql/recording_workload_jobs_per_day.kql` | Created per day; finished per day by outcome | `job.created` (recording); `transcription.jobs.finished` | A job may finish on another day |
| Recording audio hours | `kql/recording_workload_audio_hours.kql` | Hours uploaded (accepted) and hours in completed jobs, per day | `upload.completed` `audio.duration_seconds`, joined to `job.finished` success | A job whose upload is before the range is not counted |
| Speech concurrency utilisation | `kql/recording_speech_utilisation.kql` | 100 × max per 15 minutes | Gauge `transcription.speech.concurrency.utilisation` | Emitted only when `SPEECH_CONCURRENT_JOBS_LIMIT` is set on the worker (it is not set today). Live dictation is not counted |
| Browser recordings (partial) | `kql/workload_browser_recordings.kql` | Recordings and audio hours per day and mode | `recording.completed` (dictation-area mic or screen recording) | Consent-gated: only users who accepted analytics cookies. A partial sample, not a total |

## AI usage (OBS-5)

Usage only: no prices or cost are recorded anywhere. No prompt or response content is read or
recorded. Metrics carry no area: the feature (`hmcts.ai.feature`) and the Speech mode tell the
areas apart.

| Measure | Query file | Formula | Source | Caveats |
|---|---|---|---|---|
| Azure Speech audio hours | `kql/ai_audio_hours_daily.kql` | Σ seconds / 3600 per day, mode, feature, outcome and basis | `hmcts.speech.audio.duration` (server: fast = dictation uploads, batch = recording jobs); `hmcts.event.duration` of browser `speech.session_stopped` (realtime = live dictation, `browser_estimate`) | The live dictation figure is an estimate and a lower bound. A recording job processed twice counts twice. Jobs that fail in Azure record nothing |
| Source of recording's audio seconds | `kql/ai_batch_duration_source.kql` | Jobs per day by duration source: `azure`, `estimate`, `none` | `transcription.speech.usage.jobs` | Many `estimate` or `none` make batch hours and their cost share less exact |
| LLM tokens | `kql/ai_tokens_daily.kql` | Tokens and calls per day, provider, model, feature, token type and fallback flag | `gen_ai.client.token.usage` | Failed calls count 0 tokens unless the provider reported usage |
| LLM fallback and error rate | `kql/ai_fallback_rate.kql` | Per feature: calls, fallback calls and %, error calls and % | `hmcts.ai.requests` | Every attempt is a call. Errors inside litellm's own fallback chain are a lower bound |
| LLM errors by type | `kql/ai_errors_by_type.kql` | Failed calls by exception class, provider, model and feature; share | `hmcts.ai.requests` with outcome `error` | A Gemini content-filter block is an error (then a fallback) |
| Usage trend | `kql/ai_usage_trend.kql` | Per day: usage, trailing 7-day average (days with no usage count as 0), ratio | Tokens; audio hours as above | Use at least 8 days. The spike alerts compare with the previous day instead (ALERTS.md) |
| Usage share by feature | `kql/ai_usage_share_daily.kql` | Per day, meter group (`azure_llm`, `gcp_llm`, `other_llm`, `azure_speech`), unit and feature: share of the unit and of the group | As above | No usage in a group means no share. The input to cost allocation |
| Recording audio hours per hearing | `kql/recording_ai_hearing_share.kql` | Per hearing: jobs, estimated jobs, hours, share % | `job.finished` success (`speech.audio_duration_s`), else the upload's `audio.duration_seconds`; hearing = the upload's `hmcts.journey.parent_id` | transcribe-web sends no hearing ID yet (`X-Hearing-Id`), so every upload is its own hearing |

## Cost (OBS-5)

Cost is the actual cost from the billing exports, split by usage share at query time. There is no
price table. **Both queries need billing exports that do not exist yet** (a PlatOps question: where
the exports land, their schedule and delay, and who may read them). Until then the cost panels
show a note instead.

| Measure | Query file | Formula | Source | Caveats |
|---|---|---|---|---|
| AI cost allocated by feature, both areas | `kql/cost_allocation.kql` | Per day: cost of a meter group and unit × the feature's `share_of_unit` (unit `any`: `share_of_group`) | Azure Cost Management export (and optionally the GCP billing export) plus `usage_share()` = `ai_usage_share_daily.kql` | Not runnable as is: placeholders `AZURE_BILLING_EXPORT`, `GCP_BILLING_EXPORT`, `BILLING_RESOURCE_IDS`. Exports arrive late and can be restated: use whole past days. Check the meter-name rules against the first real export |
| Speech batch cost by hearing | `kql/recording_cost_by_hearing.kql` | Per day: batch Speech cost × the hearing's share of that day's recording seconds | Cost Management export; `job.finished` and `upload.completed` (recording) | Placeholders `BILLING_EXPORT_TABLE`, `SPEECH_RESOURCE_ID`. The Speech account serves both areas, so only meters with "Batch" are recording's. No hearing IDs yet |

## Not available

- **Jobs waiting for the dictation upload poller:** no queue metric, and a direct-to-storage upload
  sends no event when the file arrives.
- **Audio duration of live dictation:** the browser streams audio to Speech; the Speech-connected
  time is the proxy.
- **Exact concurrent dictation sessions:** the page heartbeat stays in the browser.
- **Percentiles from metrics:** no histogram buckets in App Insights.
- **Stitching of multi-file hearings:** there is none; one transcript per job (DIAAT-283).

## Access

This module grants nothing. To read the data, a person needs Reader (or Monitoring Reader) on the
environment's Application Insights resource or its resource group; Workbook Reader alone opens a
workbook but not the data. Who gets which role in which environment is a PlatOps decision. Whether
Dynatrace reads this telemetry (through an Azure Monitor integration or an OpenTelemetry export) is
a PlatOps question.

## Name check

`tests/check_kql_names.py` checks every name each file uses against `telemetry-names.txt`, which
is generated from transcribe-api. See [README.md](README.md#checks).
