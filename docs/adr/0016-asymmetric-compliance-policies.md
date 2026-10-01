# 0016. Asymmetric policies for compliance decisions

- Status: Accepted
- Date: 2026-10-01
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-016)

## Context

Missing an opt-out is a compliance breach. Wrongly opting someone out costs one lost email. Symmetric thresholds are the wrong tool here.

## Decision

Policies can be asymmetric if they record a written reason. Opt-out auto-applies at probability 0.6 or higher once enabled, and Gavel never sets opt-out back to false.

## Consequences

More false-positive opt-outs, by design.

## Alternatives

Same 0.85 threshold as everything else (rejected, because recall is what matters here).
