#!/usr/bin/env python3
"""Generate ../telemetry-names.txt: the telemetry names the KQL may use (DIAAT-205).

Reads a transcribe-api checkout without importing it (standard library only):

* telemetry-contract.json (the API's merged schema as JSON): every registered event
  and attribute. Authoritative for both.
* hmcts-otel's conventions.py, from the checkout's virtual environment
  (.venv/lib/python*/site-packages/hmcts_otel), or --otel-conventions: METRIC_*
  constants are metrics, the other name constants are attributes. The keys of
  hmcts-otel's own metric dimension dicts (``metric_attrs = {"event": ..., "source":
  ...}`` in its other modules) are attributes too: queries read them on its metrics.
* src/transcribe_api/**/*.py, for what the contract does not list:
  - METRIC_* constants: metrics;
  - STAGE_* constants and stage("...") literals: stages. Each stage also produces the
    events <stage>.started / .completed / .failed / .cancelled (hmcts-otel stage());
  - EVENT_* constants and record_event("...") literals: events;
  - JOURNEY_* constants: journey types;
  - ATTR_* constants and the keys of ``*attrs`` / ``attributes`` dict literals: attributes (set on the
    API's own metrics, e.g. speech.operation, phase).

Usage:

    python3 observability/tests/generate_telemetry_names.py --app-repo ../transcribe-api

It also writes ../validation/re2-patterns.txt: transcribe-api's RE2_PATTERNS
(tests/unit/telemetry_scan.py), which the prohibited-content scan must use verbatim
(tests/test_scan_patterns.py).

Run it whenever the API's telemetry changes (after pulling its master), then run
check_kql_names.py and commit the regenerated files with any KQL change.
"""

from __future__ import annotations

import argparse
import ast
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUTPUT = HERE.parent / "telemetry-names.txt"
PATTERNS_OUTPUT = HERE.parent / "validation" / "re2-patterns.txt"
NAME = re.compile(r"[a-z][a-z0-9_]*(\.[a-z0-9_]+)*")
STAGE_VERBS = ("started", "completed", "failed", "cancelled")
# hmcts-otel constants that are not exported names: the custom-event carrier, a marker
# removed before export, the redaction placeholder and the "unknown" attribute value.
CONVENTION_EXCLUDED = {"CUSTOM_EVENT_NAME", "EXCEPTION_FORMATTED", "REDACTED", "UNKNOWN"}
KINDS = ("event", "metric", "attribute", "stage", "journey")
# iCloud copies ("job_telemetry 2.py"): stale duplicates, never the module.
DUPLICATE = re.compile(r" \d+\.py$")


def _str(node: ast.AST | None) -> str | None:
    return node.value if isinstance(node, ast.Constant) and isinstance(node.value, str) else None


def _assignments(tree: ast.Module):
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    yield target.id, node.value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            yield node.target.id, node.value


def contract(text: str, names: dict[str, set[str]]) -> None:
    data = json.loads(text)
    names["event"].update(data["events"])
    names["attribute"].update(data["attributes"])


def conventions(source: str, names: dict[str, set[str]]) -> None:
    for constant, value in _assignments(ast.parse(source)):
        text = _str(value)
        if text is None or constant in CONVENTION_EXCLUDED or not NAME.fullmatch(text):
            continue
        names["metric" if constant.startswith("METRIC_") else "attribute"].add(text)


def metric_dimensions(source: str, names: dict[str, set[str]]) -> None:
    """Keys of dict literals assigned to a ``*attrs`` or ``attributes`` name (metric dimensions)."""
    for node in ast.walk(ast.parse(source)):
        if not (isinstance(node, ast.Assign) and isinstance(node.value, ast.Dict)):
            continue
        if not any(isinstance(t, ast.Name) and (t.id.endswith("attrs") or t.id == "attributes") for t in node.targets):
            continue
        for key in node.value.keys:
            text = _str(key)
            if text is not None and NAME.fullmatch(text):
                names["attribute"].add(text)


def _call_name(node: ast.Call) -> str | None:
    func = node.func
    if isinstance(func, ast.Name):
        return func.id
    if isinstance(func, ast.Attribute):
        return func.attr
    return None


