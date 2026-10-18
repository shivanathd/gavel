#!/usr/bin/env node
/*
 * Export and import Gavel definitions as JSON (DEF-001.7).
 *
 *   node scripts/gavel-definition.js export Gavel_Case_Triage > triage.json
 *   node scripts/gavel-definition.js import triage.json --package gavel-pack-service [--prefix CT2]
 *
 * Import writes Custom Metadata records (all fields explicit) and then runs hash-definitions --write, which
 * refuses a changed definition whose Version__c was not bumped.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { loadRecords } = require('./hash-definitions');

const ROOT = path.resolve(__dirname, '..');
const pick = (rec, fields) => Object.fromEntries(fields.map((f) => [f, rec.values[f] === undefined ? null : rec.values[f]]));

function exportDefinition(name) {
  const records = loadRecords();
  const decision = records.find((r) => r.type === 'Gavel_Decision' && r.devName === name);
  if (!decision) throw new Error(`definition ${name} not found`);
  const questions = records.filter((r) => r.type === 'Gavel_Question' && r.values.Decision__c === name);
  return {
    format: 'gavel-definition-v1',
    apiName: name,
    label: (decision.xml.match(/<label>([^<]*)<\/label>/) || [])[1] || name,
    decision: pick(decision, ['Target_Object__c', 'Version__c', 'Mode__c', 'Provider_Config__c', 'Description__c', 'Owner_Email__c',
      'Daily_Budget_Calls__c', 'Pack__c', 'Review_Queue__c', 'Auto_Apply__c', 'Timeout_Ms__c']),
    questions: questions.map((q) => ({
      ...pick(q, ['Key__c', 'Type__c', 'Prompt__c', 'Instructions__c', 'Order__c', 'Required_For_Action__c', 'Stage__c', 'Option_Source__c', 'Box_Gate__c']),
      options: records.filter((o) => o.type === 'Gavel_Option' && o.values.Question__c === q.devName)
        .map((o) => pick(o, ['Key__c', 'Label__c', 'Description__c', 'Level__c', 'Is_Escape__c', 'Order__c'])),
    })),
    stateFields: records.filter((r) => r.type === 'Gavel_State_Field' && r.values.Decision__c === name)
      .map((s) => pick(s, ['Field_Path__c', 'State_Key__c', 'Required__c', 'Max_Chars__c', 'Redaction_Profile__c', 'Zero_Is_Meaningful__c', 'Source__c', 'Order__c'])),
    policies: records.filter((r) => r.type === 'Gavel_Policy' && r.values.Decision__c === name)
      .map((p) => pick(p, ['Question_Key__c', 'Auto_Accept__c', 'Review_At__c', 'Min_Margin__c', 'Noul_Direction__c', 'Asymmetric_Reason__c'])),
    actionMaps: records.filter((r) => r.type === 'Gavel_Action_Map' && r.values.Decision__c === name)
      .map((a) => pick(a, ['Question_Key__c', 'Answer_Value__c', 'Action_Type__c', 'Action_Target__c', 'Action_Value__c'])),
  };
}

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const NUMBER_FIELDS = new Set(['Version__c', 'Daily_Budget_Calls__c', 'Timeout_Ms__c', 'Order__c', 'Level__c', 'Max_Chars__c', 'Auto_Accept__c', 'Review_At__c', 'Min_Margin__c']);
const BOOL_FIELDS = new Set(['Auto_Apply__c', 'Required_For_Action__c', 'Is_Escape__c', 'Required__c', 'Zero_Is_Meaningful__c']);

function recordXml(label, values) {
  const lines = ['<?xml version="1.0" encoding="UTF-8"?>',
    '<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">',
    `    <label>${esc(label.slice(0, 40))}</label>`, '    <protected>false</protected>'];
  for (const [k, v] of Object.entries(values)) {
    lines.push('    <values>', `        <field>${k}</field>`);
    if (v === null || v === undefined || v === '') {
      lines.push(BOOL_FIELDS.has(k) ? '        <value xsi:type="xsd:boolean">false</value>' : '        <value xsi:nil="true"/>');
    } else if (BOOL_FIELDS.has(k)) {
      lines.push(`        <value xsi:type="xsd:boolean">${String(v) === 'true'}</value>`);
    } else if (NUMBER_FIELDS.has(k)) {
      lines.push(`        <value xsi:type="xsd:double">${Number(v)}</value>`);
    } else {
      lines.push(`        <value xsi:type="xsd:string">${esc(v)}</value>`);
    }
    lines.push('    </values>');
  }
  lines.push('</CustomMetadata>', '');
  return lines.join('\n');
}

function importDefinition(file, pkg, prefix) {
  const d = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (d.format !== 'gavel-definition-v1') throw new Error('not a gavel-definition-v1 file');
  const dir = path.join(ROOT, 'packages', pkg, 'main', 'default', 'customMetadata');
  fs.mkdirSync(dir, { recursive: true });
  const p = prefix || d.apiName.replace(/^Gavel_/, '').replace(/[^A-Za-z0-9]/g, '').slice(0, 10);
  const write = (type, dev, label, values) => fs.writeFileSync(path.join(dir, `${type}.${dev}.md-meta.xml`), recordXml(label, values));
  write('Gavel_Decision', d.apiName, d.label, { ...d.decision, Definition_Hash__c: null });
  d.questions.forEach((q, i) => {
    const qdev = `Gavel_${p}_Q${i + 1}`;
    const { options, ...qv } = q;
    write('Gavel_Question', qdev, `${d.label} ${q.Key__c}`, { Decision__c: d.apiName, ...qv });
    (options || []).forEach((o, j) => write('Gavel_Option', `${qdev}_O${j + 1}`, `${q.Key__c} ${o.Key__c}`, { Question__c: qdev, ...o }));
  });
  d.stateFields.forEach((s, i) => write('Gavel_State_Field', `Gavel_${p}_S${i + 1}`, `${d.label} ${s.State_Key__c}`, { Decision__c: d.apiName, ...s }));
  d.policies.forEach((s, i) => write('Gavel_Policy', `Gavel_${p}_P${i + 1}`, `${d.label} ${s.Question_Key__c}`, { Decision__c: d.apiName, ...s }));
  d.actionMaps.forEach((s, i) => write('Gavel_Action_Map', `Gavel_${p}_A${i + 1}`, `${d.label} ${s.Question_Key__c}`, { Decision__c: d.apiName, ...s }));
  execFileSync(process.execPath, [path.join(__dirname, 'hash-definitions.js'), '--write'], { stdio: 'inherit' });
}

function main() {
  const [cmd, arg, ...rest] = process.argv.slice(2);
  try {
    if (cmd === 'export' && arg) {
      process.stdout.write(JSON.stringify(exportDefinition(arg), null, 2) + '\n');
    } else if (cmd === 'import' && arg) {
      const pkgIdx = rest.indexOf('--package');
      const preIdx = rest.indexOf('--prefix');
      if (pkgIdx < 0) throw new Error('--package is required');
      importDefinition(arg, rest[pkgIdx + 1], preIdx >= 0 ? rest[preIdx + 1] : null);
    } else {
      console.error('Usage: gavel-definition.js export <ApiName> | import <file.json> --package <dir> [--prefix <X>]');
      process.exit(2);
    }
  } catch (e) {
    console.error(`gavel-definition: ${e.message}`);
    process.exit(1);
  }
}

main();
