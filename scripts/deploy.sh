#!/usr/bin/env bash
# Gavel source deploy (PKG-001.2, ADR-017). Deploys the same package directories, in the same order and with
# the same post-install defaults as the unlocked packages: no flow is activated and egress stays off.
#
#   ./scripts/deploy.sh --org gavel-scratch --packs service,sales-marketing,agentforce-gate --sample-data
#
# Exit codes: 0 ok, 1 deploy failure, 2 bad arguments.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE=(gavel-core gavel-flow gavel-shadow gavel-calibrate gavel-admin)
VALID_PACKS=(agentforce-gate service sales-marketing)
# Packs deploy after the base packages, in dependency order.
PACK_ORDER=(agentforce-gate service sales-marketing)
BASE_PERMSETS=(Gavel_Admin Gavel_Runtime Gavel_Callout)

usage() {
  cat <<'EOF'
Usage: scripts/deploy.sh --org <alias|username> [--packs a,b,c] [--sample-data] [--dry-run] [--help]

Deploys Gavel as source, in package order:
  gavel-core, gavel-flow, gavel-shadow, gavel-calibrate, gavel-admin, then the selected packs.

Options:
  --org          Target org alias or username (required).
  --packs        Comma-separated packs: agentforce-gate, service, sales-marketing. Default: none.
  --sample-data  Load sample data for the selected packs (service: 200 Cases, sales-marketing: 50 Leads).
  --dry-run      Print the plan without changing the org.
  --help         Show this help.

After deploy: permission sets are assigned to the running user, no flow is active, and
Gavel_Ops_Config__mdt.Egress_Enabled__c is false. Turn egress on only after reviewing
docs/guides/data-leaving-your-org.md.

Exit codes: 0 ok, 1 deploy failure, 2 bad arguments.
EOF
}

ORG=""
PACKS=""
SAMPLE=0
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --org) ORG="${2:-}"; shift 2 ;;
    --org=*) ORG="${1#*=}"; shift ;;
    --packs) PACKS="${2:-}"; shift 2 ;;
    --packs=*) PACKS="${1#*=}"; shift ;;
    --sample-data) SAMPLE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "deploy.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# Validate packs before touching anything.
SELECTED=()
if [ -n "$PACKS" ]; then
  IFS=',' read -r -a REQUESTED <<< "$PACKS"
  for p in "${REQUESTED[@]}"; do
    p="$(echo "$p" | tr -d '[:space:]')"
    [ -z "$p" ] && continue
    ok=0
    for v in "${VALID_PACKS[@]}"; do [ "$p" = "$v" ] && ok=1; done
    if [ $ok -eq 0 ]; then
      echo "deploy.sh: unknown pack '$p'. Valid packs: ${VALID_PACKS[*]}" >&2
      exit 2
    fi
    SELECTED+=("$p")
  done
fi
if [ -z "$ORG" ]; then
  echo "deploy.sh: --org is required" >&2
  usage >&2
  exit 2
fi

ORDERED=()
for p in "${PACK_ORDER[@]}"; do
  for s in "${SELECTED[@]+"${SELECTED[@]}"}"; do [ "$p" = "$s" ] && ORDERED+=("$p"); done
done
DIRS=("${BASE[@]}")
for p in "${ORDERED[@]+"${ORDERED[@]}"}"; do DIRS+=("gavel-pack-$p"); done
PERMSETS=("${BASE_PERMSETS[@]}")
for p in "${ORDERED[@]+"${ORDERED[@]}"}"; do
  case "$p" in
    agentforce-gate) PERMSETS+=(Gavel_Agentforce_Gate) ;;
    service) PERMSETS+=(Gavel_Service_Pack) ;;
    sales-marketing) PERMSETS+=(Gavel_Sales_Marketing_Pack) ;;
  esac
done

