#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }

# F12 REQ-SM-001 acceptance. Test methods required in Gavel_SalesMarketingPack_Test:
#   AS-12.1 hiddenOptOut
#   AS-12.2 optOutNeverReversed
#   AS-12.3 junkLeadShadow
sf apex run test --tests "Gavel_SalesMarketingPack_Test.hiddenOptOut,Gavel_SalesMarketingPack_Test.optOutNeverReversed,Gavel_SalesMarketingPack_Test.junkLeadShadow" --target-org "$ORG" --result-format json --wait 20 > /tmp/acc_F12.json || exit 1
[ "$(jq -r '.result.summary.outcome' /tmp/acc_F12.json)" = "Passed" ]
