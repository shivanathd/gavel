#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }
# Holdout S3: Hidden unsubscribe caught
# Prints SATISFIED | PARTIAL | NOT_SATISFIED | MANUAL_REVIEW
[ "${GAVEL_LIVE:-0}" = "1" ] || { echo MANUAL_REVIEW; exit 0; }
# Live journey: see SCENARIOS.md S3. Maintainer records SATISFIED|PARTIAL|NOT_SATISFIED
read -r -p "S3 result: " r; echo "$r"
