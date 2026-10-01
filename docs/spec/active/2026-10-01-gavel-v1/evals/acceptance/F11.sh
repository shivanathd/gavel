#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }

# F11 REQ-SVC-001 acceptance. Test methods required in Gavel_ServicePack_Test:
#   AS-11.1 installsInShadow
#   AS-11.2 kbGapCreated
#   AS-11.3 urgencyIndependentOfPriority
sf apex run test --tests "Gavel_ServicePack_Test.installsInShadow,Gavel_ServicePack_Test.kbGapCreated,Gavel_ServicePack_Test.urgencyIndependentOfPriority" --target-org "$ORG" --result-format json --wait 20 > /tmp/acc_F11.json || exit 1
[ "$(jq -r '.result.summary.outcome' /tmp/acc_F11.json)" = "Passed" ]