echo "Gavel deploy plan for org '$ORG':"
for d in "${DIRS[@]}"; do echo "  deploy  packages/$d"; done
for ps in "${PERMSETS[@]}"; do echo "  assign  $ps"; done
[ $SAMPLE -eq 1 ] && echo "  load    sample data for: ${ORDERED[*]+"${ORDERED[*]}"}"
if [ $DRY -eq 1 ]; then
  echo "Dry run: nothing changed."
  exit 0
fi

for tool in sf jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "deploy.sh: '$tool' is required" >&2; exit 2; }
done

LOG="$(mktemp -t gavel-deploy.XXXXXX)"
trap 'rm -f "$LOG"' EXIT

for d in "${DIRS[@]}"; do
  echo "Deploying packages/$d ..."
  sf project deploy start --source-dir "$ROOT/packages/$d" --target-org "$ORG" --wait 60 --json > "$LOG" 2>/dev/null
  status="$(jq -r '.status // 1' "$LOG" 2>/dev/null)"
  if [ "$status" != "0" ]; then
    echo "deploy.sh: deploy of packages/$d failed:" >&2
    jq -r '(.result.details.componentFailures // []) | (if type == "array" then . else [.] end) | .[] | "  \(.componentType) \(.fullName): \(.problem)"' "$LOG" >&2 2>/dev/null
    jq -r '.message // empty' "$LOG" >&2 2>/dev/null
    exit 1
  fi
done

for ps in "${PERMSETS[@]}"; do
  if ! out="$(sf org assign permset --name "$ps" --target-org "$ORG" --json 2>/dev/null)"; then
    if ! echo "$out" | grep -qi "duplicate\|already"; then
      echo "deploy.sh: could not assign $ps" >&2
      echo "$out" | jq -r '.message // empty' >&2 2>/dev/null
      exit 1
    fi
  fi
  echo "Assigned $ps"
done

egress="$(sf data query -q "SELECT Egress_Enabled__c FROM Gavel_Ops_Config__mdt WHERE DeveloperName = 'Default'" --target-org "$ORG" --json 2>/dev/null | jq -r '.result.records[0].Egress_Enabled__c // "missing"')"
echo "Egress_Enabled__c = $egress (no data leaves the org until an admin turns it on)"

if [ $SAMPLE -eq 1 ]; then
  for p in "${ORDERED[@]+"${ORDERED[@]}"}"; do
    case "$p" in
      service)
        have="$(sf data query -q "SELECT COUNT() FROM Case WHERE Gavel_Sample_Label__c != null" --target-org "$ORG" --json 2>/dev/null | jq -r '.result.totalSize // 0')"
        if [ "${have:-0}" -ge 200 ]; then
          echo "Sample Cases already loaded ($have)."
        else
          sf data import tree --files "$ROOT/packages/gavel-pack-service/data/sample-cases.json" --target-org "$ORG" --json > "$LOG" 2>/dev/null
          [ "$(jq -r '.status // 1' "$LOG")" = "0" ] || { echo "deploy.sh: sample Cases failed to load" >&2; jq -r '.message // empty' "$LOG" >&2; exit 1; }
          echo "Loaded 200 sample Cases."
        fi
        ;;
      sales-marketing)
        have="$(sf data query -q "SELECT COUNT() FROM Lead WHERE FirstName = 'Gavel' AND LastName LIKE 'Sample%'" --target-org "$ORG" --json 2>/dev/null | jq -r '.result.totalSize // 0')"
        if [ "${have:-0}" -ge 50 ]; then
          echo "Sample Leads already loaded ($have)."
        else
          sf data import tree --files "$ROOT/packages/gavel-pack-sales-marketing/data/sample-leads.json" --target-org "$ORG" --json > "$LOG" 2>/dev/null
          [ "$(jq -r '.status // 1' "$LOG")" = "0" ] || { echo "deploy.sh: sample Leads failed to load" >&2; jq -r '.message // empty' "$LOG" >&2; exit 1; }
          echo "Loaded 50 sample Leads."
        fi
        ;;
    esac
  done
fi

echo "Gavel deployed to '$ORG'. No flow is active. Next: review docs/guides/data-leaving-your-org.md, then turn egress on."
exit 0
