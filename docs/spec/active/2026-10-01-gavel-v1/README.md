---
document_type: spec_index
project_id: GAVEL
version: 1.0.0
last_updated: 2026-10-01
status: draft
type: System
author: Shivanath Devinarayanan
---

# Gavel v1 Spec

| Doc | Purpose |
|---|---|
| [REQUIREMENTS.md](REQUIREMENTS.md) | Control plane: 14 features, RFC 2119 requirements, acceptance scenarios, null contract, open questions |
| [SCENARIOS.md](SCENARIOS.md) | 10 holdout journeys (hidden from the implementer) |
| [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) | 20 tasks in 7 phases, each with a verify script and commit message |
| [DECISIONS.md](DECISIONS.md) | ADR-000 to ADR-018 |
| [SYSTEM_MAP.yaml](SYSTEM_MAP.yaml) | Packages, dependencies, boundaries, customer components touched |
| [contracts/](contracts/) | Provider, state, policy, ledger, flow contracts |
| [evals/](evals/) | Manifest, task/acceptance/holdout scripts, convergence runner |

## Feature index

| ID | Feature | Class | Priority | Package |
|---|---|---|---|---|
| F1 | Provider client and contract | Security | Critical | core |
| F2 | Decision definitions (CMDT) | Functional | Critical | core |
| F3 | State builder, allowlist, redaction | Compliance | Critical | core |
| F4 | Flow invocables and async runner | Functional | Critical | flow |
| F5 | Policy engine | Security | Critical | core |
| F6 | Decision ledger | Compliance | Critical | core |
| F7 | Shadow mode and disagreement report | Operational | High | shadow |
| F8 | Feedback and calibration | Operational | High | calibrate |
| F9 | Budgets, breaker, cache, retries | Operational | High | core |
| F10 | Agentforce Gate pack | Security | High | pack-agentforce-gate |
| F11 | Service pack | Functional | High | pack-service |
| F12 | Sales and Marketing pack | Compliance | High | pack-sales-marketing |
| F13 | Packaging and deployment | Operational | Critical | repo |
| F14 | Docs, ADRs, contributor experience | Documentation | Medium | repo |

## Critical open questions (gate public release, not the build)

- OQ-1: TypeSafe data retention and DPA
- OQ-2: Full `/v1/systemone` schema and versioning policy
- OQ-3: IP clearance for a personal open-source project alongside your Asymbl role

## Run the evals

```bash
./docs/spec/active/2026-10-01-gavel-v1/evals/run-all.sh --offline   # CI, mock provider
./docs/spec/active/2026-10-01-gavel-v1/evals/run-all.sh --live      # maintainer, live key
```
