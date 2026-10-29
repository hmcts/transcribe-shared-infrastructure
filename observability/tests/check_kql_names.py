#!/usr/bin/env python3
"""Check every KQL file uses only telemetry names transcribe-api emits (DIAAT-284, DIAAT-205).

For each ../kql/*.kql and ../validation/*.kql (DIAAT-287), extracts:

* event names: ``name == "x"`` / ``name in ("x", ...)`` after ``customEvents``
* metric names: the same after ``customMetrics``
  (names after other tables, e.g. requests or availabilityResults, are not app
  telemetry and are skipped)
* attribute names: ``customDimensions["x"]``
* stage names: ``stage == "x"`` / ``stage in ("x", ...)``

and fails if any is not in ../telemetry-names.txt (generated from transcribe-api by
generate_telemetry_names.py). It also fails if a file does not start with its
measure comment, or a name comparison has no table before it.

One API serves both areas, and some event names (job.finished, transcript.available,
the security and dependency events) come from both. So a query for one area, a file
named dictation_*.kql or recording_*.kql (alert_dictation_* / alert_recording_* for
alerts), must filter on the area when it reads a table that carries it (customEvents,
requests, traces, dependencies, exceptions): it must read hmcts.area (decision 1; the
journey type's prefix is the fallback). Metrics carry no area (their dimensions are
explicit), so a metrics-only query relies on metrics only that area emits. Other files
are shared or cross-area.

Alert queries (DIAAT-285, files named alert_*.kql) must also keep transcript, audio,
case and party content out of alerts (AC3). Whatever an alert query returns can
appear in a notification (dimensions) or its linked results, so each one must:

* end with a single-line ``| project a, b, c`` of plain column names, every one in
  SAFE_ALERT_COLUMNS (counts, rates, codes, sources, states, IDs): no expressions or
  renames there, so every output column is one this check has vetted;
* read customDimensions only by key, and only keys in SAFE_ALERT_ATTRIBUTES;
* never mention a content-bearing column (CONTENT_COLUMNS) such as message or
  details, and mention url only in a ``| where`` filter, never as a value.

Usage: python3 observability/tests/check_kql_names.py
Exit status 0 when every name is known, 1 otherwise. Standard library only.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
KQL_DIR = HERE.parent / "kql"
# DIAAT-287: validation-only queries (not panels or alerts), checked the same way.
VALIDATION_DIR = HERE.parent / "validation"
ALLOWLIST = HERE.parent / "telemetry-names.txt"

TOKEN = re.compile(
    r"""
    (?P<table>\b(?:customEvents|customMetrics|requests|dependencies|exceptions|traces
        |availabilityResults|pageViews|browserTimings)\b)
    | \bname\s*(?:(?:==|=~)\s*(?P<name>"[^"]*")|in~?\s*\(\s*(?P<names>"[^"]*"(?:\s*,\s*"[^"]*")*)\s*\))
    | customDimensions\[\s*"event"\s*\]\s*\)\s*(?:==\s*(?P<dim_event>"[^"]*")
        |in\s*\(\s*(?P<dim_events>"[^"]*"(?:\s*,\s*"[^"]*")*)\s*\))
    | customDimensions\[\s*"hmcts\.journey\.type"\s*\]\s*\)\s*(?:==\s*(?P<journey>"[^"]*")
        |in\s*\(\s*(?P<journeys>"[^"]*"(?:\s*,\s*"[^"]*")*)\s*\))
    | customDimensions\[\s*"(?P<attribute>[^"]+)"\s*\]
    | \bstage\s*(?:==\s*(?P<stage>"[^"]*")|in\s*\(\s*(?P<stages>"[^"]*"(?:\s*,\s*"[^"]*")*)\s*\))
    """,
    re.VERBOSE,
)
STRING = re.compile(r'"([^"]*)"')
# `event = tostring(customDimensions["event"])`, then `event in ("x", ...)`: the alias's
# literals are names too (hmcts-otel's event metric dimension, and the journey type).
ALIAS = re.compile(
    r'\b(?P<alias>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*tostring\(\s*customDimensions\[\s*"(?P<key>event|hmcts\.journey\.type)"\s*\]\s*\)'
)
KIND_BY_ALIASED_KEY = {"event": "event", "hmcts.journey.type": "journey"}


def _alias_comparisons(alias: str) -> re.Pattern[str]:
    return re.compile(
        rf'\b{re.escape(alias)}\s*(?:==\s*(?P<one>"[^"]*")|in\s*\(\s*(?P<many>"[^"]*"(?:\s*,\s*"[^"]*")*)\s*\))'
    )

# DIAAT-285 (AC3): what an alert query may output, by kind. Counts, rates and measures:
SAFE_ALERT_COLUMNS = {
    "requests", "availability_pct", "server_error_pct", "up", "last_success_age_s",
    "violations", "stuck", "oldest_waiting_min", "failed", "failed_pct", "failures",
    # OBS-5: audio hours sent to Azure Speech (usage, never cost):
    "audio_hours", "baseline_hours", "spike_ratio", "tokens", "baseline_tokens", "sessions",
    # codes, sources, states and enums:
    "error_code", "source", "outcome", "state", "operation", "resource_type", "action",
    "feature", "area",
    # what failed (system names, never people or records):
    "cloud_RoleName", "dependency",
}
# customDimensions keys an alert query may read: enums, codes and system-generated IDs.
SAFE_ALERT_ATTRIBUTES = {
    "dependency.name", "hmcts.error.code", "hmcts.failure.source", "hmcts.outcome",
    # DIAAT-205: the area (decision 1) and the journey type it falls back to.
    "hmcts.area", "hmcts.journey.type",
    "job.state", "security.action", "security.outcome", "security.resource_type",
    "speech.operation", "storage.operation", "hmcts.request.id", "hmcts.journey.id",
    # OBS-5: the AI feature (stage-name rule) and the speech mode (an enum).
    "hmcts.ai.feature", "hmcts.speech.mode",
    # hmcts-otel's event metrics: the event name and its source (browser or server).
    "event", "source",
    # Dictation: controlled values (enums, Speech SDK code names), never content.
    "live_draft.failure_kind", "speech.cancel_reason", "speech.error_code",
}
# App Insights columns that can hold free text, people or content.
CONTENT_COLUMNS = {
    "message", "details", "outerMessage", "innermostMessage", "customMeasurements",
    "data", "target", "operation_Name", "user_Id", "user_AuthenticatedId",
    "user_AccountId", "session_Id", "client_IP", "client_City", "client_StateOrProvince",
}
FILTER_ONLY_COLUMNS = {"url"}
FINAL_PROJECT = re.compile(r"^\|\s*project\s+(?P<columns>.+?)\s*;?$")
IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
STRING_LITERAL = re.compile(r'@?"[^"]*"')
DIMENSION_KEY = re.compile(r'customDimensions\s*\[\s*"(?P<key>[^"]*)"\s*\]')
SINGLE_QUOTED_KEY = re.compile(r"customDimensions\s*\[\s*'")
BARE_DIMENSIONS = re.compile(r"\bcustomDimensions\b(?!\s*\[)")
KIND_BY_TABLE = {"customEvents": "event", "customMetrics": "metric"}
AREA_FILE = re.compile(r"^(?:alert_)?(?:dictation|recording)_")
AREA_ATTRIBUTE = re.compile(r'customDimensions\s*\[\s*"hmcts\.area"\s*\]')
AREA_TABLES = re.compile(r"\b(?:customEvents|requests|traces|dependencies|exceptions)\b")


def area_problems(name: str, code: str) -> list[str]:
    """An area's query filters every read of an area-carrying table on its own area.

    Each read (a table name) must reach, before its statement ends (the next ";", which
    closes a let, or the end), both a hmcts.area read and the own-area predicate
    ``where area == "<area>"`` or ``where area in (..., "<area>", ...)``. A branch that only
    reads the area, or filters on the other one, cannot be unioned or joined in unfiltered.
    """
    match = AREA_FILE.match(name)
    if match is None or not AREA_TABLES.search(code):
        return []
    area = "recording" if "recording" in match.group(0) else "dictation"
    keeps = re.compile(rf'\|\s*where\s+area\s*(?:==\s*"{area}"|in\s*\([^)]*"{area}")')
    problems = []
    for table in AREA_TABLES.finditer(code):
        end = code.find(";", table.end())
        statement = code[table.start(): end if end != -1 else len(code)]
        if not AREA_ATTRIBUTE.search(statement):
            problems.append(
                f"{table.group(0)} is read without an hmcts.area filter before its statement ends (decision 1)"
            )
        elif not keeps.search(statement):
            problems.append(
                f'{table.group(0)} is read without `| where area == "{area}"` before its statement ends (decision 1)'
            )
    return problems


def load_allowlist(path: Path = ALLOWLIST) -> set[tuple[str, str]]:
    allowed = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            kind, name = line.split(maxsplit=1)
            allowed.add((kind, name))
    return allowed


def _code(text: str) -> str:
    """The file without // comments (names in comments are documentation, not queries)."""
    return "\n".join(_strip_comment(line) for line in text.splitlines())


def _strip_comment(line: str) -> str:
    """The line up to a // that is not inside a "string"."""
    in_string = False
    for index, char in enumerate(line):
        if char == '"':
            in_string = not in_string
        elif char == "/" and not in_string and line[index:index + 2] == "//":
            return line[:index]
    return line


def references(text: str) -> tuple[list[tuple[str, str]], list[str]]:
    """(kind, name) pairs used by a query, and problems found while reading it."""
    found: list[tuple[str, str]] = []
    problems: list[str] = []
    table: str | None = None
    for match in TOKEN.finditer(_code(text)):
        if match["table"]:
            table = match["table"]
        elif match["name"] or match["names"]:
            if table is None:
                problems.append(f"name comparison with no table before it: {match.group(0)!r}")
                continue
            kind = KIND_BY_TABLE.get(table)
            if kind is not None:
                found.extend((kind, n) for n in STRING.findall(match["name"] or match["names"]))
        elif match["dim_event"] or match["dim_events"]:
            # hmcts-otel's event metrics: the "event" dimension is an event name.
            found.append(("attribute", "event"))
            found.extend(("event", n) for n in STRING.findall(match["dim_event"] or match["dim_events"]))
        elif match["journey"] or match["journeys"]:
            found.append(("attribute", "hmcts.journey.type"))
            found.extend(("journey", n) for n in STRING.findall(match["journey"] or match["journeys"]))
        elif match["attribute"]:
            found.append(("attribute", match["attribute"]))
        elif match["stage"] or match["stages"]:
            found.extend(("stage", n) for n in STRING.findall(match["stage"] or match["stages"]))
    code = _code(text)
    for alias in ALIAS.finditer(code):
        kind = KIND_BY_ALIASED_KEY[alias["key"]]
        for comparison in _alias_comparisons(alias["alias"]).finditer(code, alias.end()):
            found.extend((kind, n) for n in STRING.findall(comparison["one"] or comparison["many"]))
    return found, problems


def alert_problems(text: str) -> list[str]:
    """Why an alert query could put unsafe values in an alert (DIAAT-285, AC3)."""
    problems: list[str] = []
    code = _code(text)
    lines = [line.strip() for line in code.splitlines() if line.strip()]
    final = FINAL_PROJECT.match(lines[-1]) if lines else None
    if final is None:
        problems.append("alert query must end with a one-line '| project <columns>'")
    else:
        for column in (part.strip() for part in final["columns"].split(",")):
            if not IDENTIFIER.fullmatch(column):
                problems.append(f"final project must list plain column names, not {column!r}")
            elif column not in SAFE_ALERT_COLUMNS:
                problems.append(f"alert output column {column!r} is not in SAFE_ALERT_COLUMNS")
    for match in DIMENSION_KEY.finditer(code):
        if match["key"] not in SAFE_ALERT_ATTRIBUTES:
            problems.append(f"alert reads customDimensions[{match['key']!r}], not in SAFE_ALERT_ATTRIBUTES")
    if SINGLE_QUOTED_KEY.search(code):
        problems.append("alert reads a customDimensions key in single quotes; use double quotes")
    if "column_ifexists" in code:
        problems.append("alert uses column_ifexists; name columns directly")
    if re.search(r"\bpack_all\s*\(", STRING_LITERAL.sub("", code)):
        problems.append("alert uses pack_all; read single safe columns")
    without_keys = DIMENSION_KEY.sub("", code)
    if BARE_DIMENSIONS.search(without_keys):
        problems.append("alert uses customDimensions as a whole; read single safe keys")
    for line in lines:
        words = set(IDENTIFIER.findall(STRING_LITERAL.sub("", DIMENSION_KEY.sub("", line))))
        problems.extend(f"alert mentions content column {word!r}" for word in sorted(words & CONTENT_COLUMNS))
        if words & FILTER_ONLY_COLUMNS and (
            not re.match(r"^\|\s*where\b", line)
            or "|" in STRING_LITERAL.sub("", line)[1:]
        ):
            problems.extend(
                f"alert uses {word!r} outside a '| where' filter (no additional operators on that line)"
                for word in sorted(words & FILTER_ONLY_COLUMNS)
            )
    return problems


def check(kql_dir: Path = KQL_DIR, allowlist: Path = ALLOWLIST) -> list[str]:
    allowed = load_allowlist(allowlist)
    errors: list[str] = []
    files = sorted(kql_dir.glob("*.kql"))
    if not files:
        return [f"no .kql files in {kql_dir}"]
    for path in files:
        text = path.read_text(encoding="utf-8")
        if not text.startswith("//"):
            errors.append(f"{path.name}: must start with a // comment stating the measure")
        found, problems = references(text)
        problems += area_problems(path.name, _code(text))
        if path.name.startswith("alert_"):
            problems += alert_problems(text)
        errors.extend(f"{path.name}: {problem}" for problem in problems)
        errors.extend(
            f"{path.name}: unknown {kind} {name!r} (not in {allowlist.name})"
            for kind, name in dict.fromkeys(found)
            if (kind, name) not in allowed
        )
    return errors


def main() -> None:
    errors = check() + check(VALIDATION_DIR)
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        print(f"{len(errors)} problem(s). If transcribe-api's telemetry changed, regenerate "
              "telemetry-names.txt with generate_telemetry_names.py.", file=sys.stderr)
        sys.exit(1)
    alerts = len(list(KQL_DIR.glob("alert_*.kql")))
    files = len(list(KQL_DIR.glob("*.kql"))) + len(list(VALIDATION_DIR.glob("*.kql")))
    print(f"OK: every name in {files} KQL files is in {ALLOWLIST.name}; "
          f"{alerts} alert queries output only safe columns")


if __name__ == "__main__":
    main()
