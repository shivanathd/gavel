# Data leaving your org

This page lists every field each shipped Gavel definition sends to the judgment provider (TypeSafe Jev by default). Nothing else leaves the org. `scripts/docs-egress-check.sh` fails CI when a definition sends a field that is not listed here.

How sending works:

- Egress is off after install (`Gavel_Ops_Config__mdt.Egress_Enabled__c = false`). While it is off, no call is made and every run is ledgered as `SKIP egress_disabled`.
- Only the fields below are read, with the running user's sharing and field-level security (`WITH USER_MODE` and `Security.stripInaccessible`). Unreadable or empty values are left out.
- Text is redacted before it is serialized: matches become `[REDACTED:<type>]` and the ledger records only `type:count`. Redaction is best-effort pattern matching, not DLP.
- Text is cut at the listed maximum with a `[truncated]` marker.
- The ledger stores a SHA-256 hash of what was sent, not the text, unless an admin turns on `Store_State__c`.
- Images (only definitions pinned to jev-1.14.0 or later) are sent as files with the TypeSafe image opt-in header. They are not redacted or truncated. The ledger keeps only their SHA-256 digest, never the bytes. Each side must be 280 to 1568 px. A required photo outside that range skips the run before anything is sent; an optional one is left out.
- Labels and feedback are never sent to the provider.
- TypeSafe data retention and processing terms are not yet verified (OQ-1). Treat egress as sending data to a third-party processor until that is resolved.

# Pack: agentforce-gate

## Gavel_Action_Risk

Labels an agent action before it runs: read only, reversible or destructive. Destructive actions need a human. Target object: `None`. Installs in **Shadow**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `input.actionDescription` | action | yes | 1000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | text passed to the action by the caller |
| `input.targetSummary` | target | no | 1000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | text passed to the action by the caller |

## Gavel_Input_Screen

Screens inbound text (email, web form, chat) before an AI agent reads it: injected instructions, substance, relevance. Target object: `None`. Installs in **Shadow**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `input.text` | text | yes | 4000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | text passed to the action by the caller |
| `input.taskDescription` | task | no | 500 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | text passed to the action by the caller |

Intake screening flows fill `input.text` from `Case.Subject` and `Case.Description` (Email-to-Case) or `Lead.Company` and `Lead.Description` (Web-to-Lead). Agent actions pass the text the agent is about to read.

# Pack: sales-marketing

## Gavel_Lead_Quality

Separates real buyers from students, job seekers, vendors, competitors, spam and test data. Shadow only in v1. Target object: `Lead`. Installs in **Shadow**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `Company` | company | no | 255 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |
| `Title` | title | no | 128 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |
| `Email` | email_domain | no | 255 | none | domain part only; the full address never leaves the org |
| `Description` | description | no | 2000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |
| `LeadSource` | lead_source | no | 80 | none | field value |

## Gavel_Opt_Out_Detect

Finds opt-out requests hidden in replies. Installs Live-Review: review items only until an admin enables auto-apply. Target object: `EmailMessage`. Installs in **Live**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `EmailMessage.TextBody` | body | yes | 2000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | body of this email, quoted reply chains removed |

## Gavel_Persona

Persona and seniority from the job title. Edit the options to match your ideal customer profile. Target object: `Lead`. Installs in **Shadow**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `Title` | title | yes | 128 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |
| `Company` | company | no | 255 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |

## Gavel_Product_Photo_Check

Checks a product's photo before it goes into a listing: is it clear and usable, and does it show the product named. Installs in Shadow. Target object: `Product2`. Installs in **Shadow**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `ContentVersion.VersionData` | photo | yes | 100 | none | the latest PNG or JPEG file on the record or its inbound emails, sent as an image (jev-1.14.0). Images are not redacted: anything visible in the photo, such as a shipping label, leaves the org |
| `Name` | name | yes | 255 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |
| `Description` | description | no | 1000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |

## Gavel_Reply_Intent

Reads the intent of an inbound reply to outreach. Target object: `EmailMessage`. Installs in **Shadow**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `EmailMessage.TextBody` | body | yes | 2000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | body of this email, quoted reply chains removed |

## Gavel_Stage_Evidence

Checks recent activity for the evidence each stage exit needs. REVIEW sets a helper field a validation rule can use. Target object: `Opportunity`. Installs in **Shadow**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `StageName` | stage | no | 80 | none | field value |
| `Task.Description` | recent_activity | yes | 6000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | last Task and Event descriptions and email bodies on the record within 90 days |

# Pack: service

## Gavel_Case_Triage

Routes a new Case to a queue or reason, and flags security or fraud concerns. Installs in Shadow. Target object: `Case`. Installs in **Shadow**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `Subject` | subject | no | 500 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |
| `Description` | description | yes | 2000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |
| `Origin` | origin | no | 80 | none | field value |
| `Account.Industry` | industry | no | 80 | none | field value |
| `EmailMessage.TextBody` | recent_emails | no | 2000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | last inbound email bodies on the record, quoted reply chains removed, 2,000 characters each |
| `Priority` | customer_priority | no | 40 | none | field value |

## Gavel_Case_Urgency

