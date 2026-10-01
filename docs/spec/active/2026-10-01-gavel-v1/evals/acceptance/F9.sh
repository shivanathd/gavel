#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }

# F9 REQ-OPS-001 acceptance. Test methods required in Gavel_Guardrails_Test:
#   AS-9.1 budgetStopsCalls
#   AS-9.2 breakerOpensAndCloses
sf apex run test --tests "Gavel_Guardrails_Test.budgetStopsCalls,Gavel_Guardrails_Test.breakerOpensAndCloses" --target-org "$ORG" --result-format json --wait 20 > /tmp/acc_F9.json || exit 1
[ "$(jq -r '.result.summary.outcome' /tmp/acc_F9.json)" = "Passed" ]
