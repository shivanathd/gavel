# 0017. Source deploy has to match packages

- Status: Accepted
- Date: 2026-10-01
- Deciders: Shivanath Devinarayanan (No Council: single-author decision)
- Source: `docs/spec/active/2026-10-01-gavel-v1/DECISIONS.md` (ADR-017)

## Context

Demo users shouldn't end up on a different product from package users.

## Decision

`deploy.sh` deploys the same `force-app` package directories in the same order, with the same post-install defaults, including egress off.

## Consequences

One code path to test.

## Alternatives

A separate demo-only metadata set with friendlier defaults (rejected: two products to test, and demos would show behavior real installs do not have). Package-only distribution (rejected: no quick path for demos and learning, PKG-001.2).

_Alternatives section added during implementation; DECISIONS.md had none for this ADR (see PROGRESS.md)._
