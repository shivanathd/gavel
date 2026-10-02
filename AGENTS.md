# AGENTS.md

Guidance for AI coding agents working in this repo. `CLAUDE.md` carries the same rules.

## Read first
- `docs/spec/active/2026-10-01-gavel-v1/REQUIREMENTS.md` (control plane), `DECISIONS.md`, `contracts/`.
- `SECURITY.md` before touching providers, state, ledger or logging.
- Do not read `docs/spec/active/2026-10-01-gavel-v1/SCENARIOS.md` or `evals/holdout/`: they are hidden from implementers.

## Layout
Eight package directories under `packages/`, deployed in this order: core, flow, shadow, calibrate, admin, then packs. A package may only reference metadata from packages it depends on (see `sfdx-project.json`). Where a lower package needs an object from a higher one, use dynamic Apex (`Schema.getGlobalDescribe()`, `Database.query`).

## Apex rules
- Prefix everything `Gavel_`. No namespace.
- `with sharing`; state reads `WITH USER_MODE` + `Security.stripInaccessible`.
- Never `System.debug` state, payloads, headers or callout exception messages.
- No DML before a callout in the same transaction. The runtime does all callouts first, then DML.
- Invocables never throw. Errors are outcomes.
- Definitions are loaded through `Gavel_DefinitionRepo`; tests register in-memory definitions with `Gavel_TestFactory`.
- The ledger is written only through `Gavel_Ledger`.

## Verify
Each plan task has `docs/spec/active/2026-10-01-gavel-v1/evals/tasks/T{N}.sh`. Run it against the `gavel-scratch` org (`GAVEL_ORG` overrides) before committing with the plan's commit message.
