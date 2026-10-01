#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }

# F6 REQ-LEDG-001 acceptance. Test methods required in Gavel_Ledger_Test:
#   AS-6.1 errorStillLedgered
#   AS-6.2 adminCannotEdit
#   AS-6.3 tamperDetected
sf apex run test --tests "Gavel_Ledger_Test.errorStillLedgered,Gavel_Ledger_Test.adminCannotEdit,Gavel_Ledger_Test.tamperDetected" --target-org "$ORG" --result-format json --wait 20 > /tmp/acc_F6.json || exit 1
[ "$(jq -r '.result.summary.outcome' /tmp/acc_F6.json)" = "Passed" ]
