#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }
# Holdout S6: Daily budget protects the bill
# Prints SATISFIED | PARTIAL | NOT_SATISFIED | MANUAL_REVIEW
sf apex run test --class-names Gavel_Holdout_Budget_Test --target-org "$ORG" --wait 20 >/dev/null && echo SATISFIED || echo NOT_SATISFIED
