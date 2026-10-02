# 0003. Pin model versions for Live definitions

- Status: Accepted
- Date: 2026-10-01
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-003)

## Context

The API accepts model IDs and aliases, and the response reports the versioned model that answered ([TypeSafe models docs](https://docs.typesafe.ai/models)). With an alias, thresholds calibrated on one model version could silently apply to the next.

## Decision

Live definitions require a pinned model ID. Shadow and Draft may use aliases. Changing the model ID for a Live definition requires a new version and a fresh calibration.

## Consequences

Upgrading the model takes a deliberate step. Calibration stays valid.

## Alternatives

Allow aliases with a warning (rejected, because drift is silent).
