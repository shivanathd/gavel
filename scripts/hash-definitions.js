#!/usr/bin/env node
/*
 * Gavel definition hasher (ADR-009). Byte-identical with Gavel_DefinitionHasher.cls ("gavel-def-v1").
 *
 *   node scripts/hash-definitions.js --check        verify stored hashes and the lock file (CI)
 *   node scripts/hash-definitions.js --write        refresh Definition_Hash__c and gavel-definitions.lock.json
 *   node scripts/hash-definitions.js --print NAME   print the canonical text for one definition
 *
 * A definition whose canonical content changed while Version__c stayed the same fails --check and
 * --write: bump Version__c first (DEF-001.3). No dependencies beyond Node.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
const LOCK = path.join(ROOT, 'gavel-definitions.lock.json');

function decodeXml(s) {
  return s
    .replace(/&#x([0-9a-fA-F]+);/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(parseInt(d, 10)))
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&');
}

function parseRecord(file) {
  const xml = fs.readFileSync(file, 'utf8').replace(/\r\n?/g, '\n');
  const base = path.basename(file).replace(/\.md-meta\.xml$/, '');
  const dot = base.indexOf('.');
  const type = base.slice(0, dot);
  const devName = base.slice(dot + 1);
  const values = {};
  const re = /<values>\s*<field>([^<]+)<\/field>\s*(?:<value\s+xsi:nil="true"\s*\/>|<value(?:\s+[^>]*)?\/>|<value(?:\s+[^>]*)?>([\s\S]*?)<\/value>)\s*<\/values>/g;
  let m;
  while ((m = re.exec(xml)) !== null) {
    values[m[1].trim()] = m[2] === undefined ? null : decodeXml(m[2]);
  }
  return { file, xml, type, devName, values };
}

function loadRecords() {
  const out = [];
  const pkgs = path.join(ROOT, 'packages');
  if (!fs.existsSync(pkgs)) return out;
  for (const p of fs.readdirSync(pkgs)) {
    const dir = path.join(pkgs, p, 'main', 'default', 'customMetadata');
    if (!fs.existsSync(dir)) continue;
    for (const f of fs.readdirSync(dir)) {
      if (f.endsWith('.md-meta.xml') && f.startsWith('Gavel_')) out.push(parseRecord(path.join(dir, f)));
    }
  }
  return out;
}

// --- canonical form (keep in sync with Gavel_DefinitionHasher.cls) ---
const trim = (s) => s.replace(/^[\x00-\x20]+|[\x00-\x20]+$/g, '');
const str = (v) => (v === null || v === undefined ? '' : trim(String(v)));
function num(v) {
  const s = str(v);
  if (s === '') return '';
  const n = Number(s);
  if (Number.isNaN(n)) throw new Error(`not a number: ${s}`);
  if (n === 0) return '0';
  return String(n);
}
function bool(rec, field) {
  const v = rec.values[field];
  if (v === undefined) {
    throw new Error(`${rec.file}: checkbox ${field} must be set explicitly (true/false)`);
  }
  return str(v) === 'true' ? 'true' : 'false';
}
const rec = (tag, pairs) => tag + ' ' + pairs.map(([k, v]) => `${k}=${v.length}:${v}`).join(';');
const sortKey = (vals) => vals.map((v) => `${v.length}:${v}`).join(';');
const lexical = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

function byType(records, type) {
  return records.filter((r) => r.type === type);
}

function buildDefinitions(records) {
  const configs = {};
  for (const c of byType(records, 'Gavel_Provider_Config')) configs[c.devName] = c;
  const questions = byType(records, 'Gavel_Question');
  const options = byType(records, 'Gavel_Option');
  const states = byType(records, 'Gavel_State_Field');
  const policies = byType(records, 'Gavel_Policy');
  const actions = byType(records, 'Gavel_Action_Map');
  const defs = {};
  for (const d of byType(records, 'Gavel_Decision')) {
    const v = (f) => d.values[f];
    const cfg = configs[str(v('Provider_Config__c'))];
    const lines = ['gavel-def-v1'];
    lines.push(rec('decision', [
      ['DeveloperName', str(d.devName)],
      ['Target_Object__c', str(v('Target_Object__c'))],
      ['Version__c', num(v('Version__c'))],
      ['Provider_Config__c', str(v('Provider_Config__c'))],
      ['Model__c', str(cfg ? cfg.values['Model__c'] : null)],
    ]));

    const qs = {};
    for (const q of questions.filter((q) => str(q.values['Decision__c']) === d.devName)) {
      qs[sortKey([str(q.values['Key__c'])])] = q;
    }
    for (const k of Object.keys(qs).sort(lexical)) {
      const q = qs[k];
      const qv = (f) => q.values[f];
      lines.push(rec('question', [
        ['Key__c', str(qv('Key__c'))],
        ['Type__c', str(qv('Type__c'))],
        ['Prompt__c', str(qv('Prompt__c'))],
        ['Instructions__c', str(qv('Instructions__c'))],
        ['Order__c', num(qv('Order__c'))],
        ['Required_For_Action__c', bool(q, 'Required_For_Action__c')],
        ['Stage__c', str(qv('Stage__c'))],
        ['Option_Source__c', str(qv('Option_Source__c'))],
        // Added in 1.2.1: hashed only when set, so definitions without a gate keep their hash.
        ...(str(qv('Box_Gate__c')) ? [['Box_Gate__c', str(qv('Box_Gate__c'))]] : []),
      ]));
      const os = {};
      for (const o of options.filter((o) => str(o.values['Question__c']) === q.devName)) {
        os[sortKey([str(o.values['Key__c'])])] = o;
      }
      for (const ok of Object.keys(os).sort(lexical)) {
        const o = os[ok];
        const ov = (f) => o.values[f];
        lines.push(rec('option', [
          ['Question_Key__c', str(qv('Key__c'))],
          ['Key__c', str(ov('Key__c'))],
          ['Label__c', str(ov('Label__c'))],
          ['Description__c', str(ov('Description__c'))],
          ['Level__c', num(ov('Level__c'))],
          ['Is_Escape__c', bool(o, 'Is_Escape__c')],
          ['Order__c', num(ov('Order__c'))],
        ]));
      }
    }

    const ss = {};
    for (const s of states.filter((s) => str(s.values['Decision__c']) === d.devName)) {
      ss[sortKey([str(s.values['State_Key__c']), str(s.values['Field_Path__c'])])] = s;
    }
    for (const k of Object.keys(ss).sort(lexical)) {
      const s = ss[k];
      const sv = (f) => s.values[f];
      lines.push(rec('state', [
        ['Field_Path__c', str(sv('Field_Path__c'))],
        ['State_Key__c', str(sv('State_Key__c'))],
        ['Required__c', bool(s, 'Required__c')],
        ['Max_Chars__c', num(sv('Max_Chars__c'))],
        ['Redaction_Profile__c', str(sv('Redaction_Profile__c'))],
        ['Zero_Is_Meaningful__c', bool(s, 'Zero_Is_Meaningful__c')],
        ['Source__c', str(sv('Source__c'))],
        ['Order__c', num(sv('Order__c'))],
      ]));
    }

    const ps = {};
    for (const p of policies.filter((p) => str(p.values['Decision__c']) === d.devName)) {
      ps[sortKey([str(p.values['Question_Key__c'])])] = p;
    }
    for (const k of Object.keys(ps).sort(lexical)) {
      const pv = (f) => ps[k].values[f];
      lines.push(rec('policy', [
        ['Question_Key__c', str(pv('Question_Key__c'))],
        ['Auto_Accept__c', num(pv('Auto_Accept__c'))],
        ['Review_At__c', num(pv('Review_At__c'))],
        ['Min_Margin__c', num(pv('Min_Margin__c'))],
        ['Noul_Direction__c', str(pv('Noul_Direction__c'))],
        ['Asymmetric_Reason__c', str(pv('Asymmetric_Reason__c'))],
      ]));
    }

    const as = {};
    for (const a of actions.filter((a) => str(a.values['Decision__c']) === d.devName)) {
      const av = (f) => str(a.values[f]);
      as[sortKey([av('Question_Key__c'), av('Answer_Value__c'), av('Action_Type__c'), av('Action_Target__c'), av('Action_Value__c')])] = a;
    }
    for (const k of Object.keys(as).sort(lexical)) {
      const av = (f) => str(as[k].values[f]);
      lines.push(rec('action', [
        ['Question_Key__c', av('Question_Key__c')],
        ['Answer_Value__c', av('Answer_Value__c')],
        ['Action_Type__c', av('Action_Type__c')],
        ['Action_Target__c', av('Action_Target__c')],
        ['Action_Value__c', av('Action_Value__c')],
      ]));
    }

    const canonical = lines.join('\n');
    defs[d.devName] = {
      record: d,
      version: num(v('Version__c')),
      stored: str(v('Definition_Hash__c')),
      canonical,
      hash: crypto.createHash('sha256').update(canonical, 'utf8').digest('hex'),
    };
  }
  return defs;
}

function writeHash(def) {
  const r = def.record;
  const field = '<field>Definition_Hash__c</field>';
  const value = `<value xsi:type="xsd:string">${def.hash}</value>`;
  let xml;
  const re = /(<values>\s*<field>Definition_Hash__c<\/field>\s*)(<value[^>]*\/>|<value[^>]*>[\s\S]*?<\/value>)/;
  if (re.test(r.xml)) {
    xml = r.xml.replace(re, `$1${value}`);
  } else {
    xml = r.xml.replace('</CustomMetadata>', `    <values>\n        ${field}\n        ${value}\n    </values>\n</CustomMetadata>`);
  }
  fs.writeFileSync(r.file, xml);
}

function main() {
  const args = process.argv.slice(2);
  const mode = args.includes('--write') ? 'write' : args.includes('--print') ? 'print' : 'check';
  const defs = buildDefinitions(loadRecords());
  if (mode === 'print') {
    const name = args[args.indexOf('--print') + 1];
    if (!defs[name]) {
      console.error(`unknown definition ${name}`);
      process.exit(2);
    }
    process.stdout.write(defs[name].canonical + '\n');
    return;
  }
  const lock = fs.existsSync(LOCK) ? JSON.parse(fs.readFileSync(LOCK, 'utf8')) : {};
  const problems = [];
  for (const [name, d] of Object.entries(defs).sort(([a], [b]) => lexical(a, b))) {
    const locked = lock[name];
    if (locked && locked.version === d.version && locked.hash !== d.hash) {
      problems.push(`${name}: content changed but Version__c is still ${d.version}; bump the version`);
      continue;
    }
    if (mode === 'write') {
      if (d.stored !== d.hash) writeHash(d);
      lock[name] = { version: d.version, hash: d.hash };
      console.log(`${name} v${d.version} ${d.hash}`);
    } else {
      if (d.stored !== d.hash) problems.push(`${name}: Definition_Hash__c ${d.stored || '(blank)'} != computed ${d.hash}`);
      if (!locked) problems.push(`${name}: not in gavel-definitions.lock.json (run --write)`);
    }
  }
  if (mode === 'write') {
    for (const name of Object.keys(lock)) if (!defs[name]) delete lock[name];
    const sorted = {};
    for (const k of Object.keys(lock).sort(lexical)) sorted[k] = lock[k];
    fs.writeFileSync(LOCK, JSON.stringify(sorted, null, 2) + '\n');
  }
  if (problems.length) {
    for (const p of problems) console.error(`hash-definitions: ${p}`);
    process.exit(1);
  }
  if (mode === 'check') console.log(`hash-definitions: ${Object.keys(defs).length} definitions OK`);
}

if (require.main === module) main();
module.exports = { buildDefinitions, loadRecords, parseRecord };
