# Sales and Marketing pack

`gavel-pack-sales-marketing` depends on gavel-core, gavel-flow, gavel-shadow and gavel-calibrate. It adds five decisions for Leads, inbound emails and Opportunities, the `Opportunity.Gavel_Stage_Evidence_Status__c` helper field, the `Gavel_Sales_Marketing_Pack` permission set, mock fixtures and 50 sample Leads.

Every definition installs in **Shadow** except Gavel_Opt_Out_Detect, which installs **Live-Review** (ADR-015, ADR-016): it is Live, but auto-apply is off, so it creates review items and changes nothing until an admin enables auto-apply. No flow is active after install.

## Decisions

<!-- generated:start -->

### Gavel_Lead_Quality

Separates real buyers from students, job seekers, vendors, competitors, spam and test data. Shadow only in v1.

- Target object: `Lead`
- Install mode: **Shadow**
- Daily budget: 5000 calls
- Provider config: `TypeSafe_Default`

| Question | Type | Options | Auto accept | Review at | Min margin | Noul direction |
|---|---|---|---|---|---|---|
| `quality`: What kind of lead is this? | choice | `real_buyer`, `student`, `job_seeker`, `vendor`, `competitor`, `spam`, `test_data`, `manual_review` (escape) | 0.85 | 0.5 | 0.3 | - |

Data sent: see [Data leaving your org](../guides/data-leaving-your-org.md#gavel_lead_quality).

### Gavel_Opt_Out_Detect

Finds opt-out requests hidden in replies. Installs Live-Review: review items only until an admin enables auto-apply.

- Target object: `EmailMessage`
- Install mode: **Live** with auto-apply off (Live-Review)
- Daily budget: 20000 calls
- Provider config: `TypeSafe_Default`

| Question | Type | Options | Auto accept | Review at | Min margin | Noul direction |
|---|---|---|---|---|---|---|
| `asks_not_to_be_contacted`: The sender asks not to be contacted, emailed or kept on a list. | noul | true / false | 0.6 | 0.15 | - | true_is_action |

Asymmetric policy on `asks_not_to_be_contacted`: Asymmetric by design: a false positive costs one lost email; a missed opt-out is a compliance breach (CAN-SPAM, GDPR Art. 21, CASL).

Actions (Live and AUTO only):

- `asks_not_to_be_contacted` = `true`: set_field `$Who.HasOptedOutOfEmail` = `true`

Data sent: see [Data leaving your org](../guides/data-leaving-your-org.md#gavel_opt_out_detect).

### Gavel_Persona

Persona and seniority from the job title. Edit the options to match your ideal customer profile.

- Target object: `Lead`
- Install mode: **Shadow**
- Daily budget: 5000 calls
- Provider config: `TypeSafe_Default`

| Question | Type | Options | Auto accept | Review at | Min margin | Noul direction |
|---|---|---|---|---|---|---|
| `persona`: Which persona fits this person best? | choice | `executive`, `manager`, `practitioner`, `technical`, `manual_review` (escape) | 0.85 | 0.5 | 0.3 | - |
| `seniority`: What is the seniority of this title? | choice | `c_level`, `vp`, `director`, `manager`, `individual`, `unknown` (escape) | 0.85 | 0.5 | 0.3 | - |

Data sent: see [Data leaving your org](../guides/data-leaving-your-org.md#gavel_persona).

### Gavel_Reply_Intent

Reads the intent of an inbound reply to outreach.

- Target object: `EmailMessage`
- Install mode: **Shadow**
- Daily budget: 5000 calls
- Provider config: `TypeSafe_Default`

| Question | Type | Options | Auto accept | Review at | Min margin | Noul direction |
|---|---|---|---|---|---|---|
| `intent`: What does the sender want? | choice | `interested`, `not_now`, `wrong_person`, `referral`, `out_of_office`, `unsubscribe`, `other` | 0.85 | 0.5 | 0.3 | - |

Data sent: see [Data leaving your org](../guides/data-leaving-your-org.md#gavel_reply_intent).

### Gavel_Stage_Evidence

Checks recent activity for the evidence each stage exit needs. REVIEW sets a helper field a validation rule can use.

- Target object: `Opportunity`
- Install mode: **Shadow**
- Daily budget: 5000 calls
- Provider config: `TypeSafe_Default`

| Question | Type | Options | Auto accept | Review at | Min margin | Noul direction |
|---|---|---|---|---|---|---|
| `economic_buyer_identified`: The economic buyer has been identified by name or role. | noul | true / false | 0.85 | 0.5 | - | true_is_action |
| `budget_confirmed`: A budget for this purchase has been confirmed. | noul | true / false | 0.85 | 0.5 | - | true_is_action |
| `decision_process_known`: The decision process and timeline are known. | noul | true / false | 0.85 | 0.5 | - | true_is_action |

Data sent: see [Data leaving your org](../guides/data-leaving-your-org.md#gavel_stage_evidence).

<!-- generated:end -->

## Opt-out rules

- Gavel only ever sets `HasOptedOutOfEmail` (and `HasOptedOutOfFax`, `DoNotCall`) to true. Any action that would set them to false is refused and logged as `blocked_monotonic_field` (SM-001.4).
- The policy is asymmetric: auto-apply at probability 0.6 or more, review between 0.15 and 0.6. A false positive costs one email; a missed opt-out is a compliance breach. The reason is written to every ledger entry.
- A provider error, an open breaker or an exhausted budget creates a review item: opt-out fails toward a human check, never toward ignoring the request.
- "Unsubscribe me from the newsletter but keep product updates" is a preference-center case and is routed to review.
- To enable auto-apply: set `Gavel_Decision__mdt.Gavel_Opt_Out_Detect.Auto_Apply__c = true` and deploy.
- Actions run in the running user's context (least privilege). The user or integration user that runs Opt-Out Detect needs the `Gavel_Sales_Marketing_Pack` permission set, which grants edit on `HasOptedOutOfEmail` for Leads and Contacts. Without it the update is refused and the action log records the error; nothing is silently skipped.

## Stage evidence

`Gavel: Check Stage Evidence` judges each stage exit criterion (one Noul per criterion, with `Stage__c` on the question row) from the last 10 Tasks, Events and emails within 90 days. When Live it sets `Gavel_Stage_Evidence_Status__c` to `Verified`, `Missing Evidence` or `Needs Review`. A validation rule such as `AND(ISCHANGED(StageName), TEXT(Gavel_Stage_Evidence_Status__c) <> "Verified")` blocks the stage change. Lead Quality never disqualifies a lead in v1.

## How to run it in Shadow

1. Deploy: `./scripts/deploy.sh --org <org> --packs sales-marketing --sample-data`.
2. Review [Data leaving your org](../guides/data-leaving-your-org.md) (Lead email is sent as the domain only), then turn egress on.
3. Activate "Lead Created: Junk Check (Async)" and "Email Received: Reply Intent (Async)".
4. Overrides by your reps (for example a changed Lead Status) become calibration labels within 72 hours.

## How to promote

Same as every pack: at least 200 labeled entries, a calibration report from the last 14 days, a threshold applied through a version bump, then "Request Live" in the Decision Console. Einstein Lead Scoring is untouched and can serve as a baseline.