def app_module(source: str, names: dict[str, set[str]]) -> None:
    tree = ast.parse(source)
    prefixes = {
        "EVENT_": "event", "METRIC_": "metric", "STAGE_": "stage", "ATTR_": "attribute", "JOURNEY_": "journey",
    }
    for constant, value in _assignments(tree):
        text = _str(value)
        for prefix, kind in prefixes.items():
            if text is not None and constant.startswith(prefix) and NAME.fullmatch(text):
                names[kind].add(text)
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and node.args:
            first = _str(node.args[0])
            if first is None or not NAME.fullmatch(first):
                continue
            call = _call_name(node)
            if call == "record_event":
                names["event"].add(first)
            elif call == "stage":
                names["stage"].add(first)


def _conventions_file(app_repo: Path, override: Path | None) -> Path:
    if override is not None:
        return override
    found = sorted(app_repo.glob(".venv/lib/python*/site-packages/hmcts_otel/conventions.py"))
    if not found:
        sys.exit(
            f"no hmcts_otel/conventions.py in {app_repo}/.venv: run `uv sync` there, "
            "or pass --otel-conventions"
        )
    return found[-1]


def generate(app_repo: Path, otel_conventions: Path | None = None) -> str:
    names: dict[str, set[str]] = {kind: set() for kind in KINDS}
    contract_file = app_repo / "telemetry-contract.json"
    if not contract_file.is_file():
        sys.exit(f"no telemetry-contract.json in {app_repo}")
    contract(contract_file.read_text(encoding="utf-8"), names)
    conventions_file = _conventions_file(app_repo, otel_conventions)
    conventions(conventions_file.read_text(encoding="utf-8"), names)
    for module in sorted(p for p in conventions_file.parent.glob("*.py") if not DUPLICATE.search(p.name)):
        metric_dimensions(module.read_text(encoding="utf-8"), names)
    sources = sorted(p for p in (app_repo / "src" / "transcribe_api").rglob("*.py") if not DUPLICATE.search(p.name))
    if not sources:
        sys.exit(f"no src/transcribe_api in {app_repo}")
    for path in sources:
        source = path.read_text(encoding="utf-8")
        app_module(source, names)
        metric_dimensions(source, names)
    for stage in names["stage"]:
        names["event"].update(f"{stage}.{verb}" for verb in STAGE_VERBS)

    try:
        commit = subprocess.run(
            ["git", "-C", str(app_repo), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        commit = "unknown"
    lines = [
        "# Telemetry names the KQL in ./kql and ./validation may use: <kind> <name>. GENERATED, do not edit.",
        f"# Source: transcribe-api @ {commit} (telemetry-contract.json, hmcts-otel conventions and",
        "# src/transcribe_api). Regenerate: tests/generate_telemetry_names.py --app-repo <path>.",
        "# Checked by tests/check_kql_names.py.",
    ]
    for kind in KINDS:
        lines.extend(f"{kind} {name}" for name in sorted(names[kind]))
    return "\n".join(lines) + "\n"


def re2_patterns(source: str) -> dict[str, str]:
    """RE2_PATTERNS from transcribe-api's tests/unit/telemetry_scan.py: name -> pattern."""
    for node in ast.parse(source).body:
        target = node.target if isinstance(node, ast.AnnAssign) else (node.targets[0] if isinstance(node, ast.Assign) else None)
        if isinstance(target, ast.Name) and target.id == "RE2_PATTERNS" and isinstance(node.value, ast.Dict):
            return {
                ast.literal_eval(key): ast.literal_eval(value.args[0])
                for key, value in zip(node.value.keys, node.value.values)
                if isinstance(value, ast.Call) and value.args
            }
    sys.exit("no RE2_PATTERNS in transcribe-api tests/unit/telemetry_scan.py")


def patterns_file(app_repo: Path) -> str:
    patterns = re2_patterns((app_repo / "tests" / "unit" / "telemetry_scan.py").read_text(encoding="utf-8"))
    lines = [
        "# transcribe-api's RE2_PATTERNS (tests/unit/telemetry_scan.py): <name><TAB><pattern>. GENERATED.",
        "# prohibited_content_scan.kql must use each verbatim (tests/test_scan_patterns.py).",
    ]
    lines.extend(f"{name}\t{pattern}" for name, pattern in patterns.items())
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--app-repo", type=Path, required=True, help="transcribe-api checkout")
    parser.add_argument("--otel-conventions", type=Path, help="hmcts_otel/conventions.py, if not in the checkout's .venv")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    args.output.write_text(generate(args.app_repo.resolve(), args.otel_conventions), encoding="utf-8")
    PATTERNS_OUTPUT.write_text(patterns_file(args.app_repo.resolve()), encoding="utf-8")
    print(f"wrote {args.output} and {PATTERNS_OUTPUT}")


if __name__ == "__main__":
    main()
