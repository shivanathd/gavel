# Service pack

`gavel-pack-service` depends on gavel-core, gavel-flow and gavel-shadow. It adds five decisions for Cases and emails, the `Gavel_KB_Gap__c` object, the `Gavel_Service_Pack` permission set, mock fixtures and 200 labeled sample Cases.

Every definition installs in **Shadow** (ADR-015): decisions run and are ledgered, but no Case field changes until you promote a definition. No flow is active after install.

## Decisions

<!-- generated:start -->

### Gavel_Case_Triage

Routes a new Case to a queue or reason, and flags security or fraud concerns. Installs in Shadow.

- Target object: `Case`
- Install mode: **Shadow**
- Daily budget: 5000 calls
- Provider config: `TypeSafe_Default`

| Question | Type | Options | Auto accept | Review at | Min margin | Noul direction |
|---|---|---|---|---|---|---|
| `category`: Which team should handle this case? | choice | `BILLING`, `FRAUD`, `TECHNICAL`, `ACCOUNT`, `manual_review` (escape) | 0.85 | 0.5 | 0.3 | - |
| `fraud_concern`: The customer mentions a security or fraud concern. | noul | true / false | 0.85 | 0.5 | - | true_is_action |

Actions (Live and AUTO only):

- `category` = `BILLING`: set_field `Case.Type` = `Billing`
- `category` = `FRAUD`: set_field `Case.Type` = `Fraud`
- `category` = `TECHNICAL`: set_field `Case.Type` = `Technical`
- `category` = `ACCOUNT`: set_field `Case.Type` = `Account`

