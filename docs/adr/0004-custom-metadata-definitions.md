# 0004. Custom Metadata for definitions, custom objects for runtime data

- Status: Accepted
- Date: 2026-10-01
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-004)

## Context

Definitions are configuration: they should deploy between orgs, sit in version control and be packageable. Runtime data (ledger, feedback, reviews) is high-volume and changes all the time.

## Decision

Definitions, questions, options, state fields, policies and action maps live in Custom Metadata. The ledger, feedback, reviews, baselines, KB gaps and calibration reports are custom objects.

## Consequences

Admins change definitions through deploys or the Decision Builder, which uses the Metadata API. Flows can't edit definitions at runtime, which is intended.

## Alternatives

Custom objects for definitions (not deployable as config, and drift between orgs). JSON static resources (not admin-friendly).
