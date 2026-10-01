# 0001. Unlocked packages without a namespace, plus source deploy

- Status: Accepted
- Date: 2026-10-01
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-001)

## Context

The user wants both package installs and a one-command deploy. Managed packages need a namespace and security review. With no namespace, API names stay readable and teams can fork and edit freely.

## Decision

Ship eight unlocked packages with no namespace, in dependency order. Also ship `scripts/deploy.sh` for source deploys from the same `force-app` folders.

## Consequences

Name collisions are possible in customer orgs, so everything is prefixed `Gavel_`. Upgrades through unlocked packages are supported, but customers who edit the source lose clean upgrades (documented).

## Alternatives

Managed 2GP (IP protection we don't need, and it slows contributors down). Source only (no versioning, which is bad for real orgs).
