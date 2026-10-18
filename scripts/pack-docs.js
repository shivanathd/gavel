#!/usr/bin/env node
/* Regenerates the generated part of docs/packs/<pack>.md from shipped metadata (DOC-001.3). */
'use strict';
const fs = require('fs');
const path = require('path');
const { loadRecords } = require('./hash-definitions');

const ROOT = path.resolve(__dirname, '..');
const recs = loadRecords();
const v = (r, f) => (r.values[f] === undefined || r.values[f] === null ? '' : String(r.values[f]).trim());
const START = '<!-- generated:start -->';
const END = '<!-- generated:end -->';

function packTables(pack) {
  const out = [];
  for (const d of recs.filter((r) => r.type === 'Gavel_Decision' && v(r, 'Pack__c') === pack).sort((a, b) => a.devName.localeCompare(b.devName))) {
    out.push(`### ${d.devName}`, '');
    out.push(`${v(d, 'Description__c')}`, '');
    out.push(`- Target object: \`${v(d, 'Target_Object__c')}\``);
    out.push(`- Install mode: **${v(d, 'Mode__c')}**${v(d, 'Auto_Apply__c') === 'false' ? ' with auto-apply off (Live-Review)' : ''}`);
    out.push(`- Daily budget: ${v(d, 'Daily_Budget_Calls__c') ? Number(v(d, 'Daily_Budget_Calls__c')) + ' calls' : 'unlimited'}`);
    out.push(`- Provider config: \`${v(d, 'Provider_Config__c')}\``, '');
    out.push('| Question | Type | Options | Auto accept | Review at | Min margin | Noul direction |', '|---|---|---|---|---|---|---|');
    const qs = recs.filter((r) => r.type === 'Gavel_Question' && v(r, 'Decision__c') === d.devName).sort((a, b) => Number(v(a, 'Order__c')) - Number(v(b, 'Order__c')));
    for (const q of qs) {
      const opts = recs.filter((o) => o.type === 'Gavel_Option' && v(o, 'Question__c') === q.devName).sort((a, b) => Number(v(a, 'Order__c')) - Number(v(b, 'Order__c')))
        .map((o) => `\`${v(o, 'Key__c')}\`${v(o, 'Is_Escape__c') === 'true' ? ' (escape)' : ''}`).join(', ');
      const p = recs.find((r) => r.type === 'Gavel_Policy' && v(r, 'Decision__c') === d.devName && v(r, 'Question_Key__c') === v(q, 'Key__c'));
      const optText = v(q, 'Option_Source__c') ? `runtime: ${v(q, 'Option_Source__c')}`
        : v(q, 'Type__c') === 'box' ? (v(q, 'Box_Gate__c') ? `location, kept when \`${v(q, 'Box_Gate__c')}\` is true` : 'location')
        : (opts || 'true / false');
      out.push(`| \`${v(q, 'Key__c')}\`: ${v(q, 'Prompt__c')} | ${v(q, 'Type__c')} | ${optText} | ${p ? Number(v(p, 'Auto_Accept__c')) : '-'} | ${p ? Number(v(p, 'Review_At__c')) : '-'} | ${p && v(p, 'Min_Margin__c') ? Number(v(p, 'Min_Margin__c')) : '-'} | ${p ? v(p, 'Noul_Direction__c') || '-' : '-'} |`);
    }
    const asym = recs.filter((r) => r.type === 'Gavel_Policy' && v(r, 'Decision__c') === d.devName && v(r, 'Asymmetric_Reason__c'));
    for (const a of asym) out.push('', `Asymmetric policy on \`${v(a, 'Question_Key__c')}\`: ${v(a, 'Asymmetric_Reason__c')}`);
    const acts = recs.filter((r) => r.type === 'Gavel_Action_Map' && v(r, 'Decision__c') === d.devName);
    if (acts.length) {
      out.push('', 'Actions (Live and AUTO only):', '');
      for (const a of acts) out.push(`- \`${v(a, 'Question_Key__c')}\` = \`${v(a, 'Answer_Value__c')}\`: ${v(a, 'Action_Type__c')} \`${v(a, 'Action_Target__c')}\` = \`${v(a, 'Action_Value__c')}\``);
    }
    out.push('', `Data sent: see [Data leaving your org](../guides/data-leaving-your-org.md#${d.devName.toLowerCase()}).`, '');
  }
  return out.join('\n');
}

for (const pack of ['agentforce-gate', 'service', 'sales-marketing']) {
  const file = path.join(ROOT, 'docs', 'packs', `${pack}.md`);
  const text = fs.readFileSync(file, 'utf8');
  const i = text.indexOf(START);
  const j = text.indexOf(END);
  if (i < 0 || j < 0) throw new Error(`${file} needs generated markers`);
  fs.writeFileSync(file, text.slice(0, i + START.length) + '\n\n' + packTables(pack) + '\n' + text.slice(j));
  console.log(`updated docs/packs/${pack}.md`);
}
