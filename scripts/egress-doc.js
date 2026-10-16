#!/usr/bin/env node
/* Regenerates docs/guides/data-leaving-your-org.md from the shipped definitions. CI checks it with docs-egress-check.sh. */
'use strict';
const fs = require('fs');
const path = require('path');
const { loadRecords } = require('./hash-definitions');

const ROOT = path.resolve(__dirname, '..');
const recs = loadRecords();
const v = (r, f) => (r.values[f] === undefined || r.values[f] === null ? '' : String(r.values[f]).trim());
const decisions = recs.filter((r) => r.type === 'Gavel_Decision').sort((a, b) => (v(a, 'Pack__c') + a.devName).localeCompare(v(b, 'Pack__c') + b.devName));
const PROFILE = { strict: 'strict (email, phone, card, CVV, SSN, Aadhaar, India PAN)', none: 'none', pii_basic: 'pii_basic (email, phone)', payment: 'payment (card, CVV)', gov_id: 'gov_id (SSN, Aadhaar, India PAN)' };
const SOURCE_NOTE = {
  'Gavel_StateSources.InboundEmails': 'last inbound email bodies on the record, quoted reply chains removed, 2,000 characters each',
  'Gavel_StateSources.EmailBody': 'body of this email, quoted reply chains removed',
  'Gavel_StateSources.EmailDomain': 'domain part only; the full address never leaves the org',
  'Gavel_StateSources.RecentActivity': 'last Task and Event descriptions and email bodies on the record within 90 days',
  'Gavel_StateSources.Input': 'text passed to the action by the caller',
  'Gavel_ServiceSources.LinkedArticle': 'Summary of the Knowledge article attached to the email case',
  'Gavel_StateSources.RecordImage': 'the latest PNG or JPEG file on the record or its inbound emails, sent as an image (jev-1.14.0). Images are not redacted: anything visible in the photo, such as a shipping label, leaves the org',
};
const out = [];
out.push('# Data leaving your org', '');
out.push('This page lists every field each shipped Gavel definition sends to the judgment provider (TypeSafe Jev by default). Nothing else leaves the org. `scripts/docs-egress-check.sh` fails CI when a definition sends a field that is not listed here.', '');
out.push('How sending works:', '');
out.push('- Egress is off after install (`Gavel_Ops_Config__mdt.Egress_Enabled__c = false`). While it is off, no call is made and every run is ledgered as `SKIP egress_disabled`.');
out.push('- Only the fields below are read, with the running user\'s sharing and field-level security (`WITH USER_MODE` and `Security.stripInaccessible`). Unreadable or empty values are left out.');
out.push('- Text is redacted before it is serialized: matches become `[REDACTED:<type>]` and the ledger records only `type:count`. Redaction is best-effort pattern matching, not DLP.');
out.push('- Text is cut at the listed maximum with a `[truncated]` marker.');
out.push('- The ledger stores a SHA-256 hash of what was sent, not the text, unless an admin turns on `Store_State__c`.');
out.push('- Images (only definitions pinned to jev-1.14.0 or later) are sent as files with the TypeSafe image opt-in header. They are not redacted or truncated. The ledger keeps only their SHA-256 digest, never the bytes.');
out.push('- Labels and feedback are never sent to the provider.');
out.push('- TypeSafe data retention and processing terms are not yet verified (OQ-1). Treat egress as sending data to a third-party processor until that is resolved.', '');
let pack = null;
for (const d of decisions) {
  const p = v(d, 'Pack__c') || 'core';
  if (p !== pack) {
    out.push(`# Pack: ${p}`, '');
    pack = p;
  }
  out.push(`## ${d.devName}`, '');
  out.push(`${v(d, 'Description__c')} Target object: \`${v(d, 'Target_Object__c')}\`. Installs in **${v(d, 'Mode__c')}**.`, '');
  out.push('| Field path | State key | Required | Max chars | Redaction | Notes |', '|---|---|---|---|---|---|');
  const fields = recs.filter((r) => r.type === 'Gavel_State_Field' && v(r, 'Decision__c') === d.devName)
    .sort((a, b) => Number(v(a, 'Order__c') || 0) - Number(v(b, 'Order__c') || 0));
  for (const f of fields) {
    const src = v(f, 'Source__c');
    const note = src ? (SOURCE_NOTE[src.split(':')[0]] || src) : 'field value';
    out.push(`| \`${v(f, 'Field_Path__c')}\` | ${v(f, 'State_Key__c')} | ${v(f, 'Required__c') === 'true' ? 'yes' : 'no'} | ${Number(v(f, 'Max_Chars__c'))} | ${PROFILE[v(f, 'Redaction_Profile__c') || 'strict']} | ${note} |`);
  }
  if (d.devName === 'Gavel_Input_Screen') {
    out.push('', 'Intake screening flows fill `input.text` from `Case.Subject` and `Case.Description` (Email-to-Case) or `Lead.Company` and `Lead.Description` (Web-to-Lead). Agent actions pass the text the agent is about to read.');
  }
  if (d.devName === 'Gavel_KB_Coverage') {
    out.push('', 'Also sent as answer options: the Id, Title and Summary (first 2,000 characters) of up to 20 online Knowledge articles found by SOSL on the case subject (max 50).');
  }
  out.push('');
}
const target = path.join(ROOT, 'docs', 'guides', 'data-leaving-your-org.md');
fs.mkdirSync(path.dirname(target), { recursive: true });
fs.writeFileSync(target, out.join('\n'));
console.log(`wrote ${path.relative(ROOT, target)} (${decisions.length} definitions)`);
