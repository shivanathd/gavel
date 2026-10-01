#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }

# F1 REQ-CORE-001 acceptance. Test methods required in Gavel_TypeSafeProvider_Test:
#   AS-1.1 validChoiceResponse
#   AS-1.2 unknownOptionIsContractMismatch
#   AS-1.3 keyNeverLeaks
#   AS-1.4 aliasBlockedWhenLive
sf apex run test --tests "Gavel_TypeSafeProvider_Test.validChoiceResponse,Gavel_TypeSafeProvider_Test.unknownOptionIsContractMismatch,Gavel_TypeSafeProvider_Test.keyNeverLeaks,Gavel_TypeSafeProvider_Test.aliasBlockedWhenLive" --target-org "$ORG" --result-format json --wait 20 > /tmp/acc_F1.json || exit 1
[ "$(jq -r '.result.summary.outcome' /tmp/acc_F1.json)" = "Passed" ]
