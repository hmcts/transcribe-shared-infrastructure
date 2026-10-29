#!/usr/bin/env python3
"""The prohibited-content scan uses transcribe-api's RE2 patterns verbatim (DIAAT-287).

transcribe-api's automated scan (tests/unit/telemetry_scan.py) and this deployed sample
scan must look for the same things. ../validation/re2-patterns.txt is the API's
RE2_PATTERNS, pinned by generate_telemetry_names.py.

Usage: python3 -m unittest discover -s observability/tests
Standard library only.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

VALIDATION = Path(__file__).resolve().parent.parent / "validation"
SCAN = VALIDATION / "prohibited_content_scan.kql"
PINNED = VALIDATION / "re2-patterns.txt"
KQL_PATTERN = re.compile(r'^\s*(?P<name>[a-z_]+) = text matches regex @"(?P<pattern>[^"]*)"', re.MULTILINE)


def pinned() -> dict[str, str]:
    patterns = {}
    for line in PINNED.read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("#"):
            name, pattern = line.split("\t", 1)
            patterns[name] = pattern
    return patterns


class ScanPatterns(unittest.TestCase):
    def test_the_scan_uses_every_api_pattern_verbatim(self) -> None:
        in_kql = {m["name"]: m["pattern"] for m in KQL_PATTERN.finditer(SCAN.read_text(encoding="utf-8"))}
        self.assertTrue(pinned(), "re2-patterns.txt is empty")
        self.assertEqual(in_kql, pinned())

    def test_every_pattern_is_reported(self) -> None:
        text = SCAN.read_text(encoding="utf-8")
        for name in pinned():
            with self.subTest(name):
                self.assertIn(f'iff({name}, "{name}", "")', text)


class ClearedRows(unittest.TestCase):
    """PR review: sign-off needs every match reviewed, not five samples per group."""

    def test_cleared_false_positives_are_excluded_before_the_hits_are_counted(self) -> None:
        text = SCAN.read_text(encoding="utf-8")
        self.assertIn("let cleared_row_ids = dynamic([]);", text)
        hits = text[text.index("let hits = scanned"):]
        self.assertTrue(hits.splitlines()[1].strip() == "| where row_id !in (cleared_row_ids)")


if __name__ == "__main__":
    unittest.main()
