---
document_type: decisions
project_id: GAVEL
version: 1.0.0
last_updated: 2026-10-01
status: draft
---

# Gavel v1: Architecture Decision Records

Each ADR is also copied to `docs/adr/NNNN-title.md` in the repo. Council note for all ADRs: [No Council: single-author decision, Shivanath Devinarayanan]. Revisit any ADR marked "Revisit" at v1.1.

---

## ADR-000: Name the project Gavel, not JevForce

**Status:** Accepted

**Context.** Ravi Narayanan published JevForce, an Apache 2.0 Apex SDK for calling Jev from Salesforce ([JevForce](https://github.com/ravinarayanan89/JevForce)). Reusing that name would confuse users and look like a fork. "Jev" is TypeSafe's product name, and putting it in our project name implies an affiliation we don't have. A GitHub search for `gavel+salesforce` returned no repos (2026-10-01).

**Decision.** The project is called **Gavel**. Repo `shivanathd/gavel`. Tagline: "Governed AI judgments for Salesforce." Package descriptions say "works with TypeSafe Jev", never "Jev for Salesforce". Metadata prefix is `Gavel_`.

**Consequences.** Clean identity and room for more providers later. A small discoverability cost for people searching "Jev Salesforce", which the README and topics (`jev`, `typesafe`, `salesforce`, `agentforce`) cover.

**Alternatives.** "Verdict" (taken by several Salesforce repos), "Arbiter" (existing Salesforce ORM repo), "JevGuard" (Jev in the name), "Decision Ledger" (too narrow).

---

## ADR-001: Unlocked packages without a namespace, plus source deploy

**Status:** Accepted

**Context.** The user wants both package installs and a one-command deploy. Managed packages need a namespace and security review. With no namespace, API names stay readable and teams can fork and edit freely.

**Decision.** Ship eight unlocked packages with no namespace, in dependency order. Also ship `scripts/deploy.sh` for source deploys from the same `force-app` folders.

**Consequences.** Name collisions are possible in customer orgs, so everything is prefixed `Gavel_`. Upgrades through unlocked packages are supported, but customers who edit the source lose clean upgrades (documented).

**Alternatives.** Managed 2GP (IP protection we don't need, and it slows contributors down). Source only (no versioning, which is bad for real orgs).

---

## ADR-002: Provider interface, TypeSafe as default, built from scratch

**Status:** Accepted

**Context.** JevForce already wraps Jev in Apex under Apache 2.0. We could depend on it, fork it or write our own. Gavel needs batching tied to definitions, strict contract validation that returns statuses rather than throwing, ledger hooks, a mock provider and room for other providers (OpenRouter and Cloudflare also host Jev, per the [awesome-jev list](https://github.com/fatwang2/awesome-jev) and [Cloudflare docs](https://developers.cloudflare.com/ai/models/typesafe/jev/)).

**Decision.** Define `Gavel_JudgmentProvider`, then implement `Gavel_TypeSafeProvider` and `Gavel_MockProvider` from scratch, copying no JevForce code. Credit JevForce as prior art in README and NOTICE.

**Consequences.** No license obligations to JevForce because we don't copy its code. No dependency on Ravi's release cadence. We duplicate a small amount of HTTP and JSON mapping work.

**Alternatives.** Depend on JevForce (couples us to its exception model and to a non-package source layout). Fork it (then Apache 2.0 requires keeping the license and NOTICE and marking changes, and the fork diverges). Revisit if Ravi wants to collaborate (OQ-7).

---

## ADR-003: Pin model versions for Live definitions

**Status:** Accepted

**Context.** The API accepts model IDs and aliases, and the response reports the versioned model that answered ([TypeSafe models docs](https://docs.typesafe.ai/models)). With an alias, thresholds calibrated on one model version could silently apply to the next.

**Decision.** Live definitions require a pinned model ID. Shadow and Draft may use aliases. Changing the model ID for a Live definition requires a new version and a fresh calibration.

**Consequences.** Upgrading the model takes a deliberate step. Calibration stays valid.

**Alternatives.** Allow aliases with a warning (rejected, because drift is silent).

---

## ADR-004: Custom Metadata for definitions, custom objects for runtime data

**Status:** Accepted

**Context.** Definitions are configuration: they should deploy between orgs, sit in version control and be packageable. Runtime data (ledger, feedback, reviews) is high-volume and changes all the time.

**Decision.** Definitions, questions, options, state fields, policies and action maps live in Custom Metadata. The ledger, feedback, reviews, baselines, KB gaps and calibration reports are custom objects.

**Consequences.** Admins change definitions through deploys or the Decision Builder, which uses the Metadata API. Flows can't edit definitions at runtime, which is intended.

**Alternatives.** Custom objects for definitions (not deployable as config, and drift between orgs). JSON static resources (not admin-friendly).

---

## ADR-005: Fail closed, never throw into Flow

**Status:** Accepted

**Context.** An unhandled exception in a flow shows users a fault screen or rolls back the transaction. An AI dependency must never break a Case save, and it must never auto-act when it isn't sure.

**Decision.** Every provider and runtime error becomes a typed status. The policy engine maps these to ERROR or SKIP, and both route to review or to no action. Invocable actions always return normally.

**Consequences.** Admins have to watch ERROR rates (alerts in F9). The business transaction always succeeds.

**Alternatives.** Throw and let Flow fault paths handle it (rejected: too easy to misconfigure).

---

## ADR-006: Data minimization by default

**Status:** Accepted

**Context.** TypeSafe's retention and training terms aren't verified yet (OQ-1). Case, Lead and EmailMessage text often contains PII.

**Decision.** Only allowlisted fields are sent. The default redaction profile is `strict`. The ledger stores a state hash, not the state, unless an admin opts in. Egress is off after install.

**Consequences.** Setup has one extra step. Safer default posture for security reviews.

**Alternatives.** Send the whole record for better judgments (rejected). Only redact when opted in (rejected).

---

## ADR-007: Async-first execution

**Status:** Accepted

**Context.** Callouts can't run after uncommitted DML, and record-triggered flows need the async path for callouts. Bulk loads of 200 records would hit callout limits in a single transaction.

**Decision.** The primary path is a Queueable with `Database.AllowsCallouts`, chunked at 20 records. A sync invocable exists only for screen flows and Apex callers that have no pending DML.

**Consequences.** Results arrive seconds after save, not inside it, and the UI shows a PENDING state. Record-triggered templates use the async path.

**Alternatives.** Platform Event subscriber (more moving parts, harder to debug). Continuations (UI only).

---

## ADR-008: Most-conservative outcome wins

**Status:** Accepted

**Context.** A definition asks several questions. Averaging probabilities or taking the best one hides risk.

**Decision.** The definition outcome is the most conservative outcome among required questions. The order is ERROR > SKIP > ESCALATE > REVIEW > AUTO.

**Consequences.** Fewer auto-actions, and each one is easy to defend.

**Alternatives.** Weighted composite (harder to explain to auditors, and can dilute one red flag).

---

## ADR-009: Definition hash plus explicit version

**Status:** Accepted

**Context.** A ledger entry has to point to exactly what the model was asked. Admins forget to bump version numbers.

**Decision.** CI computes a canonical hash over the definition and its children and stores it in `Definition_Hash__c`. At runtime Gavel recomputes the hash, and rejects the run if it doesn't match the stored value for that version.

**Consequences.** Editing CMDT directly in Setup without a version bump makes Live runs ERROR until it's fixed. Documented loudly in the admin app.

**Alternatives.** Version only (trusts humans). Hash only (not readable).

---

## ADR-010: Custom object ledger in v1, Big Object later

**Status:** Accepted, Revisit at v1.1

**Context.** Big Objects scale better but are hard to report on and can't have triggers. v1 users need related lists, reports and an immutability trigger.

**Decision.** `Gavel_Decision_Log__c` custom object with a retention batch. Big Object archive in v1.1.

**Consequences.** Storage cost in high-volume orgs, mitigated by retention.

**Alternatives.** Big Object now. External log (sends more data out of the org).

---

## ADR-011: Shadow first, promotion gated by calibration

**Status:** Accepted

**Context.** Agreement with the baseline isn't accuracy, but switching straight to Live is how AI routing loses trust.

**Decision.** Packs install in Shadow. Promoting to Live needs a calibration report from the last 14 days with 200 or more labeled entries.

**Consequences.** Slower time to Live. Much easier to trust.

**Alternatives.** Allow an admin override of the gate (rejected in v1; could come back as a permission `Gavel_Promote_Override` in v1.1 with a ledgered reason).

---

## ADR-012: Humans apply thresholds

**Status:** Accepted

**Context.** Auto-tuning thresholds from feedback is tempting, but it creates a feedback loop no one reviews.

**Decision.** Calibration recommends and a human applies. Applying bumps the definition version.

**Consequences.** Every threshold change can be audited as a deploy.

**Alternatives.** Auto-apply inside bounds (rejected in v1).

---

## ADR-013: Budgets and circuit breaker in core

**Status:** Accepted

**Context.** A runaway flow or data load can burn money and hammer a failing API.

**Decision.** Per-definition daily budgets and an org-level breaker live in core. Every run passes through them.

**Consequences.** A small overhead on each run.

**Alternatives.** Leave it to admins (rejected).

---

## ADR-014: Agentforce gate is advisory unless wired as the only path

**Status:** Accepted, Revisit on OQ-4

**Context.** Gavel can ship agent actions and Flow wrappers. A public pre-execution hook for Agentforce isn't verified. Claiming enforcement we can't guarantee would be a security misstatement.

**Decision.** Ship the screen and risk actions, a guarded wrapper pattern and intake screening. Docs say the gate enforces only when the wrapped action is reachable solely through the wrapper, and is advisory otherwise.

**Consequences.** An honest security posture, with a bit more setup for admins.

**Alternatives.** Market it as "Agentforce firewall" (rejected).

---

## ADR-015: Packs install in Shadow

**Status:** Accepted

**Context.** Installing a pack shouldn't change a single customer record.

**Decision.** Every pack definition installs in Shadow, with the documented exception of Opt-Out Detect (ADR-016), which installs as Live-Review.

**Consequences.** Nothing happens until an admin decides it should.

---

## ADR-016: Asymmetric policies for compliance decisions

**Status:** Accepted

**Context.** Missing an opt-out is a compliance breach. Wrongly opting someone out costs one lost email. Symmetric thresholds are the wrong tool here.

**Decision.** Policies can be asymmetric if they record a written reason. Opt-out auto-applies at probability 0.6 or higher once enabled, and Gavel never sets opt-out back to false.

**Consequences.** More false-positive opt-outs, by design.

**Alternatives.** Same 0.85 threshold as everything else (rejected, because recall is what matters here).

---

## ADR-017: Source deploy has to match packages

**Status:** Accepted

**Context.** Demo users shouldn't end up on a different product from package users.

**Decision.** `deploy.sh` deploys the same `force-app` package directories in the same order, with the same post-install defaults, including egress off.

**Consequences.** One code path to test.

---

## ADR-018: Apache 2.0 license, personal ownership

**Status:** Accepted, pending OQ-3

**Context.** Personal project on the shivanathd GitHub. Apache 2.0 includes a patent grant and is common across the Salesforce ecosystem. JevForce uses Apache 2.0 too.

**Decision.** Apache 2.0 with a NOTICE file. Contributions under DCO sign-off.

**Consequences.** Enterprises can use it freely, and contributors keep their copyright.

**Alternatives.** MIT (no patent grant).

---

## ADR-019: A Box location is kept when its Noul says the thing is there

**Status:** Accepted (2026-10-18)

**Context.** A Box answer is always a box. On 49 labelled photos, box confidence did not separate present from absent: correct boxes on real photos scored 0.20 to 0.49, ghost boxes 0.03 to 0.18, and a wrong box on a torn receipt 0.44. The Noul next to each box was right on all 26.

**Decision.** `Gavel_Question__mdt.Box_Gate__c` names that Noul. Below 0.5, or with no valid gate answer: `box_not_found`. At 0.5 or more: the location is kept, and a low box confidence is `REVIEW box_low_confidence`. Ungated boxes keep the previous rule. The field is hashed only when set.

**Consequences.** Reviewers see correct low-confidence locations. Boxes still never drive actions.

**Alternatives.** A lower box threshold; pairing by key naming convention.
