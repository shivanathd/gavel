# 0012. Humans apply thresholds

- Status: Accepted
- Date: 2026-10-01
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-012)

## Context

Auto-tuning thresholds from feedback is tempting, but it creates a feedback loop no one reviews.

## Decision

Calibration recommends and a human applies. Applying bumps the definition version.

## Consequences

Every threshold change can be audited as a deploy.

## Alternatives

Auto-apply inside bounds (rejected in v1).
