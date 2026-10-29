#!/usr/bin/env python3
"""Tests for check_kql_names.py: alert outputs (DIAAT-285, AC3) and areas (DIAAT-205).

Usage: python3 -m unittest discover -s observability/tests
Standard library only.
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import check_kql_names as checker

SAFE = """// ALERT: a safe query.
customEvents
| where name == "job.storage_failed"
| where not(url matches regex @"/(health)(/|$)")
| extend error_code = tostring(customDimensions["hmcts.error.code"])
| summarize failures = count() by error_code
| project error_code, failures
"""


class AlertOutputCheck(unittest.TestCase):
    def assert_rejected(self, text: str, fragment: str) -> None:
        problems = checker.alert_problems(text)
        self.assertTrue(
            any(fragment in problem for problem in problems),
            f"expected a problem containing {fragment!r}, got {problems}",
        )

    def test_safe_query_passes(self) -> None:
        self.assertEqual(checker.alert_problems(SAFE), [])

    def test_every_alert_query_in_the_module_passes(self) -> None:
        files = sorted(checker.KQL_DIR.glob("alert_*.kql"))
        self.assertTrue(files, "no alert_*.kql files")
        for path in files:
            with self.subTest(path.name):
                self.assertEqual(checker.alert_problems(path.read_text(encoding="utf-8")), [])

    def test_unsafe_output_column_is_rejected(self) -> None:
        text = SAFE.replace("| project error_code, failures", "| project error_code, failures, url")
        self.assert_rejected(text, "'url' is not in SAFE_ALERT_COLUMNS")

    def test_renamed_content_is_rejected(self) -> None:
        text = SAFE.replace("| summarize", "| extend source = url\n| summarize")
        self.assert_rejected(text, "uses 'url' outside a '| where' filter")

    def test_expression_in_final_project_is_rejected(self) -> None:
        text = SAFE.replace("| project error_code, failures", "| project error_code, n = failures")
        self.assert_rejected(text, "plain column names")

    def test_query_must_end_with_project(self) -> None:
        self.assert_rejected(SAFE.replace("| project error_code, failures", "| order by failures"), "must end with")
        self.assert_rejected(SAFE.replace("| project error_code, failures", "| project-away error_code"), "must end with")

    def test_whole_custom_dimensions_is_rejected(self) -> None:
        text = SAFE.replace("| summarize", "| extend bag = tostring(customDimensions)\n| summarize")
        self.assert_rejected(text, "customDimensions as a whole")

    def test_unsafe_custom_dimension_key_is_rejected(self) -> None:
        text = SAFE.replace('customDimensions["hmcts.error.code"]', 'customDimensions["file.size_bytes"]')
        self.assert_rejected(text, "customDimensions['file.size_bytes'], not in SAFE_ALERT_ATTRIBUTES")

    def test_content_column_is_rejected(self) -> None:
        for column in ("message", "details", "user_AuthenticatedId", "client_IP"):
            with self.subTest(column):
                text = SAFE.replace("| summarize", f"| where isnotempty({column})\n| summarize")
                self.assert_rejected(text, f"content column {column!r}")

    def test_names_in_comments_and_strings_are_not_columns(self) -> None:
        text = SAFE.replace("| summarize", '// message, url\n| where error_code != "message url"\n| summarize')
        self.assertEqual(checker.alert_problems(text), [])

    def test_a_computed_dimension_key_is_rejected(self) -> None:
        # PR review: customDimensions[key] would bypass SAFE_ALERT_ATTRIBUTES.
        text = 'let key = "transcript.title";\n' + SAFE.replace(
            '| extend error_code = tostring(customDimensions["hmcts.error.code"])',
            '| extend error_code = tostring(customDimensions["hmcts.error.code"]), source = tostring(customDimensions[key])',
        )
        self.assert_rejected(text, "computed key")

    def test_single_quoted_keys_and_column_ifexists_are_rejected(self) -> None:
        quoted = SAFE.replace('customDimensions["hmcts.error.code"]', "customDimensions['transcript.title']")
        self.assert_rejected(quoted, "single quotes")
        hidden = SAFE.replace("| summarize", '| extend source = tostring(column_ifexists("details", ""))\n| summarize')
        self.assert_rejected(hidden, "column_ifexists")

    def test_check_applies_the_alert_rules_only_to_alert_files(self) -> None:
        unsafe = SAFE.replace("| project error_code, failures", "| project error_code, failures, url")
        with tempfile.TemporaryDirectory() as tmp:
            kql = Path(tmp)
            (kql / "alert_x.kql").write_text(unsafe, encoding="utf-8")
            (kql / "view_x.kql").write_text(unsafe, encoding="utf-8")
            errors = checker.check(kql, checker.ALLOWLIST)
        self.assertTrue(errors)
        self.assertEqual({e.split(":")[0] for e in errors}, {"alert_x.kql"})


class AreaQueries(unittest.TestCase):
    """DIAAT-205: one API serves both areas, so an area's query filters on hmcts.area."""

    AREA_FILTER = (
        '| extend area = coalesce(tostring(customDimensions["hmcts.area"]), '
        'tostring(split(tostring(customDimensions["hmcts.journey.type"]), ".")[0]))\n'
        '| where area == "recording"\n'
    )
    QUERY = '// Jobs.\ncustomEvents\n| where name == "job.finished"\n{area}| summarize jobs = count()\n'

    def _errors(self, name: str, text: str) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            kql = Path(tmp)
            (kql / name).write_text(text, encoding="utf-8")
            return checker.check(kql, checker.ALLOWLIST)

    def test_an_area_query_without_the_area_filter_is_rejected(self) -> None:
        for name in ("recording_jobs.kql", "dictation_jobs.kql", "alert_recording_jobs.kql"):
            with self.subTest(name):
                errors = self._errors(name, self.QUERY.format(area=""))
                self.assertTrue(any("hmcts.area" in error for error in errors), errors)

    def test_an_area_query_with_the_area_filter_passes(self) -> None:
        self.assertEqual(self._errors("recording_jobs.kql", self.QUERY.format(area=self.AREA_FILTER)), [])

    def test_the_area_in_a_comment_does_not_count(self) -> None:
        text = self.QUERY.format(area='// customDimensions["hmcts.area"]\n')
        self.assertTrue(any("hmcts.area" in error for error in self._errors("recording_jobs.kql", text)))

    def test_a_metrics_only_area_query_needs_no_area(self) -> None:
        # Metrics carry no hmcts.area: the query relies on a metric only that area emits.
        text = '// Jobs.\ncustomMetrics\n| where name == "transcription.jobs.finished"\n| summarize sum(valueSum)\n'
        self.assertEqual(self._errors("recording_jobs.kql", text), [])

    def test_an_unfiltered_let_branch_is_rejected(self) -> None:
        text = (
            '// Jobs.\nlet failures = customEvents\n| where name == "job.finished"\n| project x = 1;\n'
            + self.QUERY.format(area=self.AREA_FILTER)
        )
        errors = self._errors("recording_jobs.kql", text)
        self.assertTrue(any("customEvents is read without an hmcts.area filter" in e for e in errors), errors)

    def test_a_branch_that_reads_but_does_not_filter_the_area_is_rejected(self) -> None:
        # PR review: an unfiltered branch unioned into a filtered one mixes the areas.
        text = (
            '// Jobs.\nlet all = customEvents\n'
            '| extend area = tostring(customDimensions["hmcts.area"]);\n'
            'let mine = customEvents\n' + self.AREA_FILTER + '| where name == "job.finished";\n'
            'union all, mine\n| summarize jobs = count()\n'
        )
        errors = self._errors("recording_jobs.kql", text)
        self.assertTrue(any('without `| where area == "recording"`' in e for e in errors), errors)

    def test_an_area_query_must_keep_its_own_area(self) -> None:
        text = self.QUERY.format(area=self.AREA_FILTER.replace('"recording"', '"dictation"'))
        errors = self._errors("recording_jobs.kql", text)
        self.assertTrue(any('area == "recording"' in e for e in errors), errors)
        self.assertEqual(self._errors("dictation_jobs.kql", text), [])

    def test_shared_queries_need_no_area(self) -> None:
        self.assertEqual(self._errors("service_jobs.kql", self.QUERY.format(area="")), [])


