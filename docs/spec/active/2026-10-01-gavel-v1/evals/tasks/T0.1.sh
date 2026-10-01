#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }
# T0.1: Scaffold repo and packages
for f in sfdx-project.json LICENSE NOTICE SECURITY.md CONTRIBUTING.md CLAUDE.md AGENTS.md config/project-scratch-def.json; do [ -f "$ROOT/$f" ] || { echo "missing $f"; exit 1; }; done
n=$(jq '.packageDirectories | length' "$ROOT/sfdx-project.json"); [ "$n" -eq 8 ] || { echo "expected 8 packages, got $n"; exit 1; }
[ "$(jq -r '.namespace // ""' "$ROOT/sfdx-project.json")" = "" ] || { echo "namespace must be empty"; exit 1; }
