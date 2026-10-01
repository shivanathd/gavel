#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }

# F10 REQ-AGT-001 acceptance. Test methods required in Gavel_AgentforceGate_Test:
#   AS-10.1 injectionBlocked
#   AS-10.2 destructiveHeld
#   AS-10.3 providerDownFailsClosed
sf apex run test --tests "Gavel_AgentforceGate_Test.injectionBlocked,Gavel_AgentforceGate_Test.destructiveHeld,Gavel_AgentforceGate_Test.providerDownFailsClosed" --target-org "$ORG" --result-format json --wait 20 > /tmp/acc_F10.json || exit 1
[ "$(jq -r '.result.summary.outcome' /tmp/acc_F10.json)" = "Passed" ]
