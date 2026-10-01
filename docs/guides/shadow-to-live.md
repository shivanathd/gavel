# From Shadow to Live

Gavel never changes a record until you promote a definition, and promotion is gated by calibration (ADR-011).

1. **Shadow.** The definition runs and is ledgered, and actions are suppressed (`action_suppressed_shadow`). Turn egress on only after reading [Data leaving your org](data-leaving-your-org.md).
2. **Baseline.** Map what your current process decides (`Gavel_Baseline_Map__mdt`, for example `Case.Type`). `Gavel_BaselineCapture` (hourly) records it after `Baseline_Delay_Hours__c` (default 24). Missing baselines are excluded, unmapped values count as disagreement, and values Gavel set itself are excluded as circular.
3. **Compare.** The Gavel Calibration tab shows agreement by confidence band, the top disagreement pairs, and how many runs would have been AUTO. Agreement is not accuracy: a disagreement means "look here".
4. **Label.** Captured baselines, reviewer resolutions (Confirmed or Corrected) and human overrides within 72 hours become labels. Edits by integration users, automated processes and Gavel itself are not labels.
5. **Calibrate.** Run calibration. The report shows a reliability table, precision and coverage at thresholds 0.50 to 0.95, the recommended `Auto_Accept__c` that meets `Target_Precision__c` (default 0.95) with the most coverage, and a Wilson 95% interval. Gavel never applies it for you.
6. **Apply.** Change the policy, bump `Version__c`, run `node scripts/hash-definitions.js --write`, deploy. A new version needs a fresh calibration.
7. **Promote.** Click "Request Live" in the Decision Console. The gate requires a pinned model and a report for the current version, from the last 14 days, with at least 200 labeled entries and a threshold that meets the target. Otherwise it explains what is missing.
8. **Watch.** Alerts (`Gavel_Alert__e`) fire on error rate above 5% over 15 minutes, ESCALATE rate, breaker open and budget at 80%. Demote with "Back to Shadow" at any time.
