# 0015. Packs install in Shadow

- Status: Accepted
- Date: 2026-10-01
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-015)

## Context

Installing a pack shouldn't change a single customer record.

## Decision

Every pack definition installs in Shadow, with the documented exception of Opt-Out Detect (ADR-016), which installs as Live-Review.

## Consequences

Nothing happens until an admin decides it should.

## Alternatives

Install packs in Live with actions disabled by a global switch (rejected: one misconfigured switch would change customer records on install). Ask the admin to choose a mode during install (rejected: unlocked packages have no install wizard, and a wrong default is the failure we are preventing).

_Alternatives section added during implementation; DECISIONS.md had none for this ADR (see PROGRESS.md)._
