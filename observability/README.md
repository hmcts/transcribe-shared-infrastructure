# Observability queries (DIAAT-205)

The KQL behind the transcribe product's workbooks and alerts, for both areas of the
merged service: **dictation** (live dictation, uploads, minutes and documents) and
**recording** (hearing recordings transcribed by Azure Speech batch jobs). It merges
the two heritage modules (courtstranscribe and batch-audio-transcription-infra).

Every query runs against the environment's Application Insights resource: one per
environment, so no query splits by environment. Sampling is 100% (`sampling_percentage`
in the product's `application-insights.tf`); queries still `sum(itemCount)`.

## Layout

| Path | What |
|---|---|
| `kql/service_*.kql` | the service as a whole: requests, errors, exceptions, dependencies, availability |
| `kql/dictation_*.kql` | dictation only |
| `kql/recording_*.kql` | recording only |
| `kql/ai_*.kql` | AI usage (Speech and LLMs) for both areas, by feature and mode |
| `kql/workload_*.kql` | volumes and capacity, with an `area` column |
| `kql/cost_*.kql` | cost allocation by usage share |
| `kql/alert_<service|dictation|recording>_*.kql` | alert queries (see `ALERTS.md`) |
| `validation/*.kql` | DIAAT-287 checks, run by hand, not panels |
| `telemetry-names.txt` | every name the KQL may use, generated from transcribe-api |
| `tests/` | the name and area check, and its tests |

## Services (`cloud_RoleName`)

| Service | What |
|---|---|
| `transcribe-api` | the API: both areas' requests |
| `transcribe-api-worker` | the pollers and the jobs they run (dictation uploads, recording batch jobs) |
| `transcribe-web` | the Next.js server (the browser's relayed events come through `transcribe-api`) |

## Telling the areas apart

`hmcts.area` (`dictation` or `recording`) is set by transcribe-api on every request,
event, log and span of an area (hmcts-otel 0.3.0; decision 1). Shared code has none:
the top-level `/health`, the background dependency checker, and the browser relay
(`/api/telemetry`). Browser events of a dictation session carry its journey,
`dictation.session`.

Every query for one area filters on it, with the journey type's prefix as the
fallback. `tests/check_kql_names.py` fails a `dictation_*` or `recording_*` file that
does not.

Events, traces, exceptions, dependencies:

```kusto
| extend area = coalesce(tostring(customDimensions["hmcts.area"]),
    tostring(split(tostring(customDimensions["hmcts.journey.type"]), ".")[0]))
| where area == "recording"
```

Requests (`/api/v1/*` is recording, the rest of `/api/*` dictation, by mount point;
the relay and the OpenAPI document are shared, as transcribe-api's `area_for_path`):

```kusto
| extend path = tolower(tostring(parse_url(url).Path))
| extend area = coalesce(tostring(customDimensions["hmcts.area"]),
    case(path in ("/api/telemetry", "/api/openapi.json"), "",
        path == "/api/v1" or path startswith "/api/v1/", "recording",
        path startswith "/api/", "dictation", ""))
```

Alert queries read only safe keys and mention `url` only in a `| where` filter, so in
an alert, filter requests on `customDimensions["hmcts.area"]` alone.

Event names shared by both areas, which always need the filter: `job.finished`,
`transcript.available`, the `upload.*` stage events, `security.ownership_violation`
and `audit.write_failed`. `upload.validation_failed` is recording's server check; the
browser's rejected file is `upload.file_rejected` (decision 3).

## Conventions

- Each file starts with a `//` comment: the measure, the formula, the source events
  and the caveats.
- Health probes and synthetic traffic are excluded from request measures:
  `path matches regex @"(^|/)(health|healthz|healthcheck|livez|readyz|version)(/|$)"`
  and `isempty(operation_SyntheticSource)`.
- 4xx are client outcomes, not server errors.
- `dependency.name` is `database`, `storage` or `speech`.

## Checks

```bash
python3 observability/tests/check_kql_names.py
python3 -m unittest discover -s observability/tests
```

After transcribe-api's telemetry changes, regenerate the names from a checkout of its
master and commit them with any KQL change:

```bash
python3 observability/tests/generate_telemetry_names.py --app-repo ../transcribe-api
```
