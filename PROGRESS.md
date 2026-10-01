# Gavel v1 build progress

Spec: `docs/spec/active/2026-10-01-gavel-v1/`. Evals: `docs/spec/active/2026-10-01-gavel-v1/evals/`.

## Status log
- 2026-10-01 spec committed (ac4df51); work on branch `gavel-v1`.
- Phase 0: T0.1 PASS (a3d6d11), T0.2 PASS (2176dfe). No feature acceptance script maps to phase 0.
- Phase 1 (T1.1-T1.6, core): ALL PASS in gavel-scratch, committed 0654dc8..2deb904. Acceptance F1 4/4, F2 3/3, F3 4/4, F5 4/4, F6 3/3, F9 2/2: PASS.
- Phase 2 (T2.1-T2.2, flow): ALL PASS in gavel-scratch, committed. Acceptance F4 3/3: PASS.
- Phase 3 (T3.1-T3.3, shadow + calibrate): ALL PASS in gavel-scratch, committed. Acceptance F7 2/2, F8 3/3: PASS.
- Phase 4 (T4.1, admin): PASS (LWC Jest 9/9; admin package deployed, Gavel_AdminController_Test 1/1), committed. No acceptance script maps to phase 4.
- Phase 5 (T5.1-T5.3, packs): ALL PASS in gavel-scratch, committed (T5.3 on attempt 3, see B12). Acceptance F10 3/3, F11 3/3, F12 3/3: PASS.
- Phase 6 (T6.1-T6.2): T6.1 PASS, T6.2 PASS, committed. Acceptance F13 PASS (deploy.sh --packs service --sample-data into gavel-scratch, 202 Cases, egress false), F14 PASS. T6.3 not attempted (human gate: OQ-1/2/3 + live key).

## Order of work when the org exists
1. `sf org login web --alias devhub --set-default-dev-hub`
2. `sf org create scratch -d -a gavel-scratch -f config/project-scratch-def.json -v devhub`
3. For each task T1.1 ... T5.3: deploy its package dir, run `evals/tasks/T{N}.sh`, fix, commit with the plan message. Then T4.1/T6.1/T6.2 commits in order, then `evals/acceptance/*.sh`.

## BLOCKERS
- B0 RESOLVED 2026-10-01: Developer Edition Dev Hub created (alias devhub), Dev Hub enabled via DevHubSettings.enableScratchOrgManagementPref, gavel-scratch created (00DcU00000ICwUtUAL). This session cannot reach the macOS Keychain, so every sf call runs with SF_USE_GENERIC_UNIX_KEYCHAIN=true (key in ~/.sfdx/key.json, 600).
- B0 (environment): no Dev Hub authenticated on this machine (`sf org list` empty, `devhub` alias missing; browser login timed out). `gavel-scratch` cannot be created, so every eval that runs Apex tests (T1.1-T5.3, F1-F13) cannot pass yet. Code for those tasks is written but uncommitted until verified. Unblock: `sf org login web --alias devhub --set-default-dev-hub`.
- B1 (spec conflict, F5): POL-001.4 says Noul values below Review_At ESCALATE, but AGT spec "block at 0.75, review at 0.25" means below 0.25 passes, and opt-out would escalate every normal reply. Chosen (most conservative reading satisfying POL-001.3/.4 and pack numbers): a = action-side probability; a >= Auto_Accept -> AUTO; a <= min(Review_At, 1 - Auto_Accept) -> AUTO with no action; a >= Review_At -> REVIEW; else ESCALATE.
- B2 (spec ambiguity, F5): policy-contract row order puts margin_below_min before the Review_At band, but the edge case "0.5/0.5 -> ESCALATE if review_at > 0.5" requires ESCALATE first. Chosen: top < Review_At -> ESCALATE before margin check; ties never AUTO.
- B3 (spec conflict, F4/F6): LEDG-001.2 insert-only vs FLOW-001.2 "returns the pending ledger ID" and AS-4.1 "200 ledger entries" for 200 async records (exactly one per run). Chosen: the async invocable inserts one PENDING entry; the queueable finalizes that same row once (PENDING -> final) inside Gavel_Ledger; the trigger allows no other update for anyone. The hash chain is computed at finalization, so tampering after that is detectable.
- B4 (platform constraint, F9): Platform Cache keys must be alphanumeric, so `gavel.j.<hex>` / `gavel.breaker` become `gavelj<hex>` / `gavelbreaker`.
- B5 (spec gap, F14): DECISIONS.md has no Alternatives for ADR-015 and ADR-017, but AS-14.2 requires the heading. Authored short Alternatives sections in docs/adr/0015 and 0017, marked as added during implementation.
- B6 (platform, F10): GenAiFunction agent-action metadata is not shipped: it needs an Agentforce-enabled org, which a plain scratch org is not. The four Apex invocables are the agent actions; admins register them (docs/packs/agentforce-gate.md). Matches F13 edge case "agent actions deploy but unused".
- B7 (interpretation, F10): Gavel_Guarded_Action in Shadow observes only (runs the wrapped flow and ledgers the risk), consistent with ADR-015 "nothing changes until you say so"; it enforces (holds and creates a review) only when Live. The wrapper flow ships inactive.
- B8 (interpretation, F4/F5): actions on the sync "Run Decision" action are deferred to "Apply Outcome" (contract lists them separately); the async queueable and the Apex API apply Live AUTO actions inline, because nothing runs after them. Every application is recorded in insert-only Gavel_Action_Log__c, since ledger rows cannot be updated.
- B9 (interpretation, F1/F12): "ERROR routes to review" (F1) and "opt-out provider error creates a REVIEW record" (F12): on Live definitions ERROR and provider-availability SKIPs (circuit_open, budget_exceeded) create a Gavel_Review__c. Shadow creates no work items.
- B10 (known limitation, F10): Gavel_GuardedAction starts the wrapped subflow after the risk run has written the ledger, so a wrapped subflow that makes a callout fails with "uncommitted work pending". Documented; wrapped flows should not call out synchronously.
- B11 (platform, F7): Gavel_ModeChange deploys Mode__c through Metadata.Operations.enqueueDeployment, which needs the org setting "Deploy Metadata from Non-Certified Package Versions via Apex". Without it, change the mode with a CMDT deploy; the promotion gate still applies through Gavel_PromotionGate.canPromote.
- Open risks to confirm in gavel-scratch (no org yet): EmailMessageRelation FromAddress inserts (sales pack tests), Case.Type accepting non-default values (calibration tests), static test state surviving into queueables/batches at Test.stopTest().
- B12 (finding, F12): AUTO actions run in user mode (least privilege). In a fresh org the admin had no FLS on Contact/Lead.HasOptedOutOfEmail, so the opt-out update was refused and logged (fail closed). Kept user mode; Gavel_Sales_Marketing_Pack now grants edit on HasOptedOutOfEmail (Contact, Lead) without View All, deploy.sh assigns it, and action logs now record the DML error message. T5.3 needed 3 attempts (fixture sender relation, then this FLS gap).
