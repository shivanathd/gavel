# 0014. Agentforce gate is advisory unless wired as the only path

- Status: Accepted, Revisit on OQ-4
- Date: 2026-10-01
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-014)

## Context

Gavel can ship agent actions and Flow wrappers. A public pre-execution hook for Agentforce isn't verified. Claiming enforcement we can't guarantee would be a security misstatement.

## Decision

Ship the screen and risk actions, a guarded wrapper pattern and intake screening. Docs say the gate enforces only when the wrapped action is reachable solely through the wrapper, and is advisory otherwise.

## Consequences

An honest security posture, with a bit more setup for admins.

## Alternatives

Market it as "Agentforce firewall" (rejected).
