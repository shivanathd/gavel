# Contributing to Gavel

Thanks for helping. Gavel is spec-driven: the control plane lives in `docs/spec/active/2026-10-01-gavel-v1/`. Read `REQUIREMENTS.md`, `DECISIONS.md` and the relevant contract before changing behavior.

## Ground rules

- Sign off every commit (DCO): `git commit -s`. By signing off you certify the [Developer Certificate of Origin](https://developercertificate.org/).
- Conventional commit messages: `feat(core): ...`, `fix(flow): ...`, `docs: ...`.
- No accuracy claims without a linked, reproducible eval.
- Follow `SECURITY.md`. A change that logs state, stores a key or fails open will not be merged.

## Dev loop

```bash
./scripts/scratch.sh gavel-scratch
./scripts/deploy.sh --org gavel-scratch --packs service,sales-marketing,agentforce-gate --sample-data
./docs/spec/active/2026-10-01-gavel-v1/evals/run-all.sh --offline
npm install && npm run test:unit
```

## Changing a definition

Definitions are Custom Metadata. If you change a question, option, state field, policy or action map:

1. Bump `Version__c` on the `Gavel_Decision__mdt` record.
2. Run `node scripts/hash-definitions.js --write` to refresh `Definition_Hash__c` and `gavel-definitions.lock.json`.
3. Add every new state field to `docs/guides/data-leaving-your-org.md`.

`node scripts/hash-definitions.js --check` fails CI if a definition changed without a version bump.

## Apex style

- `with sharing` by default. Ledger writes are the documented exception (`Gavel_Ledger` runs in system mode so a decision is always recorded).
- Record reads for state use `WITH USER_MODE` and `Security.stripInaccessible`.
- Never throw out of an invocable. Return outcome `ERROR` with a reason.
- Tests use `Gavel_MockProvider` or `HttpCalloutMock`. Never call the live API from a test.
