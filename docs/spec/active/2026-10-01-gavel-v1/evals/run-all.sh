#!/usr/bin/env bash
# Gavel convergence runner. Usage: ./evals/run-all.sh [--offline|--live]
set -uo pipefail
E="$(cd "$(dirname "$0")" && pwd)"; R="$E/results"; mkdir -p "$R"
MODE="${1:---offline}"; [ "$MODE" = "--live" ] && export GAVEL_LIVE=1
tp=0; tt=0; ap=0; at=0; hs=0; hp=0; hn=0; hm=0
for s in "$E"/tasks/*.sh; do n=$(basename "$s" .sh); tt=$((tt+1)); bash "$s" >"$R/$n.log" 2>&1; rc=$?; [ $rc -eq 0 ] && tp=$((tp+1)); [ $rc -eq 3 ] && { tt=$((tt-1)); echo "$n MANUAL"; continue; }; echo "$n rc=$rc"; done
for s in "$E"/acceptance/*.sh; do n=$(basename "$s" .sh); at=$((at+1)); bash "$s" >"$R/acc_$n.log" 2>&1 && ap=$((ap+1)); done
for s in "$E"/holdout/*.sh; do r=$(bash "$s" 2>/dev/null | tail -1); case "$r" in SATISFIED) hs=$((hs+1));; PARTIAL) hp=$((hp+1));; MANUAL_REVIEW) hm=$((hm+1));; *) hn=$((hn+1));; esac; done
ht=$((hs+hp+hn)); sat=$(awk -v s=$hs -v t=$ht 'BEGIN{ if(t==0) print 0; else printf "%.2f", s/t }')
verdict=LOOP
if [ $tp -eq $tt ] && [ $ap -eq $at ] && awk -v x="$sat" 'BEGIN{exit !(x>=0.9)}' && [ $hm -eq 0 ]; then verdict=SHIP; fi
it=$(( $(ls "$R"/convergence-*.json 2>/dev/null | wc -l) + 1 )); [ $it -gt 3 ] && [ "$verdict" != SHIP ] && verdict=ESCALATE
cat > "$R/convergence-$it.json" <<J
{"iteration":$it,"mode":"$MODE","tasks":{"pass":$tp,"total":$tt},"acceptance":{"pass":$ap,"total":$at},"holdout":{"satisfied":$hs,"partial":$hp,"not_satisfied":$hn,"manual_pending":$hm,"satisfaction":$sat},"verdict":"$verdict"}
J
cp "$R/convergence-$it.json" "$R/convergence-report.json"; cat "$R/convergence-report.json"
[ "$verdict" = SHIP ]
