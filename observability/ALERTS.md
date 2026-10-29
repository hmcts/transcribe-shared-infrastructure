# Alerts (DIAAT-285)

The alert queries for transcribe-api, both areas (dictation and recording), and how to respond
to each alert. The queries are the `kql/alert_*.kql` files in this module. Each file starts with a
`//` comment that gives the measure, the source and the caveats. The file is authoritative: if this
page and a file disagree, the file is right and this page needs fixing.

> **Status: off.** The rules and action groups are defined in `alerts.tf` and created only when
> `alerts_enabled` is true (the root's `observability_alerts_enabled`, default false). They
> cannot be switched on until PlatOps decide the route and allow the resource types.
>
> Open with PlatOps:
> - **Routing.** Whether alerts go to Dynatrace, to a Slack action group, or to our own action
>   groups. Until this is answered, "Route" below names the receiving team only.
> - **Resource types.** Whether scheduled query rules (`azurerm_monitor_scheduled_query_rules_alert_v2`),
>   metric alerts, action groups, workbooks and standard web tests are allowed.
> - **Owner teams.** The service team and Security are placeholders until PlatOps confirms them.
> - **Severity scale.** The heritage dictation rules used 1 (critical) and 2 (warning). The
>   heritage recording rules used the Azure scale 0 to 4. `alerts.tf` uses 1 critical, 2 warning,
>   3 informational and 4 test; to be agreed.
>
> The thresholds are **provisional**. They come from technical refinement, before any baseline
> data. Revise them once a few weeks of data exist (see [Revising thresholds](#revising-thresholds)).

## Contents

- [How the rules use these queries](#how-the-rules-use-these-queries)
- [No content in alerts (AC3)](#no-content-in-alerts-ac3)
- [Alert summary](#alert-summary)
- [Common first checks on AKS](#common-first-checks-on-aks)
- [Service alerts](#service-alerts)
- [Dictation alerts](#dictation-alerts)
- [Recording alerts](#recording-alerts)
- [Not covered by a query alert](#not-covered-by-a-query-alert)
- [Controlled tests (AC2)](#controlled-tests-ac2)
- [Revising thresholds](#revising-thresholds)

## How the rules use these queries

- Every rule is a scheduled log query on the environment's Application Insights resource (one per
  environment: aat, perftest, ithc, demo, prod). No query splits by environment.
- The rule's window is the query's time range. The queries have no time filter of their own,
  except the two AI spike queries, which read 2 days.
- Some queries need a parameter. `alerts.tf` prepends it as a `let` line, for example
  `let min_requests = 20;`. To run such a query by hand in Logs, prepend the same line. The
  parameter and its Logs example are in the file's comment.
- The rule's measure and dimensions must be columns of the file's final `| project`. The column
  names below are copied from those lines. The Terraform must use these names.
- Sampling is 100%, so counts are complete. Browser events relayed through `POST /api/telemetry`
  are lost if the browser closes before it sends them, so browser counts are a lower bound.

### Output columns

Each file's final `| project`, in order. These are the only names a rule may use as its measure or
dimensions.

| Query file | Output columns |
|---|---|
| `kql/alert_service_unavailable.kql` | `cloud_RoleName, area, requests, availability_pct` |
| `kql/alert_service_server_errors.kql` | `cloud_RoleName, area, requests, server_error_pct` |
| `kql/alert_service_dependency_down.kql` | `dependency, up` |
| `kql/alert_service_ownership_violation.kql` | `area, outcome, resource_type, action, violations` |
| `kql/alert_service_ownership_violation_test.kql` | `outcome, resource_type, violations` |
| `kql/alert_service_ai_usage_spike.kql` | `feature, audio_hours, baseline_hours, spike_ratio` |
| `kql/alert_service_ai_token_spike.kql` | `feature, tokens, baseline_tokens, spike_ratio` |
| `kql/alert_dictation_session_failures.kql` | `error_code, failures` |
| `kql/alert_dictation_speech_failures.kql` | `error_code, failures` |
| `kql/alert_dictation_speech_unhealthy.kql` | `failures, failed_pct` |
| `kql/alert_dictation_no_speech.kql` | `failures, failed_pct` |
| `kql/alert_dictation_autosave_stalled.kql` | `failed_pct, failures, sessions` |
| `kql/alert_dictation_submission_failures.kql` | `error_code, failures` |
| `kql/alert_dictation_document_generation_failures.kql` | `source, error_code, failures` |
| `kql/alert_dictation_upload_job_failures.kql` | `error_code, failures` |
| `kql/alert_dictation_upload_jobs_stuck.kql` | `stuck, oldest_waiting_min` |
| `kql/alert_recording_poller_stalled.kql` | `last_success_age_s` |
| `kql/alert_recording_stuck_jobs.kql` | `state, stuck` |
| `kql/alert_recording_oldest_waiting.kql` | `oldest_waiting_min` |
| `kql/alert_recording_failed_jobs.kql` | `source, failed, failed_pct` |
| `kql/alert_recording_speech_timeouts_throttling.kql` | `error_code, failures` |
| `kql/alert_recording_speech_connection_failures.kql` | `error_code, failures` |
| `kql/alert_recording_storage_failed.kql` | `operation, error_code, failures` |
| `kql/alert_recording_upload_failures.kql` | `outcome, error_code, failures` |

### Columns renamed from the heritage queries

The merged queries use one vocabulary: `error_code` for a code and `failures` for a count of
failures. Update any rule, runbook or receiver that used the heritage names.

| Alert query | Heritage columns | Columns now |
|---|---|---|
| `kql/alert_service_unavailable.kql` | dictation `endpoint_availability.kql`: `cloud_RoleName, availability_pct, error_rate_pct, requests, server_errors`; recording: `cloud_RoleName, requests, availability_pct` | `cloud_RoleName, area, requests, availability_pct` |
| `kql/alert_service_server_errors.kql` | dictation: `error_rate_pct` (in `endpoint_availability.kql`); recording: `cloud_RoleName, requests, server_error_pct` | `cloud_RoleName, area, requests, server_error_pct` |
| `kql/alert_service_dependency_down.kql` | dictation: `dependency, down_pct, down_samples, samples`; recording: `dependency, up` | `dependency, up` |
| `kql/alert_service_ownership_violation.kql` | dictation: `resource_type, action, outcome, events, request_ids`; recording: `outcome, resource_type, action, violations` | `area, outcome, resource_type, action, violations` (no request IDs) |
| `kql/alert_service_ai_usage_spike.kql` | dictation `ai_usage_spike.kql`: `usage_measure, usage_last_day, usage_previous_day, spike_ratio`; recording: `feature, audio_hours, baseline_hours, spike_ratio` | `feature, audio_hours, baseline_hours, spike_ratio` |
| `kql/alert_service_ai_token_spike.kql` | dictation `ai_usage_spike.kql` (the `llm_tokens` rows) | `feature, tokens, baseline_tokens, spike_ratio` |
| `kql/alert_dictation_session_failures.kql` | `code, sessions` | `error_code, failures` |
| `kql/alert_dictation_speech_failures.kql` | `error_code, sessions, events` | `error_code, failures` |
| `kql/alert_dictation_autosave_stalled.kql` | `stalled_pct, stalled_sessions, sessions` | `failed_pct, failures, sessions` |
| `kql/alert_dictation_submission_failures.kql` | `code, submissions` | `error_code, failures` |
| `kql/alert_dictation_document_generation_failures.kql` | `journey, code, runs` | `source, error_code, failures` |
| `kql/alert_dictation_upload_job_failures.kql` | `code, jobs` | `error_code, failures` |
| `kql/alert_dictation_upload_jobs_stuck.kql` | `age_minutes` (one row per job) | `stuck, oldest_waiting_min` (one row; the Maximum is the same) |

The recording queries kept their heritage columns. The two `area` columns are new: a failing area
is now visible even when the other area is busy.

## No content in alerts (AC3)

An alert notification carries the rule's name and description, the measure's value, the
threshold, the dimension values and a link to the results in the portal. So every alert query
ends with a `| project` of safe columns only: counts, rates, codes, sources, states, areas, and
service and dependency names. No query returns a URL, operation name, user, record ID, title,
file name, exception message or the whole `customDimensions`.

`tests/check_kql_names.py` enforces this for every `kql/alert_*.kql` file. It fails a query that
outputs any other column, computes a column in its final `project`, reads `customDimensions`
whole or a key outside its safe list, mentions a content-bearing column, or uses `url` anywhere
but a `| where` filter. The application does not record transcript, audio, case or party content,
or file names, in telemetry at all (DIAAT-205, DIAAT-280), so the linked results cannot hold them
either.

The ownership-violation alert says what kind of violation happened, never who or which record.
The [investigator query](#investigating-an-ownership-violation) finds that, outside the alert.

## Alert summary

"Heritage" values are those of the heritage `alerts.tf` and `variables.tf` (dictation:
courtstranscribe; recording: batch-audio-transcription-infra). Where both areas had the alert
with different values, both are shown and the merged value is **to be agreed**. "Provisional"
marks a value suggested by the query file for an alert that is new. Windows and frequencies are
ISO 8601 durations as the Terraform takes them.

| Alert | Query file | Measure (aggregation, operator, threshold) | Window / frequency | Sev | Dimensions | Route |
|---|---|---|---|---|---|---|
| [service-unavailable](#service-unavailable) | `kql/alert_service_unavailable.kql` | `availability_pct` (Minimum, LessThan): dictation 90, recording 95, to be agreed. `min_requests`: dictation 20, recording 10, to be agreed | PT15M / PT5M | dictation 1, recording 0 | `cloud_RoleName`, `area` | service team |
| [server-errors](#server-errors) | `kql/alert_service_server_errors.kql` | `server_error_pct` (Maximum, GreaterThan): dictation 2, recording 5, to be agreed. `min_requests` 20 | dictation PT30M / PT10M, recording PT1H / PT15M, to be agreed | dictation 2, recording 3 | `cloud_RoleName`, `area` | service team |
| [dependency-down](#dependency-down) | `kql/alert_service_dependency_down.kql` | `up` (Maximum, LessThan, 1) | PT10M (`dependency_down_minutes`) / PT5M | 1 | `dependency` | service team |
| [ownership-violation](#ownership-violation) | `kql/alert_service_ownership_violation.kql` | `violations` (Total, GreaterThan, 0) | dictation PT10M / PT5M, recording PT5M / PT5M, to be agreed | 1 | `area`, `outcome`, `resource_type`, `action` | Security |
| [ownership-violation-test](#ownership-violation-test) | `kql/alert_service_ownership_violation_test.kql` | `violations` (Total, GreaterThan, 0) | PT5M / PT5M | 4, named `[TEST]` | `outcome` | Security |
| [ai-usage-spike](#ai-usage-spike) | `kql/alert_service_ai_usage_spike.kql` | `spike_ratio` (Maximum, GreaterThan, 3). `min_baseline_hours`: recording 1; dictation had another rule (both days at least 2 hours), to be agreed | P2D / dictation PT6H, recording PT1H, to be agreed | dictation 2, recording 3 | `feature` | service team |
| [ai-token-spike](#ai-token-spike) | `kql/alert_service_ai_token_spike.kql` | `spike_ratio` (Maximum, GreaterThan, 3). `min_baseline_tokens`: to be agreed (dictation had both days at least 200,000 tokens; the file's Logs example is 10000) | P2D / PT6H | 2 | `feature` | service team |
| [dictation-session-failures](#dictation-session-failures) | `kql/alert_dictation_session_failures.kql` | `failures` (Total, GreaterThanOrEqual, 5) | PT30M / PT10M | 2 | none (heritage) | service team |
| [speech-failures](#speech-failures) | `kql/alert_dictation_speech_failures.kql` | `failures` (Total, GreaterThanOrEqual, 3) | PT30M / PT10M | 2 | `error_code` | service team |
| [speech-unhealthy](#speech-unhealthy) | `kql/alert_dictation_speech_unhealthy.kql` | `failures` (Total, GreaterThanOrEqual, 3), provisional | PT30M / PT10M, provisional | 2, provisional | none | service team |
| [no-speech](#no-speech) | `kql/alert_dictation_no_speech.kql` | `failures` (Total, GreaterThanOrEqual, 5), provisional | PT30M / PT10M, provisional | 2, provisional | none | service team |
| [autosave-stalled](#autosave-stalled) | `kql/alert_dictation_autosave_stalled.kql` | `failed_pct` (Maximum, GreaterThan, 10), with `\| where sessions >= 5` appended | PT30M / PT10M | 2 | none | service team |
| [submission-failures](#submission-failures) | `kql/alert_dictation_submission_failures.kql` | `failures` (Total, GreaterThanOrEqual, 2) | PT30M / PT10M | 2 | none (heritage) | service team |
| [document-generation-failures](#document-generation-failures) | `kql/alert_dictation_document_generation_failures.kql` | `failures` (Total, GreaterThanOrEqual, 2) | PT30M / PT10M | 2 | none (heritage) | service team |
| [upload-job-failures](#upload-job-failures) | `kql/alert_dictation_upload_job_failures.kql` | `failures` (Total, GreaterThanOrEqual, 3) | PT1H / PT15M | 2 | none (heritage) | service team |
| [upload-jobs-stuck](#upload-jobs-stuck) | `kql/alert_dictation_upload_jobs_stuck.kql` | `oldest_waiting_min` (Maximum, GreaterThan, 120) | PT6H / PT30M | 2 | none | service team |
| [poller-stalled](#poller-stalled) | `kql/alert_recording_poller_stalled.kql` | `last_success_age_s` (Minimum, GreaterThan, 600) | PT10M / PT5M | 1 | none | service team |
| [stuck-jobs](#stuck-jobs) | `kql/alert_recording_stuck_jobs.kql` | `stuck` (Maximum, GreaterThan, 0) | PT15M / PT5M | 2 | `state` | service team |
| [oldest-waiting](#oldest-waiting) | `kql/alert_recording_oldest_waiting.kql` | `oldest_waiting_min` (Maximum, GreaterThan, 20) | PT15M / PT5M | 2 | none | service team |
| [failed-jobs](#failed-jobs) | `kql/alert_recording_failed_jobs.kql` | `failed_pct` (Maximum, GreaterThan, 10). `min_jobs` 5 | PT1H / PT15M | 2 | `source` | service team |
| [speech-timeouts-throttling](#speech-timeouts-throttling) | `kql/alert_recording_speech_timeouts_throttling.kql` | `failures` (Total, GreaterThan, 5) | PT30M / PT10M | 2 | `error_code` | service team |
| [speech-connection-failures](#speech-connection-failures) | `kql/alert_recording_speech_connection_failures.kql` | `failures` (Total, GreaterThan, 5) | PT30M / PT10M | 2 | `error_code` | service team |
| [storage-failed](#storage-failed) | `kql/alert_recording_storage_failed.kql` | `failures` (Total, GreaterThan, 0) | PT15M / PT5M | 2 | `operation`, `error_code` | service team |
| [upload-failures](#upload-failures) | `kql/alert_recording_upload_failures.kql` | `failures` (Total, GreaterThan, 10) | PT1H / PT15M | 3 | `outcome`, `error_code` | service team |
| [availability-test](#availability-test) | none: a metric alert on each availability test | failed locations (GreaterThanOrEqual, 2 of 5) | PT5M / PT1M | dictation 1, recording 0 | the test | service team |

Notes on the table:

- **Dimensions on the dictation count alerts.** The heritage dictation rules for session,
  submission, document and upload-job failures had no dimensions, so the threshold applied to the
  total of all codes. The merged queries return `error_code` (and `source` for documents). Adding
  them as dimensions would apply the threshold per code. Whether to do that is to be agreed; until
  then, keep the heritage behaviour (no dimensions).
- **Auto-resolve.** Every alert resolves itself when the condition clears, except the real
  ownership-violation alert in the heritage recording rules, which stayed open until someone
  closed it. The dictation rule resolved itself. Which behaviour to keep is to be agreed with
  Security.
- **Area on the service alerts.** `area` is a new dimension on service-unavailable, server-errors
  and ownership-violation. It is empty for shared paths (`/health`, `/api/telemetry`,
  `/api/openapi.json`) and for transcribe-web's own requests.
- The dictation heritage rules called availability "endpoint-availability" and the 5xx rule
  "server-error-rate". The names above follow the merged files.
- **Terraform defaults.** Where a value is "to be agreed", `alert_thresholds` in `variables.tf`
  defaults to the dictation value: availability 90% with `min_requests` 20, 5xx 2% over PT30M,
  ownership violations over PT10M, `min_baseline_hours` 2, `min_baseline_tokens` 200,000, AI spikes
  every PT6H, and Sev 1 for the critical alerts. Every rule resolves itself. Change a value by
  setting `alert_thresholds` once it is agreed.

## Common first checks on AKS

Every runbook below starts from these. They replace the heritage App Service checks: there is no
App Service, no Easy Auth and no Sentry on CNP.

1. **Run the alert's query in Logs.** Open the environment's Application Insights resource, then
   Logs. Paste the `.kql` file (prepend its `let` parameter if it has one) and set the time range
   to the alert window. Then run the related panel queries named in the runbook; most are also
   panels of the environment's workbooks (`workbooks.tf`).
2. **Pods.** `kubectl -n transcribe get pods`. Look for restarts, `CrashLoopBackOff`, `Pending`,
   `ImagePullBackOff` or `OOMKilled` (`kubectl -n transcribe describe pod <pod>`).
   `kubectl -n transcribe get deploy` lists the API and worker deployments.
3. **Logs.** `kubectl -n transcribe logs <pod> --since=30m` for a transcribe-api pod or the
   transcribe-api-worker pod; add `--previous` after a restart. The same logs are in
   Application Insights: `traces | where cloud_RoleName == "transcribe-api-worker"` (or
   `"transcribe-api"`). Exceptions: `kql/service_exceptions_by_type.kql`.
4. **Flux.** `kubectl -n transcribe get helmreleases` (or `flux get helmreleases -n transcribe`).
   A release that is not `Ready`, or a recent upgrade, points at a deployment. To roll back,
   revert the release's change in cnp-flux-config.
5. **Dependencies.** `GET /api/health/dependencies` gives the live state of the database, storage
   and Speech. History: `kql/service_dependency_up.kql` and
   `kql/service_dependency_health_changes.kql` (`hmcts.error.code`: `dependency.timeout`,
   `dependency.auth_failed`, `dependency.unreachable`, `dependency.error`). Also check Azure
   Service Health for the region.

Where things live:

| Thing | Where |
|---|---|
| API pods (`cloud_RoleName` `transcribe-api`) | AKS, namespace `transcribe`, deployed by Flux from cnp-flux-config. One or more replicas (`cloud_RoleInstance`) |
| Worker pod (`transcribe-api-worker`): the dictation upload poller and the recording batch-job poller | Same namespace and image. Exactly one replica, only on the active cron cluster (aat-00 in AAT; Flux sets `global.activeCronCluster`). Which cluster is active in other environments is a PlatOps question |
| transcribe-web (Next.js) | AKS, its own release |
| App Insights, Key Vault `transcribe-<env>`, storage, Speech, OpenAI | this repository (transcribe-shared-infrastructure) |
| PostgreSQL flexible server | transcribe-api `infrastructure/` |

Who has `kubectl` access in each environment (and how prod access is granted) is a PlatOps
question. If you have no access, ask the platform on-call to run the checks.

Escalation, until PlatOps confirms the teams and the route:

1. The service team investigates.
2. If the cause is an Azure service (Speech, Storage, PostgreSQL, OpenAI) or the platform (AKS,
   Flux, network, Key Vault), the service team contacts PlatOps, who may raise an Azure support
   case.
3. If personal data may have been exposed, raise a security incident with Security.

## Service alerts

### service-unavailable

**Means.** More than the threshold share of real requests to a service (`cloud_RoleName`) and
area got a 5xx, or failed with no status, in 15 minutes. Health and version probes and synthetic
traffic are left out; 4xx count as available. `min_requests` stops one failed request out of two
at night from paging. Users probably cannot use that area.

**First checks.**
1. [Common first checks](#common-first-checks-on-aks). Which service and which area?
2. `kql/service_server_error_rate.kql` and `kql/service_exceptions_by_type.kql` for the window.
3. `kql/service_dependency_up.kql`: a database or storage outage shows as 5xx (see
   [dependency-down](#dependency-down)).
4. Pods: are the API pods running and ready? Did a Flux upgrade start at the same time?

**Likely causes and fixes.**
- A bad release: roll back in cnp-flux-config.
- Pods crashing or not ready (secrets not mounted from Key Vault, a failed migration at startup,
  out of memory): fix the cause, or roll back.
- A dependency down: handle [dependency-down](#dependency-down) first.
- Ingress or network problems on the platform: PlatOps.

### server-errors

**Means.** The 5xx rate of a service and area is above the threshold, but not yet at
"unavailable". The service is degraded.

**First checks.** `kql/service_server_error_rate.kql` and `kql/service_exceptions_by_type.kql`.
In Logs, find which operations fail: `requests | where toint(resultCode) >= 500 | summarize
count() by name, cloud_RoleName`. Then the [common first checks](#common-first-checks-on-aks).

**Likely causes and fixes.** A recent release (roll back), one failing dependency (see its alert),
or one code path raising an unhandled exception (raise a defect). If it gets worse, it becomes
[service-unavailable](#service-unavailable).

### dependency-down

**Means.** For the whole window, every health check of PostgreSQL (`database`) or Blob Storage
(`storage`) failed on every API instance (`service.dependency.up` max = 0). Both areas need both.
Uploads, dictation submissions, autosave, job creation and saving transcripts fail while it lasts.
Azure Speech is not paged here: its checks run at most every 5 minutes, and its failures have
their own alerts.

**First checks.**
1. `kql/service_dependency_health_changes.kql`: the `error_code` says how the check fails.
2. `GET /api/health/dependencies`.
3. The PostgreSQL flexible server or the storage account in the portal: state, health blade,
   Azure Service Health.

**Likely causes and fixes.**
- `dependency.auth_failed`: the pods' workload identity, a role assignment, or a secret in Key
  Vault `transcribe-<env>` changed or expired. Check the role assignments and the secrets.
- `dependency.unreachable`: private endpoint, DNS or network change. PlatOps.
- `dependency.timeout`: the server is overloaded or restarting. Check its metrics.
- The server was stopped or is in maintenance: start it, or wait for the maintenance to end.

No data at all means the API is down or the checker is not running: that is
[service-unavailable](#service-unavailable), not this alert.

### ownership-violation

**Means.** Someone reached, or tried to reach, a record they do not own, in either area. The
dimensions say what:

- `area`: `dictation` or `recording` (the route's area).
- `outcome`:
  - `blocked`: the authorisation check refused the request; the caller got the usual 404 or 422.
    Causes: someone probing IDs by hand, a link shared between colleagues, a stale link, or a
    client bug that sends the wrong ID.
  - `detected`: authorisation let the request through and the post-authorisation assertion
    caught it. The caller still got a 404, but this is an authorisation defect that should never
    happen. **Treat it as a potential data breach.**
- `resource_type`: dictation `transcription`, `minute_version`, `transcription_job`, `document`,
  `audio`, `draft`; recording `job`, `transcript`, `audio`, `upload`.
- `action`: `read`, `write`, `delete`, `reassign` (a dictation save that would move a record to
  another owner), `submit` (a recording job naming another user's upload).

The event carries no user ID, owner ID, email, record ID, file name or content. Investigators find
who and which record through the request ID, as below.

**First checks.** [Investigating an ownership violation](#investigating-an-ownership-violation).
Then: how many, and how fast? Many targets from one caller suggests enumeration. For `detected`,
find the release that introduced the defect and assess what the caller could have received.

**Escalation.** Security owns this alert. For `detected`, or a pattern of `blocked` attempts,
Security raises a security incident, the service team fixes the defect, and the data protection
process decides whether personal data was exposed. For repeated `blocked` events from one user,
consider suspending their access.

#### Investigating an ownership violation

This query is for investigators. It is not an alert query and is not bound by the alert column
rules: it returns request IDs and journey IDs, which are system-generated UUIDs, never names or
case data. Run it in Logs on the environment's Application Insights resource, with the time
range set to the alert window (widen it a little either side).

```kusto
customEvents
| where name == "security.ownership_violation"
| where tostring(customDimensions["security.outcome"]) != "test"
| project timestamp,
    area = tostring(customDimensions["hmcts.area"]),
    outcome = tostring(customDimensions["security.outcome"]),
    resource_type = tostring(customDimensions["security.resource_type"]),
    action = tostring(customDimensions["security.action"]),
    request_id = tostring(customDimensions["hmcts.request.id"]),
    journey_type = tostring(customDimensions["hmcts.journey.type"]),
    journey_id = tostring(customDimensions["hmcts.journey.id"]),
    cloud_RoleName, cloud_RoleInstance
| order by timestamp desc
```

- `request_id` is the request's `hmcts.request.id`. Its request:
  `requests | where tostring(customDimensions["hmcts.request.id"]) == "<id>"`. The API's log line
  for a blocked check is `UNAUTHORISED_ACCESS_ATTEMPT` in `traces` with the same request.
- `journey_id` is the current journey or the target's (for recording, the target job or upload).

Then find who and which record in the audit log (DIAAT-286). The same call that records the event
writes an audit row, with the actor and record IDs, to `audit_log` in the transcribe-api database
(see transcribe-api `src/transcribe_api/domain/audit.py`). Only authorised staff may query it; how
they reach the prod database is a PlatOps question.

```sql
SELECT timestamp, event_type, outcome, user_id, object_type, object_id, request_id, detail
FROM audit_log
WHERE request_id IN ('<request_id 1>', '<request_id 2>')
ORDER BY timestamp;
```

- An ownership refusal is an `ACCESS_DENIED` row with `outcome` `denied`.
- `user_id` is the actor's internal user UUID (`user.id`); the users table maps it to a person.
- `object_type` and `object_id` are the target record's type and UUID. The record's owner is on
  that record in the database.
- `detail` holds controlled values only (how and why it was refused).

Audit writes fail open: a failed write records `audit.write_failed` and the request carries on. If
a request ID has no audit row, search for `audit.write_failed` with the same `hmcts.request.id`
and use the `traces` and `requests` rows instead.

Record the decision and the IDs in the incident, never the content of any record.

### ownership-violation-test

**Means.** The controlled test of the Security route, not a real violation. Only
`POST /api/security/alert-test` emits it (one endpoint for both areas, SystemAdministrator only).
The endpoint answers 404 unless `SECURITY_ALERT_TEST_TRIGGER_ENABLED=true` **and** `ENVIRONMENT`
is `local` or `test` (transcribe-api `SECURITY_ALERT_TEST_ENVIRONMENTS`). So it cannot run in any
deployed CNP environment (preview, aat, perftest, ithc, demo, prod). The rule is Sev 4 and its
name starts with `[TEST]`.

**Action.** Confirm it arrived where Security expects it, then tell whoever is running the test.
If nobody is running a test, tell the service team: in a deployed environment it should be
impossible, so something has changed.

### ai-usage-spike

**Means.** The audio hours sent to Azure Speech for a feature in the last 24 hours are more than
the threshold times those of the 24 hours before (or `min_baseline_hours`, whichever is larger).
Features: `upload_transcription` (dictation uploads, fast mode), `batch_transcription` (recording
jobs) and `dictation` (live dictation, the browser-reported Speech session length, an estimate).
This is usage, not cost: nothing is broken for users, but the bill rises with it.

The baseline is the previous day, not a 7-day average, because Azure caps a log alert's query
range at 2 days (window P2D). The 7-day view is `kql/ai_usage_trend.kql`.

**First checks.**
1. `kql/ai_usage_trend.kql` over 30 days: a one-day peak or a new level?
2. `kql/ai_audio_hours_daily.kql`: which feature and mode?
3. For `batch_transcription`: `kql/recording_ai_hearing_share.kql` (one hearing or upload taking
   most of the hours?), `kql/recording_workload_jobs_per_day.kql` (more jobs, or longer ones?) and
   `kql/ai_batch_duration_source.kql` (a rise in `estimate` means Azure's results stopped carrying
   the duration).
4. For `upload_transcription`: `kql/dictation_workload_upload_jobs.kql`.
5. For `dictation`: `kql/dictation_workload_hours.kql` and
   `kql/dictation_workload_active_sessions.kql` (a session left running?).

**Likely causes and fixes.** A backlog uploaded at once or the first working day after a quiet
period (expected); the same audio submitted again and again, a client looping, or a job processed
twice (a fault: fix it and tell PlatOps about the extra cost). Sustained genuine growth goes to
the product lead and PlatOps (budget).

### ai-token-spike

**Means.** LLM tokens for a feature (`hmcts.ai.feature`: minutes, titles, documents, recording
post-processing, whatever each call site names) in the last 24 hours are more than the threshold
times those of the 24 hours before (or `min_baseline_tokens`, whichever is larger). All models,
input and output. Usage, never cost.

**First checks.**
1. `kql/ai_usage_trend.kql` (`llm_tokens`) and `kql/ai_tokens_daily.kql`: which feature, model
   and token type?
2. `kql/ai_fallback_rate.kql` and `kql/ai_errors_by_type.kql`: a rise in fallbacks or errors
   points at a provider (every attempt counts, so a fallback storm multiplies calls).
3. The worker logs (`transcribe-api-worker`) for repeated minutes or title generation on the
   same job.

**Likely causes and fixes.** A retry loop or a job reprocessed, a fallback storm (calls going to
Grok or GPT-4o after Gemini fails), very long uploads, or genuine growth. Fix a loop and tell
PlatOps about the cost; a provider problem goes to PlatOps or the provider.

### availability-test

A metric alert per standard availability test (`availability-tests.tf`), not a query: Sev 1 when a
test fails from `availability_test_failed_locations` (2) or more of its 5 locations in 5 minutes.
The heritage dictation rule used Sev 1 over 5 minutes, the recording rule Sev 0 over 15 minutes;
to be agreed. No test exists yet: which CNP URLs Azure's public test agents can reach is a PlatOps
question (`observability_availability_test_urls`, empty).

**Means.** The service cannot be reached from outside, or answers its health URL with something
other than 200 (a redirect to sign-in is a failure).

**First checks.** `kql/service_availability_synthetic.kql`, then
[service-unavailable](#service-unavailable) and the [common first checks](#common-first-checks-on-aks).
If only the test fails and real requests succeed, suspect the ingress, DNS or the certificate
(the test fails 7 days before it expires).

## Dictation alerts

Most dictation measures come from browser events relayed by `POST /api/telemetry`. They have no
`hmcts.area`; the queries take the area from the journey type (`dictation.session`). A browser
that closes before it sends its batch loses its events, so counts are a lower bound.

### dictation-session-failures

**Means.** Live dictation sessions ended in error (`dictation.session_ended` with outcome
`error`), by `error_code`: `speech.unhealthy` (Azure Speech kept dropping), `autosave.failed`
(the draft was not being saved) or `submission.failed`. `dictation.no_transcript` (nothing
captured) is a `failure`, often the user, and is left out.

**First checks.** `kql/dictation_session_failures.kql` and `kql/dictation_session_outcomes.kql`.
The matching alert usually points at the cause: [speech-failures](#speech-failures),
[speech-unhealthy](#speech-unhealthy), [autosave-stalled](#autosave-stalled) or
[submission-failures](#submission-failures).

**Likely causes and fixes.** See the matching alert. Azure Speech problems go to PlatOps; the rest
to the service team.

### speech-failures

**Means.** Live dictation sessions hit Azure Speech failures, per Speech error code
(`speech.canceled` with reason `Error` or `StartFailed`, and `speech.unhealthy`).
`failures` counts distinct sessions per code.
- `ConnectionFailure`: network or Speech service trouble.
- `TooManyRequests`: throttling, the concurrency or quota limit was reached.
- `ServiceTimeout`: Speech timed out.
- `AuthenticationFailure`: a token problem.
- Empty: `StartFailed` carries no Speech code (for example the token request failed).

**First checks.** `kql/dictation_speech_cancellations.kql`, `kql/dictation_latency.kql` (start
latency). The token stage: `kql/service_stage_duration_metric.kql` (stage `speech_token`) and the
API logs for `GET /api/get-speech-token`. The Speech resource's metrics and quota in the portal,
and `speech` in `kql/service_dependency_up.kql`.

**Likely causes and fixes.** Throttling: ask PlatOps for a quota or tier increase. Token failures:
the API's managed identity or its role on the Speech resource (`AZURE_SPEECH_RESOURCE_ID`). A
regional outage: PlatOps and Azure support.

### speech-unhealthy

**Means.** Live dictation sessions whose Azure Speech sessions kept collapsing
(`speech.unhealthy`), whatever the error code. It fails the dictation session with
`speech.unhealthy`. New in the merged module: it replaces the browser Sentry alert on this event.
It overlaps [speech-failures](#speech-failures), which also counts this event per code; this one
fires even when the codes are spread out. `failed_pct` (share of active sessions) is context only.

**First checks and fixes.** As [speech-failures](#speech-failures). Also check whether the users
share a network (a court building's network can drop long-lived connections).

### no-speech

**Means.** Live dictation sessions warned that no speech was captured
(`dictation.no_speech_warning`): recording ran with no text. New in the merged module: it replaces
the browser Sentry alert on this event. One user's muted or wrong microphone is often the cause, so
the provisional threshold (5 sessions) is higher than speech-unhealthy's. `failed_pct` is context
only.

**First checks.** `kql/dictation_speech_cancellations.kql` and `kql/dictation_latency.kql` for the
same window: is Speech returning errors, or is it silent? Check whether the sessions are from one
place or device type, and whether a transcribe-web release changed microphone handling (Flux).

**Likely causes and fixes.** Several sessions at once point at Speech returning nothing (PlatOps,
Azure support) or a transcribe-web defect (roll back). Isolated cases are user equipment: service
support.

### autosave-stalled

**Means.** In more than 10% of active dictation sessions (with at least 5 active sessions),
autosave has stopped working: consecutive failed saves (`live_draft.autosave_stalled`), sign-in
expiry (`auth`) excluded. If the browser closes, users may lose dictated text.

**First checks.** `kql/dictation_autosave_failures.kql`, by `failure_kind`:
- `server`: failures of `PUT /api/live-draft` on transcribe-api. Check
  `kql/service_server_error_rate.kql`, the API logs and the database
  ([dependency-down](#dependency-down)).
- `network`: the users' network or the ingress. Check whether the sessions share a site.

**Likely causes and fixes.** Database trouble (handle dependency-down first), an API release
(roll back), or a network problem (PlatOps).

### submission-failures

**Means.** Dictation submissions (`POST /api/live-transcription/submission`) failed on the server
side (`submission.failed` with outcome `error`). The decision document was not generated, stored
or linked. Codes include `storage.write_failed` and `document.store_failed` (storage and database
failures); a template failure shows as `unhandled.<Type>`. The transcript is still in the user's
draft.

**First checks.** `kql/dictation_submissions.kql`, `kql/dictation_document_generation.kql`,
`kql/service_dependency_up.kql` (storage, database), `kql/service_exceptions_by_type.kql`.

**Likely causes and fixes.** Storage or database failures (PlatOps if the resource is unhealthy;
otherwise identity and roles), or a template or code defect after a release (roll back). Tell
affected users to retry once the cause is fixed.

### document-generation-failures

**Means.** Document generation failed (`document_generation.failed` with outcome `error`). `source`
is the journey: `dictation.submission` (the decision document, transcribe-api: codes
`document.render_failed`, `document.store_failed`) or `dictation.transcription` (the uploaded-audio
document, transcribe-api-worker: `document.not_generated`).

**First checks.** `kql/dictation_document_generation.kql` and
`kql/dictation_document_template_versions.kql`: did a new template version start failing?
`kql/service_exceptions_by_type.kql`. For `dictation.transcription`, the worker logs.

**Likely causes and fixes.** A new template version (roll back the template or the release),
storage failures (see dependency-down), or a code defect.

### upload-job-failures

**Means.** Uploaded-audio jobs (journey `dictation.transcription`, run by the dictation upload
poller in transcribe-api-worker) ended in error. `error_code`:
- `transcription.failed`: the Azure Speech request failed, timed out or was throttled;
- `minutes_generation.failed`, `minutes.failed`: the LLM failed;
- `document.not_generated`, `title.failed`, `notification.email_failed`: a later part degraded.

A rejected file (`failure`) is left out.

**First checks.** `kql/dictation_workload_upload_jobs.kql`, `kql/service_dependency_up.kql`
(speech, storage), and for minutes `kql/ai_errors_by_type.kql` and `kql/ai_fallback_rate.kql`.
Worker pod and logs (`transcribe-api-worker`).

**Likely causes and fixes.** Speech throttling or outage (PlatOps), LLM provider errors (PlatOps or
the provider), the worker restarting mid-job (`OOMKilled`: the worker's memory limit is 2 GiB), or
email delivery failures.

### upload-jobs-stuck

**Means.** An uploaded-audio job that started in the last 6 hours has not finished after the
threshold (120 minutes). `stuck` is the number of unfinished jobs, `oldest_waiting_min` the age of
the oldest. It may still be running (a very long file), or it was lost (the worker restarted or
crashed mid-job). Jobs waiting for the poller (uploaded, not picked up) are not visible: there is
no queue metric for dictation uploads.

**First checks.**
1. `kql/dictation_workload_active_jobs.kql`.
2. The worker pod: `kubectl -n transcribe get pods` on the active cron cluster. A restart around
   the job's start time (`--previous` logs) means it was lost.
3. To find the journey ID, run the query without its final `| project` (in Logs, not in the rule).

**Likely causes and fixes.** A lost job needs its file re-queued (the service team). If the worker
is missing (not on the active cron cluster, or the HelmRelease failed), fix the release with
PlatOps.

## Recording alerts

The recording metrics (`transcription.*`) come from transcribe-api-worker and carry no area: they
are recording's own. The recording events keep `hmcts.area == "recording"`.

### poller-stalled

**Means.** The recording batch-job polling loop has not completed a poll for more than 600 seconds
(`transcription.poller.last_success_age`, freshest replica). Jobs are not submitted, polled or
finished: the queue has stopped. It polls every `BATCH_POLL_INTERVAL_SECONDS` (30 s). No points at
all means no alert: if the worker sends nothing, the poller-stalled query sees nothing.

**First checks.**
1. `kql/recording_poller_heartbeat.kql` and `kql/recording_queue_jobs.kql`.
2. If the database is down, every poll fails: see [dependency-down](#dependency-down).
3. The worker pod and its logs. The worker has exactly one replica, on the active cron cluster
   only, so check that cluster.
4. `kql/service_exceptions_by_type.kql` with `cloud_RoleName == "transcribe-api-worker"`.

**Likely causes and fixes.** The database is unreachable (fix that first); the worker pod is
crash-looping or missing (Flux, the active cron cluster); the loop is wedged while the process
runs (restart the pod: `kubectl -n transcribe delete pod <worker pod>`, and the deployment starts
a new one). If a restart does not help, PlatOps.

### stuck-jobs

**Means.** At least one recording job has waited longer than `JOB_STUCK_WAITING_SECONDS` (30 min)
without Azure Speech starting it (`state` `waiting`), or has run longer than
`JOB_STUCK_RUNNING_SECONDS` (3 h) (`state` `running`). Observation only: nothing is retried or
failed automatically. A stuck job stays in `transcription.jobs.stuck` until it finishes or is
cleared, so the alert keeps firing until then. That is intended: such a job needs a person.

**First checks.**
1. `kql/recording_stuck_jobs.kql`: job ID, state and Azure Speech job ID
   (`hmcts.dependency.ref`).
2. `waiting`: is the poller alive ([poller-stalled](#poller-stalled))? Is Speech throttling
   ([speech-timeouts-throttling](#speech-timeouts-throttling))?
3. `running`: check the Azure Speech job by its ID, and Azure Service Health for Speech.

**Likely causes and fixes.** A backed-up or stopped poller, Speech throttling or a hung Speech job.
A job that can never finish (no Speech job ID, or Speech has lost it) has no documented manual
clear-up yet: escalate to the service team to clear it.

### oldest-waiting

**Means.** The oldest recording job not yet started by Azure Speech has waited more than 20
minutes. Jobs already reported stuck are left out of the gauge, so one job that never finishes
cannot hold this alert on. It is set below `JOB_STUCK_WAITING_SECONDS` (30 min) to warn before
jobs are reported stuck: the queue is backing up.

**First checks.** `kql/recording_queue_oldest_waiting.kql`, `kql/recording_queue_jobs.kql`,
`kql/recording_workload_jobs_per_day.kql` (a volume spike or a slowdown?),
`kql/recording_speech_throttled.kql`, `kql/recording_retries.kql`,
`kql/recording_speech_utilisation.kql` (only if `SPEECH_CONCURRENT_JOBS_LIMIT` is set).

**Likely causes and fixes.** A burst of uploads (wait, or raise the Speech quota with PlatOps),
Speech throttling, or a slow poller.

### failed-jobs

**Means.** More than 10% of the recording jobs that finished in the window ended in error from
one `source` (at least `min_jobs` finished): `application` (our code, database, blob storage),
`dependency` (Azure Speech) or `queue` (never processed). Client failures (outcome `failure`, the
caller's audio or request was rejected) are left out.

**First checks.** `kql/recording_failures_by_source.kql`, `kql/recording_failed_jobs.kql`. For
`dependency`: `kql/recording_speech_error_codes.kql`. For `application`:
`kql/recording_stage_failures.kql`, `kql/recording_storage_failures.kql`,
`kql/service_exceptions_by_type.kql`.

**Likely causes and fixes.** Azure Speech rejecting or failing jobs (PlatOps, Azure support), a
storage or database fault (see [storage-failed](#storage-failed)), or a code defect after a
release (roll back).

### speech-timeouts-throttling

**Means.** Azure Speech batch calls timed out (`speech.timeout`) or were refused with HTTP 429
(`speech.throttled`). Calls, not jobs: retries count again. Jobs are retried, but slow down.

**First checks.** `kql/recording_speech_calls.kql`, `kql/recording_speech_throttled.kql`,
`kql/recording_retries.kql`, `kql/recording_speech_utilisation.kql`; the Speech resource's metrics
and quota in the portal. Live dictation uses the same Speech resource: check
`kql/dictation_speech_cancellations.kql` for `TooManyRequests` too.

**Likely causes and fixes.** Load near the resource's limits (PlatOps for a quota increase), or a
regional problem (Azure Service Health).

### speech-connection-failures

**Means.** Azure Speech batch calls failed to connect (`speech.connect_error`), broke off
(`speech.transport_error`) or got a 5xx (`speech.http_5xx`). Network or service problems, not our
requests.

**First checks.** `kql/recording_speech_failures.kql` (by operation and code), `speech` in
`kql/service_dependency_up.kql` and `kql/service_dependency_health_changes.kql`, Azure Service
Health, and any private endpoint, DNS or egress change on the cluster.

**Likely causes and fixes.** Network or private endpoint changes (PlatOps), or a Speech outage
(Azure support through PlatOps).

### storage-failed

**Means.** A database or blob write in the recording pipeline failed. `operation`:
`transcript.save`, `job.mark_failed`, `job.mark_needs_cleanup`, `blob.mark_failed` (in the worker,
after Azure Speech), or `upload.blob_write` (the upload's blob write, `POST /api/v1/uploads`).
`error_code`: `storage.db_unavailable`, `storage.db_rejected`, `storage.db_failed`,
`storage.blob_failed`, `storage.write_failed`. A failed `transcript.save` is retried on the next
poll.

**First checks.** `kql/recording_storage_failures.kql`, `kql/service_dependency_up.kql`.

**Likely causes and fixes.** The database or storage is unreachable (see
[dependency-down](#dependency-down)); `storage.db_rejected` usually means a code defect (a
constraint or bad data: raise a defect); an identity or role change on the storage account.

### upload-failures

**Means.** More than 10 recording uploads failed with the same outcome and code in an hour:
- `error`: server side, for example `storage.write_failed` or `unhandled.<Type>`;
- `failure`: the file was rejected: `upload.unsupported_format`, `upload.too_large`,
  `upload.undecodable`, `http.4xx`.

**First checks.** `kql/recording_upload_outcomes.kql`, `kql/recording_upload_size.kql`. For
errors: [storage-failed](#storage-failed) and `kql/service_exceptions_by_type.kql`.

**Likely causes and fixes.** Errors: storage or a defect. Rejections: a new recorder or file format
in use, which is a product question, not an outage.

## Not covered by a query alert

- **Synthetic availability.** A metric alert, not a query: see
  [availability-test](#availability-test).
- **The API sends no telemetry at all.** If transcribe-api is fully down, the request-based alerts
  see nothing. Only the availability tests or a platform probe can show it. Whether Dynatrace probes
  the service is a PlatOps question.
- **Jobs waiting for the dictation upload poller.** No queue metric for dictation uploads.
- **Azure Speech timeouts and throttling for dictation uploads** are not split by type: they show
  as `transcription.failed` in [upload-job-failures](#upload-job-failures).
- **LLM provider health.** No cheap check. Minutes failures show in upload-job-failures; LLM errors
  and fallbacks in `kql/ai_errors_by_type.kql` and `kql/ai_fallback_rate.kql`.
- **Cost.** The spike alerts read usage, not cost. Budget alerts on actual cost belong to Azure Cost
  Management and GCP budgets (PlatOps).

## Controlled tests (AC2)

Run these once in each environment after the alerts are first enabled, again after any change to
routing or receivers. For each, record the alert, the time it fired, who received it and when, in
DIAAT-287 (see `VALIDATION.md`). The alert must arrive at its route, and nowhere else.

`alert_threshold_overrides` (alert name => threshold) sets a temporary threshold that a healthy
system meets, so each critical rule fires through its real action group without breaking
anything. A key that is not an alert (or `availability-test`) fails the plan. Remove each override
after its test.

| Critical alert | Controlled test | Expected |
|---|---|---|
| service-unavailable | Override the threshold to 100.1 and make at least `min_requests` requests in 15 minutes | A notification to the service team's route, with `cloud_RoleName` and `area` |
| dependency-down | Override the threshold to 2 (`up` is always below 2) | One notification per dependency (`database`, `storage`) |
| poller-stalled | Override the threshold to -1 (the age is always above -1) | A notification to the service team's route |
| ownership-violation (real rule) | With Security told in advance: as test user B, open a recording job of test user A (`/api/v1/jobs/<A's job ID>`) through transcribe-web. B gets a 404 | A notification to Security with `area = recording`, `outcome = blocked`, `resource_type = transcript`, `action = read` |
| ownership-violation-test | `POST /api/security/alert-test` cannot run on CNP (see [ownership-violation-test](#ownership-violation-test)). Instead create a temporary log alert rule with the query `print outcome = "test", resource_type = "transcription", violations = 1` (threshold > 0, routed to Security), let it fire once, then delete it | A `[TEST]` notification at Security only |

Also use "Test action group" in the portal on each action group: this proves the receivers, not
the rules. If routing goes through Dynatrace or a Slack action group, the tests are the same but
the receiving end changes; PlatOps to confirm.

## Revising thresholds

Once there are a few weeks of data:

1. For each alert, run its query and its panel queries over 30 days. Look at the normal range and
   the peaks.
2. Set each threshold above normal peaks, so that an alert means action is needed. Record the
   reasoning in the PR that changes it.
3. Review alerts that fired without needing action: raise the threshold or lengthen the window.

Check in particular:
- the availability threshold against the availability target (99% or 99.5% a month, still to be
  confirmed, DIAAT-277);
- `oldest_waiting_min` against the agreed turnaround;
- the Speech thresholds against the Speech resource's quota, which both areas now share;
- the spike floors (`min_baseline_hours`, `min_baseline_tokens`) against a normal quiet day
  (`kql/ai_usage_trend.kql` over 30 days).
