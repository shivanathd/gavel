#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }
# T0.2: CI pipeline
wf="$ROOT/.github/workflows/ci.yml"; [ -f "$wf" ] || exit 1
for j in scratch deploy apex-tests code-analyzer lwc-jest evals-offline egress-check; do grep -q "$j" "$wf" || { echo "missing job $j"; exit 1; }; done
