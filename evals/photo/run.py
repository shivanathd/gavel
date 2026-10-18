#!/usr/bin/env python3
"""
Live photo eval: labelled photos through Gavel.run in a scratch org, against real Jev.

  python3 evals/photo/run.py fetch            # download the Wikimedia photos into evals/photo/.cache/
  python3 evals/photo/run.py records upload   # create Cases, Assets, Products, Work Orders; attach the photos
  python3 evals/photo/run.py run              # one Gavel.run per case (sf apex run), results in .cache/results.json
  python3 evals/photo/run.py score            # compare with the labels in cases.json

The org must have Gavel installed, egress on and the TypeSafe key set: see .claude/skills/verify/SKILL.md.
GAVEL_ORG names the org (default gavel-eval). Every case makes one real, billed call.
"""
import base64, json, os, re, subprocess, sys, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, '.cache')
ORG = os.environ.get('GAVEL_ORG', 'gavel-eval')
CASES = json.load(open(os.path.join(HERE, 'cases.json')))
IDS = os.path.join(CACHE, 'ids.json')
RESULTS = os.path.join(CACHE, 'results.json')
UA = {'User-Agent': 'GavelPhotoEval/1.0 (https://github.com/shivanathd/gavel)'}
GATES = {'damage_area': 'damage_visible', 'parcel_area': 'parcel_visible', 'total_area': 'total_visible'}


def load(path):
    return json.load(open(path)) if os.path.exists(path) else {}


def image_path(ref):
    if isinstance(ref, str):
        return os.path.join(HERE, ref)
    return os.path.join(CACHE, re.sub(r'\W', '_', ref['wikimedia']) + '.jpg')


def sf(args, stdin=None):
    r = subprocess.run(['sf', *args, '-o', ORG, '--json'], capture_output=True, text=True, input=stdin)
    return json.loads(r.stdout)


def apex(src):
    path = os.path.join(CACHE, 'tmp.apex')
    open(path, 'w').write(src)
    d = sf(['apex', 'run', '--file', path])
    if d.get('status') != 0 or not d['result'].get('success'):
        raise RuntimeError(json.dumps(d)[:600])
    # Match the debug lines only: the log also echoes the source, which contains the same marker.
    return re.findall(r'\|ERROR\|EVAL (.*)', d['result']['logs'])


