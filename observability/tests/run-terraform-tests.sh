#!/usr/bin/env bash
# Plan the root's observability-*.tf against a mock provider (tests/*.tftest.hcl), with
# tests/harness/ in place of observability.tf, so no Azure access or git modules are
# needed. Usage: observability/tests/run-terraform-tests.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp "$ROOT"/observability-*.tf "$WORK"/
cp "$ROOT"/observability/tests/harness/*.tf "$WORK"/
mkdir -p "$WORK/observability" "$WORK/tests"
cp -R "$ROOT/observability/kql" "$WORK/observability/"
cp "$ROOT/observability/ALERTS.md" "$WORK/observability/"
cp "$ROOT"/observability/tests/*.tftest.hcl "$WORK/tests/"

terraform -chdir="$WORK" init -backend=false -input=false >/dev/null
terraform -chdir="$WORK" test