Data sent: see [Data leaving your org](../guides/data-leaving-your-org.md#gavel_case_triage).

### Gavel_Case_Urgency

Scores real urgency 0 to 4 from the text and recent emails, independent of the priority the customer picked.

- Target object: `Case`
- Install mode: **Shadow**
- Daily budget: 5000 calls
- Provider config: `TypeSafe_Default`

| Question | Type | Options | Auto accept | Review at | Min margin | Noul direction |
|---|---|---|---|---|---|---|
| `urgency`: How urgent is this case really, judged from what the customer describes? | score | `L0`, `L1`, `L2`, `L3`, `L4` | 0.85 | 0.5 | - | - |

Data sent: see [Data leaving your org](../guides/data-leaving-your-org.md#gavel_case_urgency).

### Gavel_Closure_Check

Before a Case closes: did the customer confirm the issue is resolved in their last inbound message?

- Target object: `Case`
- Install mode: **Shadow**
- Daily budget: 5000 calls
- Provider config: `TypeSafe_Default`

| Question | Type | Options | Auto accept | Review at | Min margin | Noul direction |
|---|---|---|---|---|---|---|
| `customer_confirmed_resolved`: The customer confirmed that the issue is resolved. | noul | true / false | 0.85 | 0.5 | - | true_is_action |

Data sent: see [Data leaving your org](../guides/data-leaving-your-org.md#gavel_closure_check).

### Gavel_Delivery_Proof

Item not received: is a parcel visible in the delivery photo, is it at a door, and where. Reads the newest Case image, so attach the carrier photo last. Photos can show house numbers. Installs in Shadow.

- Target object: `Case`
- Install mode: **Shadow**
- Daily budget: 2000 calls
- Provider config: `TypeSafe_Jev_1_14`

| Question | Type | Options | Auto accept | Review at | Min margin | Noul direction |
|---|---|---|---|---|---|---|
| `parcel_visible`: The photo shows a delivered parcel or package. | noul | true / false | 0.85 | 0.5 | - | false_is_action |
| `at_door`: The parcel is at the door, porch or entrance of a home or building. | noul | true / false | 0.85 | 0.5 | - | false_is_action |
| `parcel_area`: The delivered parcel or package. | box | true / false | 0.8 | 0.5 | - | - |

Asymmetric policy on `parcel_visible`: No parcel in the delivery photo is the case to flag.

Asymmetric policy on `at_door`: A parcel away from any door is the case to flag.

Data sent: see [Data leaving your org](../guides/data-leaving-your-org.md#gavel_delivery_proof).

### Gavel_KB_Coverage

Checks whether a Knowledge article answers the case. No article, or a weak match, creates a KB gap record.

- Target object: `Case`
- Install mode: **Shadow**
- Daily budget: 5000 calls
- Provider config: `TypeSafe_Default`

| Question | Type | Options | Auto accept | Review at | Min margin | Noul direction |
|---|---|---|---|---|---|---|
| `article`: Which candidate article best answers the customer question? | choice | runtime: Gavel_KBCandidates | 0.85 | 0.5 | 0.3 | - |
| `answers_question`: The selected article answers the customer question. | noul | true / false | 0.85 | 0.5 | - | true_is_action |

Data sent: see [Data leaving your org](../guides/data-leaving-your-org.md#gavel_kb_coverage).

### Gavel_Proof_Of_Purchase

Proof of purchase photo: is it a receipt or invoice, does it list the product, is the total visible and where. Jev points at the total but cannot read it. Receipts show names and card digits. Installs in Shadow.

- Target object: `Case`
- Install mode: **Shadow**
- Daily budget: 2000 calls
- Provider config: `TypeSafe_Jev_1_14`

| Question | Type | Options | Auto accept | Review at | Min margin | Noul direction |
|---|---|---|---|---|---|---|
| `is_receipt`: The photo shows a purchase receipt or invoice: paper, photographed, or a screenshot of an emailed receipt. Not a product photo, a note or an unrelated picture. | noul | true / false | 0.85 | 0.5 | - | false_is_action |
| `lists_product`: The receipt lists a purchase of the product named in the state. Line items may be abbreviated or coded. | noul | true / false | 0.85 | 0.5 | - | false_is_action |
| `total_visible`: The total amount paid is visible on the receipt. | noul | true / false | 0.85 | 0.5 | - | false_is_action |
| `total_area`: The total amount paid on the receipt. | box | true / false | 0.8 | 0.5 | - | - |

Asymmetric policy on `is_receipt`: A photo that is not a receipt is the case to flag.

Asymmetric policy on `lists_product`: A receipt for something else is the case to flag.

Asymmetric policy on `total_visible`: A receipt with no visible total cannot be checked.

Data sent: see [Data leaving your org](../guides/data-leaving-your-org.md#gavel_proof_of_purchase).

### Gavel_Reply_Check

Checks an outbound draft against the linked Knowledge article: supported, contradicted or unsupported.

- Target object: `EmailMessage`
- Install mode: **Shadow**
- Daily budget: 5000 calls
- Provider config: `TypeSafe_Default`

| Question | Type | Options | Auto accept | Review at | Min margin | Noul direction |
|---|---|---|---|---|---|---|
| `support`: Is the reply draft supported by the linked article text? | choice | `supported`, `contradicted`, `unsupported` | 0.85 | 0.5 | 0.3 | - |

Data sent: see [Data leaving your org](../guides/data-leaving-your-org.md#gavel_reply_check).

### Gavel_Return_Photo_Check

Reads the customer's photo on a return Case (jev-1.14.0): is damage visible, does it match the claim, and where is it. Skips when the Case has no photo. Run async for photos over about 1.5 MB. Installs in Shadow.

- Target object: `Case`
- Install mode: **Shadow**
- Daily budget: 2000 calls
- Provider config: `TypeSafe_Jev_1_14`

| Question | Type | Options | Auto accept | Review at | Min margin | Noul direction |
|---|---|---|---|---|---|---|
| `damage_visible`: The photo in the state shows visible damage or a defect on the product. | noul | true / false | 0.85 | 0.5 | - | true_is_action |
| `matches_claim`: The photo is consistent with the damage or fault the customer describes in the claim. | noul | true / false | 0.85 | 0.5 | - | false_is_action |
| `damage_area`: The damaged or defective area of the product in the photo. | box | true / false | 0.8 | 0.5 | - | - |

Asymmetric policy on `matches_claim`: A photo that does not match the claim is the case to flag.

Data sent: see [Data leaving your org](../guides/data-leaving-your-org.md#gavel_return_photo_check).

### Gavel_Return_Triage

Decides how to handle a return request: refund, replace, repair, reject under policy, or a person. The return window, refund limit and a failed photo check are enforced in code (Gavel_ReturnOptions). Installs in Shadow.

- Target object: `Case`
- Install mode: **Shadow**
- Daily budget: 5000 calls
- Provider config: `TypeSafe_Default`

| Question | Type | Options | Auto accept | Review at | Min margin | Noul direction |
|---|---|---|---|---|---|---|
| `outcome`: How should this return request be handled? | choice | runtime: Gavel_ReturnOptions:30:500 | 0.85 | 0.5 | 0.3 | - |
| `customer_caused`: The customer describes damage that they or someone in their household caused. | noul | true / false | 0.85 | 0.5 | - | true_is_action |

Actions (Live and AUTO only):

- `outcome` = `refund`: set_field `Case.Gavel_Return_Outcome__c` = `refund`
- `outcome` = `replace`: set_field `Case.Gavel_Return_Outcome__c` = `replace`
- `outcome` = `repair`: set_field `Case.Gavel_Return_Outcome__c` = `repair`
- `outcome` = `reject_policy`: set_field `Case.Gavel_Return_Outcome__c` = `reject_policy`

Data sent: see [Data leaving your org](../guides/data-leaving-your-org.md#gavel_return_triage).

### Gavel_Work_Completion

Checks the technician's completion photo on a Work Order: does it show the job finished, and is the site left clean and safe. Installs in Shadow.

- Target object: `WorkOrder`
- Install mode: **Shadow**
- Daily budget: 2000 calls
- Provider config: `TypeSafe_Jev_1_14`

| Question | Type | Options | Auto accept | Review at | Min margin | Noul direction |
|---|---|---|---|---|---|---|
| `work_complete`: The photo shows the job described in the state finished. | noul | true / false | 0.85 | 0.5 | - | false_is_action |
| `site_clean`: The work area is left clean and safe: no debris, loose tools or exposed wiring. | noul | true / false | 0.85 | 0.5 | - | false_is_action |

Asymmetric policy on `work_complete`: An unfinished job reported as done is the case to flag.

Asymmetric policy on `site_clean`: A hazard left on site is the case to flag.

Data sent: see [Data leaving your org](../guides/data-leaving-your-org.md#gavel_work_completion).

### Gavel_Wrong_Item_Check

Compares the customer's photo with the catalog photo of the Case's product (Asset.Product2): is this the item we sent? Needs a PNG or JPEG on the Case and on the Product. Installs in Shadow.

- Target object: `Case`
- Install mode: **Shadow**
- Daily budget: 2000 calls
- Provider config: `TypeSafe_Jev_1_14`

| Question | Type | Options | Auto accept | Review at | Min margin | Noul direction |
|---|---|---|---|---|---|---|
| `product_visible`: The customer photo shows a physical product, not a screenshot, a receipt or an unrelated scene. | noul | true / false | 0.85 | 0.5 | - | false_is_action |
| `same_product`: The product in the customer photo is the same product as in the catalog photo. | noul | true / false | 0.85 | 0.5 | - | false_is_action |

Asymmetric policy on `product_visible`: A photo with no product in it cannot be compared and is the case to flag.

Asymmetric policy on `same_product`: A wrong item is what this check exists to catch.

Data sent: see [Data leaving your org](../guides/data-leaving-your-org.md#gavel_wrong_item_check).

<!-- generated:end -->

## KB coverage and gaps

`Gavel: Check KB Coverage` (or `Gavel_KBCoverage.check`) asks Gavel_KB_Coverage to pick among the top 20 (max 50) online Knowledge articles found by SOSL on the case subject, plus `none`. A `Gavel_KB_Gap__c` record is created when there is no candidate, when the answer is `none`, or when the article does not answer the question. Gaps are Gavel records, so they are created in Shadow too. Question text on the gap is redacted. Without Knowledge, the run is ledgered as `SKIP knowledge_not_enabled`.

## Real urgency

Gavel_Case_Urgency scores 0 to 4 from the description and recent inbound emails. The customer-selected priority is sent as `customer_priority` so the ledger can show both values, and the prompt tells the model to judge independently of it. Einstein Case Classification can run side by side as the shadow baseline.

## How to run it in Shadow

1. Deploy: `./scripts/deploy.sh --org <org> --packs service --sample-data`.
2. Review [Data leaving your org](../guides/data-leaving-your-org.md), then set `Gavel_Ops_Config__mdt.Default.Egress_Enabled__c = true`.
3. Activate the flow template "Case Created: Triage (Async)".
4. Map baselines: `Gavel_Baseline_Map__mdt` ships `Case.Type` values Billing, Fraud, Technical and Account for Gavel_Case_Triage. Add your own values.
5. Schedule `Gavel_BaselineCapture` hourly. Read the Shadow comparison in the Gavel Calibration tab. Agreement with today's process is not accuracy.

## How to promote

1. Collect labels: captured baselines and reviewer resolutions. You need at least `Min_Sample__c` (default 200) labeled entries.
2. Run calibration from the Gavel Calibration tab. Apply a recommended threshold through a deploy that bumps `Version__c` (ADR-012), then `node scripts/hash-definitions.js --write`.
3. In the Decision Console click "Request Live". The promotion gate refuses without a calibration report from the last 14 days.

No accuracy numbers are claimed for this pack until a reproducible eval is linked here.
