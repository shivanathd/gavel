#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }
# T6.1: Deploy scripts
"$ROOT/scripts/deploy.sh" --help >/dev/null || exit 1
"$ROOT/scripts/deploy.sh" --org none --packs bogus >/dev/null 2>&1; [ $? -eq 2 ] || { echo "unknown pack must exit 2"; exit 1; }