class DimensionNames(unittest.TestCase):
    """Event names on hmcts-otel's "event" metric dimension, and journey types, are names too."""

    def test_event_and_journey_comparisons_are_read_as_names(self) -> None:
        text = (
            'customMetrics\n| where tostring(customDimensions["event"]) == "speech.session_stopped"\n'
            '| where tostring(customDimensions["hmcts.journey.type"]) in ("dictation.session", "nope.journey")\n'
        )
        found, _ = checker.references(text)
        self.assertIn(("event", "speech.session_stopped"), found)
        self.assertIn(("journey", "dictation.session"), found)
        self.assertIn(("journey", "nope.journey"), found)
        allowed = checker.load_allowlist()
        self.assertIn(("journey", "dictation.session"), allowed)
        self.assertNotIn(("journey", "nope.journey"), allowed)


class AliasedNames(unittest.TestCase):
    """PR review: `event = tostring(customDimensions["event"]) | where event in (...)`."""

    def test_aliased_event_and_journey_names_are_checked(self) -> None:
        text = (
            'customMetrics\n| extend event = tostring(customDimensions["event"]),\n'
            '    journey = tostring(customDimensions["hmcts.journey.type"])\n'
            '| where event in ("speech.session_stopped", "speech.no_such_event")\n'
            '| where journey == "dictation.session"\n'
        )
        found, _ = checker.references(text)
        self.assertIn(("event", "speech.no_such_event"), found)
        self.assertIn(("event", "speech.session_stopped"), found)
        self.assertIn(("journey", "dictation.session"), found)

    def test_a_typo_in_an_aliased_event_fails_the_check(self) -> None:
        text = (
            '// Latency.\ncustomMetrics\n| where name == "hmcts.event.duration"\n'
            '| extend event = tostring(customDimensions["event"])\n| where event in ("speech.frist_result")\n'
        )
        with tempfile.TemporaryDirectory() as tmp:
            kql = Path(tmp)
            (kql / "workload_x.kql").write_text(text, encoding="utf-8")
            errors = checker.check(kql, checker.ALLOWLIST)
        self.assertTrue(any("speech.frist_result" in e for e in errors), errors)


class ValidationQueries(unittest.TestCase):
    """DIAAT-287: the validation queries are checked like the panels."""

    def test_validation_queries_pass(self) -> None:
        self.assertTrue(sorted(checker.VALIDATION_DIR.glob("*.kql")), "no validation queries")
        self.assertEqual(checker.check(checker.VALIDATION_DIR), [])

    def test_main_checks_the_validation_queries(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            validation = Path(tmp)
            (validation / "scan.kql").write_text('customEvents\n| where name == "nope"\n')
            original = checker.VALIDATION_DIR
            checker.VALIDATION_DIR = validation
            try:
                with self.assertRaises(SystemExit):
                    checker.main()
            finally:
                checker.VALIDATION_DIR = original


if __name__ == "__main__":
    unittest.main()
