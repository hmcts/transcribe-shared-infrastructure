# Validation (DIAAT-287)

How to prove, on CNP, that the telemetry, measures and alerts of transcribe-api work for both areas
(dictation and recording) in realistic success and failure scenarios, and how to record the
evidence. Epic: DIAAT-205. The measures are in [MEASURES.md](MEASURES.md) and the alerts in
[ALERTS.md](ALERTS.md).

| Acceptance criterion | How it is met |
|---|---|
| AC1: QA, the Technical Lead, Product and service support agree that the MVP is usable | [Sign-off](#sign-off-ac1), after the deployed run |
| AC2: a dictation session and a recording batch job have both been traced end to end | Automated, then in AAT: [D1](#dictation-scenarios) and [R1](#recording-scenarios) with the [trace queries](#tracing-end-to-end-ac2) |
| AC3: no prohibited content in the approved test sample | The [automated scan](#1-the-automated-scan) (evidence JSON from the build), then the [deployed sample scan](#4-the-deployed-sample-scan-ac3) (`validation/prohibited_content_scan.kql`) over the AAT test window |

The procedure has five parts: the automated scan on every build, preparation, the scenarios in AAT
for each area, the deployed sample scan, then evidence and sign-off.

> **What is not deployed yet.** The workbooks, alert rules and availability tests are a later
> Terraform PR (PlatOps must first allow those resource types). Until then, check each panel by
> running its query file in Logs, and check each alert by running its `kql/alert_*.kql` file over
> the scenario's window. Alert delivery is tested once the rules exist, with the controlled tests
> in [ALERTS.md](ALERTS.md#controlled-tests-ac2).

## 1. The automated scan

transcribe-api's unit tests drive the real API router (and, for recording, the real polling loop)
with production's middleware, instrumentation and exception handlers. Only Azure Speech, Blob
Storage and the database are faked. They run on every build of transcribe-api.

| Area | Tests (transcribe-api) | Scenarios |
|---|---|---|
| Dictation | `tests/unit/dictation/unit/validation/test_e2e_dictation_journey.py`, `test_pii_scan.py`; seeded values in `pii_scan.py` | Success with pause, resume and download; slow Speech start; failed start with an invalid token; failed start with the token service down; autosave failing then tab closed; network lost before any text; document generation failure |
| Recording | `tests/unit/recording/unit/validation/test_e2e_recording_journey.py`, `test_prohibited_content_scan.py`; seeded values in `prohibited_content.py` | Success from upload to audio export; rejected upload (unsupported format, undecodable); Azure Speech fails the job; throttling retried; database failure saving the transcript, recovered on the next poll; stuck job reported once; multi-file hearing |

Everything each scenario exports (span names and attributes, log records, custom events, metric
attributes) is scanned by one engine, `tests/unit/telemetry_scan.py`, for:

- **seeded values:** each area's synthetic case data (names, case references, file names, emails,
  a SAS signature, a bearer token, transcript text). None may appear anywhere;
- **pattern classes:** email, UK case reference (also in file names), SAS `sig=`, bearer token,
  JWT, UK postcode, National Insurance number, whatever the value.

A finding names the seed or pattern and where it was found, never the matched text. A scenario
that exported nothing fails too: an empty scan proves nothing.

**The evidence file.** `tests/unit/conftest.py` deletes any earlier file at the start of the test
session and writes `test-results/telemetry-pii-scan.json` at the end. It holds the check, the
commit, the hmcts-otel version, `result` (`pass` or `fail`; it also fails if the test session
failed), `areas_scanned`, `scenarios_scanned`, `scenarios_failed`, totals, the seeded value labels
(never the values), the patterns and, per scenario, its counts and findings.

**In the pipeline.** `Jenkinsfile_CNP` archives the file after the test stage
(`afterAlways('test')`, `archiveArtifacts ... 'test-results/telemetry-pii-scan.json'`). The
archive step allows an empty result, so a missing file does not fail the build: check that the
artefact is there. Take it from the Jenkins build of the commit deployed to AAT.

**Pass:** `result` is `pass`, `areas_scanned` is `["dictation", "recording"]`, and
`scenarios_failed` is empty.

**The patterns stay in step.** The deployed scan uses transcribe-api's `RE2_PATTERNS` (the patterns
KQL can run) verbatim. `validation/re2-patterns.txt` is the pinned copy, refreshed by
`tests/generate_telemetry_names.py`, and `tests/test_scan_patterns.py` fails if
`validation/prohibited_content_scan.kql` differs from it.

## 2. Before the deployed run

- **Environment:** AAT. Deploy the release candidate through Flux and note the image (commit).
  Scenarios marked **disruptive** break a shared resource or change a setting through
  cnp-flux-config: run them only with PlatOps' agreement, in a window when nobody else uses AAT.
  Whether they may run in AAT at all is a PlatOps question; where they may not, the automated
  test is the evidence.
- **Alerts:** if the rules exist by then, enable them in AAT with real receivers and tell the
  service team and Security that tests are coming. Otherwise, run the alert queries by hand.
- **Access:** Reader on the AAT Application Insights resource (Logs); two test users (A and B) with
  the roles each area needs; a Chromium browser with developer tools (to read `X-Request-Id` and
  to throttle or go offline). For the audit checks, someone authorised to query the AAT database.
- **Synthetic data only.** Enter only the [synthetic case](#the-synthetic-case). Never use a real
  recording or real case details.
- **Run sheet.** Record the start and end of the whole test window in UTC, and for each scenario:
  start and end time, environment, and the system-generated IDs (session ID, request IDs, upload
  ID, job ID, Azure Speech job ID). Run the scenarios one at a time.

### The synthetic case

These are the values the sample scan looks for (`seeded_values` in
`validation/prohibited_content_scan.kql`). Enter nothing else.

**Dictation** (from the heritage dictation plan):

| Field | Value |
|---|---|
| Appellant | `Okonkwo-DIAAT298` |
| Respondent | `HomeOfficeRespondent-DIAAT298` |
| Judge | `HHJ-Blackwood-DIAAT298` |
| Notes | `PrivateJudicialNote-DIAAT298 appeal PA/50123/2024, lives at SW1A 2AA, NI AB 12 34 56 C, contact appellant.okonkwo@example.com` |
| Transcript | Dictate freely, then type `AppellantStatesDIAAT298sentinel` into the transcript |

The case reference, postcode, NI number and email in the notes are caught by the pattern classes,
not by `seeded_values`.

**Recording.** Short audio files of made-up speech, named with made-up case data, as in the
heritage recording plan, for example `PA_99999_2099 Testperson v Home Office.wav`. The case
reference in the name is caught by the `uk_case_reference` pattern. Write down every other
distinctive value you use (for example `Testperson`, and any speaker or party names in the audio)
and add them to `seeded_values` in the Logs editor before running the scan. The file's
`seeded_values` lists the dictation values only; agreeing a fixed set of recording values for it is
an open item.

## 3. Scenarios in AAT

Counts are for the scenario alone, with the time range set to its window. Compare them with the
scenario's `notes` in the evidence JSON where the automated test recorded expected values.
Workbook panels are named by their query file until the workbooks exist.

### Dictation scenarios

Use test user A in a browser with developer tools. Find a session's ID:

```kusto
customEvents
| where timestamp between (datetime(<start>) .. datetime(<end>))
| where name == "dictation.session_requested"
| project timestamp, session = tostring(customDimensions["hmcts.journey.id"])
```

| # | Scenario | Steps | Expected events (browser; server) | Queries: expected | Alert query |
|---|---|---|---|---|---|
| D1 | Success, with pause and resume (AC2) | Record, speak, pause, resume, speak, pause, fill the form with the synthetic case, submit, download the document | `dictation.session_requested`, `speech.token_fetched`, `speech.session_started`, `speech.first_result`, `dictation.paused`, `speech.session_stopped`, `dictation.resumed`, `dictation.resume_first_result`, `dictation.submission_finished`, `dictation.session_ended` (success); `speech_token.*`, `submission.*`, `document_generation.*`, `document.available`, `transcript.available` | `kql/dictation_session_outcomes.kql`: success +1. `kql/dictation_submissions.kql`: server and browser success +1. `kql/dictation_document_generation.kql`: `dictation.submission` success +1. `kql/dictation_latency.kql`: all three measures present | none |
| D2 | Slow start | Developer tools, Network: throttle to Slow 3G (or 3 s latency), then record. Turn throttling off after the first text | As D1, with long `hmcts.duration_ms` on `speech.session_started` and `speech.first_result` | `kql/dictation_latency.kql`, `kql/dictation_latency_metric.kql`: the start p95 and average rise for the hour | none (no latency alert) |
| D3 | Failed start: Speech refuses the token | Developer tools, Sources, Overrides: make `/api/get-speech-token` return an invalid token, then record. Repeat in 3 sessions within 30 minutes | `speech.canceled` (`Error`, `AuthenticationFailure`) per attempt, `speech.unhealthy`, `dictation.session_ended` (failure, `dictation.no_transcript`) | `kql/dictation_speech_cancellations.kql`: `Error AuthenticationFailure`. `kql/dictation_session_outcomes.kql`: failure +1 each | `kql/alert_dictation_speech_failures.kql`: `error_code = AuthenticationFailure`, `failures` 3. `kql/alert_dictation_speech_unhealthy.kql`: `failures` 3. `kql/alert_dictation_session_failures.kql`: no row (no transcript is a failure, not an error) |
| D4 | Interruption: tab closed | Record, speak, close the tab without submitting | `dictation.session_ended` (cancelled, `dictation.not_submitted`, `page_hidden`) | `kql/dictation_session_outcomes.kql`: cancelled +1 | none |
| D5 | Interruption: network lost | Record, speak, developer tools Offline for 2 minutes, close the tab, reopen the app (it sends the stored session end) | `speech.canceled` (`Error`, `ConnectionFailure`), `live_draft.save_failed` (`network`), `live_draft.autosave_stalled`, `dictation.session_ended` (error, `autosave.failed`) | `kql/dictation_autosave_failures.kql`: `save_failed` and `autosave_stalled`, `network`. `kql/dictation_session_failures.kql`: `autosave.failed` +1 | `kql/alert_dictation_autosave_stalled.kql`: a row; the rule fires only with at least 5 active sessions and over 10% stalled. `kql/alert_dictation_session_failures.kql`: `autosave.failed` |
| D6 | Submission or document failure (**disruptive**) | No safe fault switch exists. With PlatOps, during the storage outage of R5 (or a database outage), submit once | `submission.failed` (`storage.write_failed` or an exception type), `dictation.submission_finished` (error, `http.500`) | `kql/dictation_submissions.kql`: failure by code +1 | `kql/alert_dictation_submission_failures.kql`: a row. `document.render_failed` is covered by the automated test only |

The heritage scenario "token service down" (break `AZURE_SPEECH_KEY`) does not apply on CNP: the
API reaches Speech with its managed identity (`AZURE_SPEECH_RESOURCE_ID`), so the token cannot be
broken that way. D3 covers a failed start; the automated test covers the token service.

### Recording scenarios

Upload through transcribe-web, signed in as test user A. Trace one job's events:

```kusto
customEvents
| where tostring(customDimensions["hmcts.journey.id"]) in ("<job id>", "<upload id>")
| project timestamp, name,
    parent = tostring(customDimensions["hmcts.journey.parent_id"]),
    outcome = tostring(customDimensions["hmcts.outcome"]),
    code = tostring(customDimensions["hmcts.error.code"]),
    source = tostring(customDimensions["hmcts.failure.source"]),
    speech_job = tostring(customDimensions["hmcts.dependency.ref"]),
    duration_ms = todouble(customDimensions["hmcts.duration_ms"])
| order by timestamp asc
```

| # | Scenario | Steps | Expected events | Queries: expected | Alert query |
|---|---|---|---|---|---|
| R1 | Success (AC2) | Upload one file (about 2 minutes of speech) and submit it. Wait for completion. Open the transcript and play the audio | Upload journey: `upload.started`, `upload.completed`. Job journey, parent = the upload ID: `job.created`, `speech_submission.*`, `job.queued`, `speech.job_running`, `result_processing.started`, `results_retrieval.*`, `transcript_postprocessing.*`, `transcript_persistence.*`, `transcript.available`, `job.finished` (success), `result_processing.completed`. `job.queue_wait_ms + job.processing_ms <= hmcts.duration_ms` on `job.finished` | `kql/recording_upload_outcomes.kql` success +1; `kql/recording_queue_wait.kql`; `kql/recording_speech_processing.kql`; `kql/recording_transcripts_available.kql` +1; `kql/recording_availability_durations.kql`; `kql/recording_workload_jobs_per_day.kql` created +1, success +1; `kql/recording_workload_audio_hours.kql` | none |
| R2 | Upload rejected | Upload a text file renamed `.mp3` | `upload.started`, `upload.validation_failed`, `upload.failed` (failure, `upload.undecodable`). No job events | `kql/recording_upload_outcomes.kql`: failure `upload.undecodable` +1 | `kql/alert_recording_upload_failures.kql`: a row; the rule needs more than 10 in an hour |
| R3 | Azure Speech fails the job | As a signed-in user, call `POST /api/v1/jobs` with an `audio_url` Azure can reach but not transcribe (a public URL that returns HTML) | `job.queued`, `speech.job_failed`, `job.finished` (error, `speech.job_failed`, source `dependency`, `speech.error_code` such as `InvalidData`). Azure's message is never in telemetry | `kql/recording_failures_by_source.kql` dependency +1; `kql/recording_speech_error_codes.kql`; `kql/recording_failed_jobs.kql` | `kql/alert_recording_failed_jobs.kql`: no firing for one job (`min_jobs` 5) |
| R4 | Throttling (**disruptive**) | Submit 20 or more small jobs at once (a script against the API) to reach the Speech limit. If Azure never returns 429, record "not reproduced at this quota" | `job.retried` (`speech.throttled`, `job.retry.operation`, `speech.retry_after_s`); `job.poll_failed` if the retry is throttled too; every job still ends in `job.finished` | `kql/recording_speech_throttled.kql`, `kql/recording_retries.kql`, `kql/recording_speech_calls.kql` | `kql/alert_recording_speech_timeouts_throttling.kql`: `speech.throttled` |
| R5 | Storage failure (**disruptive**) | PlatOps removes the API's Blob Storage data role for 15 minutes. Upload a file. Restore the role and upload again | `upload.failed` (error, `storage.write_failed`); `dependency.health_changed` storage down, then up. The retry succeeds | `kql/recording_storage_failures.kql` (`upload.blob_write`); `kql/service_dependency_up.kql` storage 0, then 1; `kql/service_dependency_health_changes.kql` | `kql/alert_recording_storage_failed.kql`; `kql/alert_service_dependency_down.kql` if the outage covers the whole 10-minute window |
| R6 | Stuck job (**disruptive**) | Set `JOB_STUCK_RUNNING_SECONDS=60` on the worker (through cnp-flux-config). Submit a file that takes Azure more than a minute. Set it back afterwards | One `job.stuck` (state `running`, source `dependency`) however many polls see it; the job still finishes | `kql/recording_stuck_jobs.kql`: one row with the job and Azure job IDs; `kql/recording_queue_jobs.kql` | `kql/alert_recording_stuck_jobs.kql`: `state = running` |
| R7 | Multi-file hearing | Upload two files as one hearing | Two upload journeys whose parent is the hearing ID; two jobs, each with its own upload as parent; two transcripts, no stitched one | `kql/recording_ai_hearing_share.kql`: one hearing, two jobs | none |
| R8 | Dependency down (**disruptive**) | With a job running in Azure, stop the AAT PostgreSQL flexible server for 15 minutes, then start it | `dependency.health_changed` (database down with its code, then up); polls fail and the heartbeat age grows; after the restart the job finishes once (one `transcript.available`, one `job.finished`) | `kql/service_dependency_up.kql` database 0, then 1; `kql/recording_poller_heartbeat.kql`; `kql/service_dependency_health_changes.kql`; `kql/service_server_error_rate.kql` | `kql/alert_service_dependency_down.kql`: `database`, `up` 0; `kql/alert_recording_poller_stalled.kql` above 600; `kql/alert_service_unavailable.kql` |

Notes:

- **R7 cannot run on CNP yet.** transcribe-web sends no hearing ID (`X-Hearing-Id`) today, so every
  upload is its own hearing. The automated test covers the correlation. Run R7 once the header is
  sent; until then, record "not applicable".
- A database failure while saving a transcript (`transcript_persistence.failed`,
  `storage.db_unavailable`, then success on the next poll) cannot be caused on its own in a
  deployed environment. The automated test covers it; R8 covers a database outage.
- R8 also stops dictation (autosave and submissions fail). Run it in a quiet window.
- **Security.** The ownership-violation scenario is the real-rule controlled test in
  [ALERTS.md](ALERTS.md#controlled-tests-ac2): as test user B, open user A's R1 job
  (`/api/v1/jobs/<job id>`). Expect a 404 for B, and a `security.ownership_violation` event with
  `area` `recording`, `outcome` `blocked`. Then follow the
  [investigator query](ALERTS.md#investigating-an-ownership-violation) to the audit row.
  `POST /api/security/alert-test` answers 404 in every deployed CNP environment, so the `[TEST]`
  route test uses a temporary rule instead (ALERTS.md).

### Tracing end to end (AC2)

**A dictation session (D1).**

1. List everything on the session, in order:

   ```kusto
   let session = "<session id>";
   customEvents
   | where timestamp between (datetime(<start>) .. datetime(<end>))
   | where tostring(customDimensions["hmcts.journey.id"]) == session
       or tostring(customDimensions["hmcts.journey.parent_id"]) == session
   | project timestamp, name, journey = tostring(customDimensions["hmcts.journey.type"]),
       outcome = tostring(customDimensions["hmcts.outcome"]), code = tostring(customDimensions["hmcts.error.code"]),
       request_id = tostring(customDimensions["hmcts.request.id"]),
       transcription_id = tostring(customDimensions["dictation.transcription_id"])
   | order by timestamp asc
   ```

   Expect the browser events, then the submission's events with one `request_id`, ending in
   `transcript.available` with the `transcription_id`.
2. The submission request: `requests | where tostring(customDimensions["hmcts.request.id"]) ==
   "<request_id>"`, and its dependencies by `operation_Id`.
3. The download. Request URLs carry no IDs, so this step uses the audit log (an authorised
   person): `SELECT event_type, outcome, request_id, timestamp FROM audit_log WHERE object_id =
   '<transcription_id>';`. Expect `transcript.export` rows for the download; each `request_id`
   finds its row in `requests`.

**A recording batch job (R1).**

1. The trace query above, with the job and upload IDs: every event in order, the job's parent is
   the upload.
2. The poller's `result_processing` span has a span link to the trace of the `POST /api/v1/jobs`
   request.
3. The audit log for the job ID (an authorised person): `job.submit`, `transcript.view` and
   `audio.export`, each with the `X-Request-Id` of the request that did it.

Capture each result as evidence (IDs only).

### Panel value checks

For each scenario, run its queries with the time range set to its window, and compare with the
expected values above and with the trace query for the same IDs. With the workbooks deployed,
check the panels the same way (hourly or daily bins add scenarios together). Record the query or
panel, the expected value, the value seen and a screenshot with the time range visible. A
difference is a defect in the query or the telemetry, unless it is explained by browser loss
(relayed counts are a lower bound).

For recording, over the whole run window:

| Query | Expected |
|---|---|
| `kql/recording_upload_outcomes.kql` | success = accepted uploads on the run sheet; failure `upload.undecodable` = 1 (R2); error `storage.write_failed` = 1 (R5) |
| `kql/recording_transcripts_available.kql` | One per job that completed, none for R3 |
| `kql/recording_failures_by_source.kql` | dependency = R3 (plus any R4 job that failed); application = 0 |
| `kql/recording_stuck_jobs.kql` | Exactly one row, for the R6 job |
| `kql/recording_workload_jobs_per_day.kql` | created = jobs submitted; finished (all outcomes) = created, once every job has ended |
| `kql/recording_job_duration_metric.kql` | jobs per phase = the number of `job.finished` events for the same jobs |
| `kql/recording_queue_wait.kql`, `kql/recording_speech_processing.kql`, `kql/recording_availability_durations.kql` | For R1, within a minute of the job's own event durations |

### Alert checks

For each scenario with an alert query, run the `kql/alert_*.kql` file over the scenario's window
(prepend its `let` parameter) and record whether the expected row is there. Once the rules exist,
also record for each alert that fires: the alert ID, the time sent and received, that it reached
its route and nowhere else, and that someone from service support followed its runbook section in
ALERTS.md and found the cause (note any step that was missing or wrong).

## 4. The deployed sample scan (AC3)

After all the scenarios have run:

1. Open the AAT Application Insights resource, Logs. Paste `validation/prohibited_content_scan.kql`.
2. Set `window_start` and `window_end` to the test window (UTC). Add the recording run's
   distinctive values to `seeded_values` (see [the synthetic case](#the-synthetic-case)). The time
   picker then shows "Set in query".
3. Run it. It scans every row of `traces`, `customEvents`, `exceptions`, `requests` and
   `dependencies` written in the window (messages, names, URLs, `customDimensions`, exception
   details, dependency data and targets, and `user_AuthenticatedId`) for the seeded values and the
   seven pattern classes. It returns, per table, column and check, the number of matches and up to
   `max_samples` row IDs (`itemId`). Never the matched text.
4. Export the result (Export, CSV).

The heritage recording plan added two checks. Whether they are part of the approved sample is to
be agreed with QA and Security before the run:

- the same scan over the last 7 days (no seeded values needed), to catch content from outside the
  test window;
- a manual review in the test window of 50 random `traces`, 50 random `customEvents` and every
  `exceptions` row, looking for transcript text, file names, names, case references, emails, URLs
  with tokens or blob paths. Record the item IDs reviewed, not the content.

**Pass criteria** (from the file's comment):

- a `(scanned)` row with `matches` > 0 for `traces`, `customEvents` and `requests` (an empty window
  proves nothing); and
- no other rows, with every false positive listed in `cleared_row_ids`. A group's
  `sample_row_ids` holds at most five of its matches, so clearing the samples is not enough:
  every matching row must be reviewed. Triage the samples, add each false positive's `itemId` to
  `cleared_row_ids`, and rerun. Repeat until no row other than `(scanned)` remains; the
  `matches` count of each remaining group shows how many rows are still unreviewed.

**Triage.** For each hit, look at that one row privately:

```kusto
union traces, customEvents, exceptions, requests, dependencies
| where itemId == "<sample row id>"
```

Record the decision, not the content:

- a **false positive** (for example a postcode-like token in a stack trace): record the `itemId`,
  the table, column and check, and the reason, and add the `itemId` to `cleared_row_ids` before
  the next run;
- a **true positive** is a defect: raise it, treat it as a potential security incident (tell
  Security), and it blocks sign-off until fixed and re-scanned.

## 5. Evidence

Attach to DIAAT-287, link DIAAT-287 from the epic DIAAT-205, and add the link to the release's
OAT evidence record (where that is kept is to be confirmed with QA and service support). Name the
files `DIAAT-287_aat_<yyyy-mm-dd>_<item>`. IDs, counts and screenshots only, no content.

- `telemetry-pii-scan.json` from the Jenkins build of the deployed commit, with the build link;
- the run sheet: scenarios, times, environment, IDs, and which disruptive scenarios ran or why not;
- the AC2 trace results for D1 and R1 (event lists, the requests, the audit rows);
- query or panel results with expected and seen values, and screenshots;
- the alert check results, and, once the rules exist, the alert delivery records;
- the `prohibited_content_scan` CSV, with the triage notes for any hits, and the manual review
  record if it is part of the approved sample.

## Sign-off (AC1)

Each role reviews the evidence and the views and decides whether the MVP is usable for them.

| Role | Name | Usable? (yes / no / with conditions) | Conditions or gaps | Date |
|---|---|---|---|---|
| QA | | | | |
| Technical Lead | | | | |
| Product | | | | |
| Service support | | | | |

## Known gaps

- **Render failures are not named on the submission.** A template rendering failure fails the
  submission with the exception type (`unhandled.<Type>`), not `document.render_failed`.
- **Speech outages do not count as session failures.** A session that never starts ends as
  `failure` (`dictation.no_transcript`), not `error`. Only speech-failures and speech-unhealthy see
  it, and `StartFailed` carries no Speech error code.
- **The token request is not on the session journey.** The server's `speech_token` stage has no
  session ID: use the browser's `speech.token_fetched`, or correlate by time.
- **The dictation download is not on any journey.** The session-to-download link goes through
  `audit_log`.
- **No safe fault switch for document generation or storage.** D6 and R5 need PlatOps to break a
  shared resource in AAT.
- **No hearing IDs on CNP yet**, so R7 waits for transcribe-web to send `X-Hearing-Id`.
- **The `[TEST]` security route cannot be triggered on CNP**, by design.
