#!/usr/bin/env python3
"""Tests for generate_telemetry_names.py's reading of hmcts-otel conventions (OBS-5).

Usage: python3 -m unittest discover -s observability/tests
Standard library only.
"""

from __future__ import annotations

import unittest

import generate_telemetry_names as generator

# The shape of hmcts_otel/conventions.py (0.2.0).
CONVENTIONS = '''
METRIC_SPEECH_AUDIO_DURATION = "hmcts.speech.audio.duration"
METRIC_GEN_AI_TOKEN_USAGE = "gen_ai.client.token.usage"
SPEECH_MODE = "hmcts.speech.mode"
AI_FEATURE = "hmcts.ai.feature"
GEN_AI_SEMCONV_VERSION = "1.37.0"
UNKNOWN = "unknown"
REDACTED = "[REDACTED]"
CUSTOM_EVENT_NAME = "microsoft.custom_event.name"
'''


class Conventions(unittest.TestCase):
    def setUp(self) -> None:
        self.names: dict[str, set[str]] = {"event": set(), "metric": set(), "attribute": set(), "stage": set()}
        generator.conventions(CONVENTIONS, self.names)

    def test_ai_usage_metrics_and_attributes_are_names(self) -> None:
        self.assertEqual(self.names["metric"], {"hmcts.speech.audio.duration", "gen_ai.client.token.usage"})
        self.assertIn("hmcts.speech.mode", self.names["attribute"])
        self.assertIn("hmcts.ai.feature", self.names["attribute"])

    def test_values_that_are_not_names_are_left_out(self) -> None:
        # "unknown" is the value recorded for an invalid provider, model or feature.
        self.assertEqual(self.names["attribute"], {"hmcts.speech.mode", "hmcts.ai.feature"})


class Contract(unittest.TestCase):
    """DIAAT-205: events and attributes come from transcribe-api's telemetry contract."""

    def test_every_event_and_attribute_in_the_contract_is_a_name(self) -> None:
        names: dict[str, set[str]] = {kind: set() for kind in generator.KINDS}
        generator.contract(
            '{"events": {"job.finished": {}}, "attributes": {"hmcts.area": {}, "hmcts.outcome": {}}}', names
        )
        self.assertEqual(names["event"], {"job.finished"})
        self.assertEqual(names["attribute"], {"hmcts.area", "hmcts.outcome"})


class MetricDimensions(unittest.TestCase):
    def test_hmcts_otels_metric_dimension_keys_are_attributes(self) -> None:
        names: dict[str, set[str]] = {kind: set() for kind in generator.KINDS}
        generator.metric_dimensions(
            'metric_attrs = {"event": name, "class": cls, "source": src}\n'
            'other = {"not.a.dimension": 1}\n',
            names,
        )
        self.assertEqual(names["attribute"], {"event", "class", "source"})


class AppSource(unittest.TestCase):
    def test_metrics_stages_and_events_are_read_from_the_source(self) -> None:
        names: dict[str, set[str]] = {kind: set() for kind in generator.KINDS}
        generator.app_module(
            'METRIC_JOBS = "transcription.jobs.finished"\n'
            'STAGE_UPLOAD = "upload"\n'
            'def f():\n'
            '    with stage("speech_token"):\n'
            '        record_event("job.finished")\n',
            names,
        )
        self.assertEqual(names["metric"], {"transcription.jobs.finished"})
        self.assertEqual(names["stage"], {"upload", "speech_token"})
        self.assertEqual(names["event"], {"job.finished"})


if __name__ == "__main__":
    unittest.main()