def q(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'") + "'"


def fetch():
    for c in CASES:
        for ref in [c['img'], c.get('catalog')]:
            if not isinstance(ref, dict) or os.path.exists(image_path(ref)):
                continue
            # Thumbnail that fits 1280x1568, inside TypeSafe's 280..1568 px per side.
            p = {'action': 'query', 'titles': ref['wikimedia'], 'prop': 'imageinfo', 'iiprop': 'url',
                 'iiurlwidth': 1280, 'iiurlheight': 1568, 'format': 'json'}
            for attempt in range(5):
                try:
                    api = urllib.request.Request('https://commons.wikimedia.org/w/api.php?' + urllib.parse.urlencode(p), headers=UA)
                    page = next(iter(json.load(urllib.request.urlopen(api, timeout=30))['query']['pages'].values()))
                    url = page['imageinfo'][0]['thumburl']
                    open(image_path(ref), 'wb').write(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read())
                    break
                except urllib.error.HTTPError as e:
                    if e.code != 429:
                        raise
                    time.sleep(20 * (attempt + 1))
            print('fetched', ref['wikimedia'], flush=True)
            time.sleep(4)


def records():
    lines = ["Account acct = new Account(Name='Gavel Photo Eval'); insert acct;"]
    for c in CASES:
        v = 'r' + re.sub(r'\W', '', c['id'])
        if c['defn'] == 'Gavel_Work_Completion':
            lines.append(f"WorkOrder {v} = new WorkOrder(Subject={q(c['job']['subject'])}, Description={q(c['job']['description'])}); insert {v};")
            lines.append(f"System.debug(LoggingLevel.ERROR, 'EVAL {c['id']} ' + {v}.Id);")
        elif c['defn'] == 'Gavel_Product_Photo_Check':
            lines.append(f"Product2 {v} = new Product2(Name={q(c['name'])}, ProductCode={q(c['id'])}); insert {v};")
            lines.append(f"System.debug(LoggingLevel.ERROR, 'EVAL {c['id']} ' + {v}.Id);")
        else:
            prod, asset = 'null', 'null'
            if 'catalog' in c:
                lines.append(f"Product2 p{v} = new Product2(Name={q(c['product'])}, ProductCode={q(c['id'])}); insert p{v};")
                prod = f'p{v}.Id'
            if 'product' in c:
                lines.append(f"Asset a{v} = new Asset(Name={q(c['product'])}, AccountId=acct.Id, Product2Id={prod}, PurchaseDate=Date.today().addDays(-5), Price=40); insert a{v};")
                asset = f'a{v}.Id'
            desc = c.get('claim', 'Warranty claim, receipt attached.')
            lines.append(f"Case {v} = new Case(Subject={q('EVAL ' + c['id'])}, Description={q(desc)}, Origin='Web', Status='New', AccountId=acct.Id, AssetId={asset}); insert {v};")
            lines.append(f"System.debug(LoggingLevel.ERROR, 'EVAL {c['id']} ' + {v}.Id + ' ' + {prod});")
    ids = {}
    for line in apex('\n'.join(lines)):
        p = line.split()
        ids[p[0]] = {'rec': p[1], 'prod': p[2] if len(p) > 2 and p[2] != 'null' else None}
    json.dump(ids, open(IDS, 'w'), indent=1)
    print('records', len(ids))


def upload():
    ids = load(IDS)
    for c in CASES:
        r = ids[c['id']]
        for target, ref in [(r['rec'], c['img'])] + ([(r['prod'], c['catalog'])] if c.get('catalog') else []):
            if r.get('uploaded_' + target):
                continue
            path = image_path(ref)
            body = json.dumps({'Title': os.path.basename(path), 'PathOnClient': os.path.basename(path), 'FirstPublishLocationId': target,
                               'VersionData': base64.b64encode(open(path, 'rb').read()).decode()})
            out = subprocess.run(['sf', 'api', 'request', 'rest', '/services/data/v64.0/sobjects/ContentVersion', '--method', 'POST',
                                  '--body', '-', '-o', ORG], capture_output=True, text=True, input=body).stdout
            ok = '"success":true' in out.replace(' ', '')
            r['uploaded_' + target] = ok
            print('upload', c['id'], os.path.basename(path), ok, flush=True)
        json.dump(ids, open(IDS, 'w'), indent=1)


RUN = """Gavel_Runtime.RunResult r = Gavel.run('__ID__', '__DEF__');
Gavel_Decision_Log__c e = r.ledgerId == null ? null : [SELECT Model_Version__c, Http_Status__c, Answers_JSON__c, Latency_Ms__c, Cache_Hit__c FROM Gavel_Decision_Log__c WHERE Id = :r.ledgerId];
System.debug(LoggingLevel.ERROR, 'EVAL ' + JSON.serialize(new Map<String, Object>{ 'outcome' => r.outcome, 'reason' => r.reason,
    'answers' => r.answerValues, 'perQ' => r.perQuestion, 'model' => e == null ? null : e.Model_Version__c,
    'http' => e == null ? null : e.Http_Status__c, 'ms' => e == null ? null : e.Latency_Ms__c,
    'cache' => e == null ? null : e.Cache_Hit__c, 'raw' => e == null ? null : e.Answers_JSON__c }).replace('\\n', ' '));"""


def run():
    ids, res = load(IDS), load(RESULTS)
    for c in CASES:
        if c['id'] in res and res[c['id']].get('reason') != 'duplicate_inflight':
            continue
        out = apex(RUN.replace('__ID__', ids[c['id']]['rec']).replace('__DEF__', c['defn']))
        res[c['id']] = json.loads(out[-1])
        print(c['id'], res[c['id']]['outcome'], res[c['id']]['reason'], flush=True)
        json.dump(res, open(RESULTS, 'w'), indent=1)


def score():
    res, tally, boxes = load(RESULTS), {}, {'kept_right': 0, 'kept_wrong': 0, 'dropped_right': 0, 'dropped_wrong': 0}
    for c in CASES:
        r = res.get(c['id'])
        if not r or not r.get('raw'):
            print(c['id'], 'no result', r and r.get('reason'))
            continue
        answers = json.loads(r['raw'])['answers']
        for key, expected in c['expect'].items():
            p = answers.get(key, {}).get('probability')
            route = (r['perQ'].get(key) or '?').split(':')[0]
            right = p is not None and (p >= 0.5) == expected
            bucket = ('right' if right else 'WRONG') + ('+auto' if route == 'AUTO' else '+review')
            tally[bucket] = tally.get(bucket, 0) + 1
            if not right:
                print('MISS', c['id'], key, 'expected', expected, 'p', p, r['perQ'].get(key))
        for box, gate in GATES.items():
            if box not in answers or gate not in answers:
                continue
            # A box should be kept exactly when the thing is there; the label of the gate Noul says whether it is.
            there = c['expect'].get(gate)
            if there is None:
                continue
            kept = r['answers'].get(box) is not None
            boxes[('kept_' if kept else 'dropped_') + ('right' if kept == there else 'wrong')] += 1
            print('BOX', c['id'], box, 'kept' if kept else 'dropped', 'confidence', answers[box].get('confidence'), r['perQ'].get(box))
    print('labels', tally)
    print('boxes', boxes)


if __name__ == '__main__':
    os.makedirs(CACHE, exist_ok=True)
    steps = {'fetch': fetch, 'records': records, 'upload': upload, 'run': run, 'score': score}
    for step in sys.argv[1:] or ['score']:
        steps[step]()
