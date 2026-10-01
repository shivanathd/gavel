---
document_type: implementation_plan
project_id: GAVEL
version: 1.0.0
last_updated: 2026-10-01
status: draft
---

# Gavel v1: Implementation Plan

Order: Critical first. Every task has a Verify step that maps to `evals/tasks/T{N}.sh`. Commit the spec before any code (meta-law).

## Phase 0: Repo foundation

### T0.1 Scaffold repo and packages
Create `sfdx-project.json` with 8 package directories and dependencies, `config/project-scratch-def.json` (Knowledge, Platform Cache enabled), LICENSE (Apache 2.0), NOTICE, SECURITY.md, CONTRIBUTING.md, CLAUDE.md, AGENTS.md.
**Traces:** F13, F14, ADR-001, ADR-018
**Verify:** `evals/tasks/T0.1.sh` checks all files exist and `sfdx-project.json` lists 8 packages with no namespace.
**Commit:** `chore: scaffold gavel repo and package layout`

### T0.2 CI pipeline
GitHub Actions: scratch org create, deploy, Apex tests with coverage, Code Analyzer, LWC Jest, `evals/run-all.sh --offline`, egress docs check.
**Traces:** F13 PKG-001.4
**Verify:** `evals/tasks/T0.2.sh` checks the workflow file has all six jobs.
**Commit:** `ci: add scratch org pipeline`

## Phase 1: Core (Critical)

### T1.1 CMDT types and validator
All `Gavel_*__mdt` types, `Gavel_DefinitionValidator`, canonical hash, `scripts/hash-definitions.js`.
**Traces:** F2
**Verify:** `evals/tasks/T1.1.sh` runs `Gavel_DefinitionValidator_Test`.
**Commit:** `feat(core): decision definitions and validator`

### T1.2 Provider interface, mock and TypeSafe provider
**Traces:** F1, ADR-002, ADR-003, ADR-005
**Verify:** `evals/tasks/T1.2.sh` runs provider tests and the log-leak scan.
**Commit:** `feat(core): judgment provider interface and TypeSafe provider`

### T1.3 State builder and redaction
**Traces:** F3, ADR-006
**Verify:** `evals/tasks/T1.3.sh` runs state builder tests including the 200-string PII fixture.
**Commit:** `feat(core): state builder with allowlist and redaction`

### T1.4 Policy engine
**Traces:** F5, ADR-008
**Verify:** `evals/tasks/T1.4.sh` runs the truth-table tests with 100% branch coverage.
**Commit:** `feat(core): policy engine`

### T1.5 Ledger
Object, immutability trigger, hash chain, verifier, retention batch, fallback platform event, record LWC.
**Traces:** F6, ADR-010
**Verify:** `evals/tasks/T1.5.sh` runs ledger tests.
**Commit:** `feat(core): decision ledger`

### T1.6 Ops guardrails
Budget, breaker, cache, retries, alerts.
**Traces:** F9, ADR-013
**Verify:** `evals/tasks/T1.6.sh` runs guardrail tests.
**Commit:** `feat(core): budgets, circuit breaker and cache`

## Phase 2: Flow runtime

### T2.1 Invocables and Queueable runner
**Traces:** F4, ADR-007
**Verify:** `evals/tasks/T2.1.sh` runs the bulk 200-record test.
**Commit:** `feat(flow): invocable actions and async runner`

### T2.2 Apply Outcome and review records
**Traces:** F4 FLOW-001.3, F5 POL-001.9
**Verify:** `evals/tasks/T2.2.sh`
**Commit:** `feat(flow): apply outcome and review queue`

## Phase 3: Shadow and calibration

### T3.1 Shadow mode, baseline capture, disagreement report
**Traces:** F7, ADR-011
**Verify:** `evals/tasks/T3.1.sh`
**Commit:** `feat(shadow): baseline capture and disagreement report`

### T3.2 Feedback capture and calibration
**Traces:** F8, ADR-012
**Verify:** `evals/tasks/T3.2.sh` runs the calibration math tests (Wilson fixture).
**Commit:** `feat(calibrate): feedback and threshold recommendations`

### T3.3 Promotion gate
**Traces:** F7 SHAD-001.5, ADR-003
**Verify:** `evals/tasks/T3.3.sh`
**Commit:** `feat(shadow): calibration-gated promotion`

## Phase 4: Admin app

### T4.1 Lightning app, Decision Console, Ledger viewer, Calibration dashboard
**Traces:** F2 DEF-001.6, F6 LEDG-001.6, F7, F8
**Verify:** `evals/tasks/T4.1.sh` runs LWC Jest.
**Commit:** `feat(admin): console, ledger viewer, calibration dashboard`

## Phase 5: Packs

### T5.1 Agentforce Gate pack
**Traces:** F10, ADR-014
**Verify:** `evals/tasks/T5.1.sh`
**Commit:** `feat(pack-agentforce-gate): input screen, action risk, guarded wrapper`

### T5.2 Service pack
**Traces:** F11, ADR-015
**Verify:** `evals/tasks/T5.2.sh`
**Commit:** `feat(pack-service): triage, urgency, KB coverage, closure, reply check`

### T5.3 Sales and Marketing pack
**Traces:** F12, ADR-016
**Verify:** `evals/tasks/T5.3.sh`
**Commit:** `feat(pack-sales-marketing): lead quality, reply intent, opt-out, persona, stage evidence`

## Phase 6: Ship

### T6.1 deploy.sh and scratch.sh
**Traces:** F13, ADR-017
**Verify:** `evals/tasks/T6.1.sh` checks `--help`, pack validation and exit codes.
**Commit:** `feat: source deploy scripts`

### T6.2 Docs site, egress page, pack READMEs, ADR copies
**Traces:** F14
**Verify:** `evals/tasks/T6.2.sh` runs the egress check and ADR lint.
**Commit:** `docs: v1 documentation`

### T6.3 Release: package versions and install links
**Human gate:** OQ-1, OQ-2 and OQ-3 resolved. Maintainer runs the live evals (red team, opt-out, live contract test).
**Verify:** `evals/run-all.sh --live` reports SHIP.
**Commit:** `release: v1.0.0`

## Convergence

`evals/run-all.sh` runs task, acceptance and holdout layers. SHIP when all tasks pass, all acceptance pass and holdout satisfaction is 90% or more. LOOP when any fail with fewer than 3 iterations. ESCALATE after 3 failed iterations or any Critical security or compliance failure.
