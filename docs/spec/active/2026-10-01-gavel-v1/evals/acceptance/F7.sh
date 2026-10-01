#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }

# F7 REQ-SHAD-001 acceptance. Test methods required in Gavel_Shadow_Test:
#   AS-7.1 agreementReport
#   AS-7.2 promotionBlocked
sf apex run test --tests "Gavel_Shadow_Test.agreementReport,Gavel_Shadow_Test.promotionBlocked" --target-org "$ORG" --result-format json --wait 20 > /tmp/acc_F7.json || exit 1
[ "$(jq -r '.result.summary.outcome' /tmp/acc_F7.json)" = "Passed" ]
