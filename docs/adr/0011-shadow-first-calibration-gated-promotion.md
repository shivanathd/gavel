# 0011. Shadow first, promotion gated by calibration

- Status: Accepted
- Date: 2026-10-01
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-011)

## Context

Agreement with the baseline isn't accuracy, but switching straight to Live is how AI routing loses trust.

## Decision

Packs install in Shadow. Promoting to Live needs a calibration report from the last 14 days with 200 or more labeled entries.

## Consequences

Slower time to Live. Much easier to trust.

## Alternatives

Allow an admin override of the gate (rejected in v1; could come back as a permission `Gavel_Promote_Override` in v1.1 with a ledgered reason).
