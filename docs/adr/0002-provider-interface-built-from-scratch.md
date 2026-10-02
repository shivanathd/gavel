# 0002. Provider interface, TypeSafe as default, built from scratch

- Status: Accepted
- Date: 2026-10-01
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-002)

## Context

JevForce already wraps Jev in Apex under Apache 2.0. We could depend on it, fork it or write our own. Gavel needs batching tied to definitions, strict contract validation that returns statuses rather than throwing, ledger hooks, a mock provider and room for other providers (OpenRouter and Cloudflare also host Jev, per the [awesome-jev list](https://github.com/fatwang2/awesome-jev) and [Cloudflare docs](https://developers.cloudflare.com/ai/models/typesafe/jev/)).

## Decision

Define `Gavel_JudgmentProvider`, then implement `Gavel_TypeSafeProvider` and `Gavel_MockProvider` from scratch, copying no JevForce code. Credit JevForce as prior art in README and NOTICE.

## Consequences

No license obligations to JevForce because we don't copy its code. No dependency on Ravi's release cadence. We duplicate a small amount of HTTP and JSON mapping work.

## Alternatives

Depend on JevForce (couples us to its exception model and to a non-package source layout). Fork it (then Apache 2.0 requires keeping the license and NOTICE and marking changes, and the fork diverges). Revisit if Ravi wants to collaborate (OQ-7).
