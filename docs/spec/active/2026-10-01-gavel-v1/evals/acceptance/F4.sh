#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }

# F4 REQ-FLOW-001 acceptance. Test methods required in Gavel_RunDecision_Test:
#   AS-4.1 bulk200Async
#   AS-4.2 screenFlowSync
#   AS-4.3 errorSurfacesAsOutcome
sf apex run test --tests "Gavel_RunDecision_Test.bulk200Async,Gavel_RunDecision_Test.screenFlowSync,Gavel_RunDecision_Test.errorSurfacesAsOutcome" --target-org "$ORG" --result-format json --wait 20 > /tmp/acc_F4.json || exit 1
[ "$(jq -r '.result.summary.outcome' /tmp/acc_F4.json)" = "Passed" ]
