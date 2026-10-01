#!/usr/bin/env bash
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ORG="${GAVEL_ORG:-gavel-scratch}"
apex_test(){ sf apex run test --class-names "$1" --target-org "$ORG" --code-coverage --result-format json --wait 20 > /tmp/gavel_$$.json || return 1; [ "$(jq -r '.result.summary.outcome' /tmp/gavel_$$.json)" = "Passed" ]; }
# T1.2: Provider
apex_test Gavel_TypeSafeProvider_Test,Gavel_MockProvider_Test
! grep -rniE "bearer [a-z0-9_-]{16,}" "$ROOT/force-app" "$ROOT/packages" 2>/dev/null || { echo "possible key in source"; exit 1; }
