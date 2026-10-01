#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }

# F3 REQ-STATE-001 acceptance. Test methods required in Gavel_StateBuilder_Test:
#   AS-3.1 onlyAllowlistedFields
#   AS-3.2 cardNumberRedacted
#   AS-3.3 flsRespected
#   AS-3.4 killSwitch
sf apex run test --tests "Gavel_StateBuilder_Test.onlyAllowlistedFields,Gavel_StateBuilder_Test.cardNumberRedacted,Gavel_StateBuilder_Test.flsRespected,Gavel_StateBuilder_Test.killSwitch" --target-org "$ORG" --result-format json --wait 20 > /tmp/acc_F3.json || exit 1
[ "$(jq -r '.result.summary.outcome' /tmp/acc_F3.json)" = "Passed" ]