Scores real urgency 0 to 4 from the text and recent emails, independent of the priority the customer picked. Target object: `Case`. Installs in **Shadow**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `Subject` | subject | no | 500 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |
| `Description` | description | yes | 2000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |
| `Origin` | origin | no | 80 | none | field value |
| `Account.Industry` | industry | no | 80 | none | field value |
| `EmailMessage.TextBody` | recent_emails | no | 2000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | last inbound email bodies on the record, quoted reply chains removed, 2,000 characters each |
| `Priority` | customer_priority | no | 40 | none | field value |

## Gavel_Closure_Check

Before a Case closes: did the customer confirm the issue is resolved in their last inbound message? Target object: `Case`. Installs in **Shadow**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `EmailMessage.TextBody` | last_inbound | yes | 2000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | last inbound email bodies on the record, quoted reply chains removed, 2,000 characters each |

## Gavel_Delivery_Proof

For an item-not-received Case with the carrier's delivery photo: is a parcel visible, is it at a door or entrance, and where is it. Installs in Shadow. Target object: `Case`. Installs in **Shadow**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `ContentVersion.VersionData` | photo | yes | 100 | none | the latest PNG or JPEG file on the record or its inbound emails, sent as an image (jev-1.14.0). Images are not redacted: anything visible in the photo, such as a shipping label, leaves the org |
| `Description` | claim | yes | 2000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |

## Gavel_KB_Coverage

Checks whether a Knowledge article answers the case. No article, or a weak match, creates a KB gap record. Target object: `Case`. Installs in **Shadow**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `Subject` | subject | yes | 500 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |
| `Description` | description | no | 2000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |

Also sent as answer options: the Id, Title and Summary (first 2,000 characters) of up to 20 online Knowledge articles found by SOSL on the case subject (max 50).

## Gavel_Proof_Of_Purchase

Checks the photo a customer sent as proof of purchase: is it a real receipt, does it list the product, and where is the total. Jev points at the total but cannot read it. Installs in Shadow. Target object: `Case`. Installs in **Shadow**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `ContentVersion.VersionData` | photo | yes | 100 | none | the latest PNG or JPEG file on the record or its inbound emails, sent as an image (jev-1.14.0). Images are not redacted: anything visible in the photo, such as a shipping label, leaves the org |
| `Asset.Name` | product | yes | 120 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |

## Gavel_Reply_Check

Checks an outbound draft against the linked Knowledge article: supported, contradicted or unsupported. Target object: `EmailMessage`. Installs in **Shadow**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `EmailMessage.TextBody` | draft | yes | 2000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | body of this email, quoted reply chains removed |
| `Knowledge__kav.Summary` | article | no | 2000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | Summary of the Knowledge article attached to the email case |

## Gavel_Return_Photo_Check

Reads the customer's photo on a return Case (jev-1.14.0): is damage visible, does it match the claim, and where is it. Skips when the Case has no photo. Run async for photos over about 1.5 MB. Installs in Shadow. Target object: `Case`. Installs in **Shadow**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `ContentVersion.VersionData` | photo | yes | 100 | none | the latest PNG or JPEG file on the record or its inbound emails, sent as an image (jev-1.14.0). Images are not redacted: anything visible in the photo, such as a shipping label, leaves the org |
| `Description` | claim | yes | 2000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |
| `Asset.Name` | product | no | 120 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |

## Gavel_Return_Triage

Decides how to handle a return request: refund, replace, repair, reject under policy, or a person. The return window, refund limit and a failed photo check are enforced in code (Gavel_ReturnOptions). Installs in Shadow. Target object: `Case`. Installs in **Shadow**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `Subject` | subject | no | 500 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |
| `Description` | request | yes | 2000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |
| `Reason` | reason | no | 80 | none | field value |
| `Asset.Name` | product | no | 120 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |
| `Asset.PurchaseDate` | purchase_date | no | 20 | none | field value |
| `Asset.Price` | item_price | no | 20 | none | field value |
| `EmailMessage.TextBody` | recent_emails | no | 4000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | last inbound email bodies on the record, quoted reply chains removed, 2,000 characters each |

## Gavel_Work_Completion

Checks the technician's completion photo on a Work Order: does it show the job finished, and is the site left clean and safe. Installs in Shadow. Target object: `WorkOrder`. Installs in **Shadow**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `ContentVersion.VersionData` | photo | yes | 100 | none | the latest PNG or JPEG file on the record or its inbound emails, sent as an image (jev-1.14.0). Images are not redacted: anything visible in the photo, such as a shipping label, leaves the org |
| `Subject` | job_title | no | 255 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |
| `Description` | job | yes | 2000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |

## Gavel_Wrong_Item_Check

Compares the customer's photo with the catalog photo of the Case's product (Asset.Product2): is this the item we sent? Needs a PNG or JPEG on the Case and on the Product. Installs in Shadow. Target object: `Case`. Installs in **Shadow**.

| Field path | State key | Required | Max chars | Redaction | Notes |
|---|---|---|---|---|---|
| `ContentVersion.VersionData` | photo | yes | 100 | none | the latest PNG or JPEG file on the record or its inbound emails, sent as an image (jev-1.14.0). Images are not redacted: anything visible in the photo, such as a shipping label, leaves the org |
| `ContentVersion.VersionData` | catalog_photo | yes | 100 | none | the latest PNG or JPEG file on the related record `Asset.Product2Id`, sent as an image (jev-1.14.0). Images are not redacted |
| `Asset.Name` | product | no | 120 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |
| `Description` | claim | yes | 2000 | strict (email, phone, card, CVV, SSN, Aadhaar, India PAN) | field value |
