/**
 * Runs decisions end to end: definition -> guardrails -> state -> provider -> policy -> actions -> ledger.
 * Every run produces exactly one ledger entry, including SKIP and ERROR (LEDG-001.1). Never throws (ADR-005).
 *
 * Phase 1 does every read and callout; phase 2 does all DML (actions, ledger, action logs, reviews,
 * counters), so callouts never follow uncommitted work.
 */
public with sharing class Gavel_Runtime {
    public static final Integer DUPLICATE_WINDOW_SECONDS = 60;
    public static final String DEFERRED = 'deferred';

    public class RunRequest {
        public Id recordId;
        public String definitionApiName;
        /** Direct inputs for record-less definitions (Screen Input, Action Risk). */
        public Map<String, Object> inputs;
        /** When set, finalizes this PENDING ledger entry instead of inserting a new one. */
        public Gavel_Decision_Log__c pendingEntry;
        /** False for the sync Flow action: AUTO actions wait for Apply Outcome. */
        public Boolean applyActions = true;
        /** Retries are only allowed in async context. */
        public Boolean isAsync = false;

        public RunRequest() {
        }

        public RunRequest(Id recordId, String definitionApiName) {
            this.recordId = recordId;
            this.definitionApiName = definitionApiName;
        }
    }

    public class RunResult {
        public String definitionApiName;
        public Id recordId;
        public String outcome;
        public String reason;
        public Id ledgerId;
        public String topChoice;
        public Decimal topConfidence;
        public String answersJson;
        public Boolean cacheHit = false;
        public String actionTaken;
        public Boolean actionSuppressed = false;
        public Id reviewId;
        public Map<String, String> perQuestion = new Map<String, String>();
        public Map<String, String> answerValues = new Map<String, String>();
        public Gavel_JudgmentResponse response;
    }

    public class ApplyResult {
        public Id ledgerId;
        public Boolean applied = false;
        public String actions;
    }

    private class RunState {
        public Integer index;
        public RunRequest req;
        public RunResult res = new RunResult();
        public Gavel_Definition def;
        public Gavel_StateBuilder.StateResult state;
        public Gavel_JudgmentResponse resp;
        public Gavel_Outcome outcome;
        public Gavel_Decision_Log__c entry;
        public Boolean done = false;
        public String idempotencyKey;
    }

    public static RunResult run(RunRequest req) {
        return runAll(new List<RunRequest>{ req })[0];
    }

    public static RunResult run(Id recordId, String definitionApiName) {
        return run(new RunRequest(recordId, definitionApiName));
    }

    public static List<RunResult> runAll(List<RunRequest> requests) {
        List<RunState> runs = new List<RunState>();
        Set<String> names = new Set<String>();
        for (Integer i = 0; i < requests.size(); i++) {
            RunState r = new RunState();
            r.index = i;
            r.req = requests[i];
            r.res.definitionApiName = r.req.definitionApiName;
            r.res.recordId = r.req.recordId;
            runs.add(r);
            if (r.req.definitionApiName != null) {
                names.add(r.req.definitionApiName);
            }
        }
        Map<String, Gavel_Definition> defs = new Map<String, Gavel_Definition>();
        try {
            defs = Gavel_DefinitionRepo.getAll(names);
        } catch (Exception e) {
            defs = new Map<String, Gavel_Definition>();
        }

        // Duplicate in-flight detection (same record + definition + version within 60s).
        Set<String> keys = new Set<String>();
        for (RunState r : runs) {
            r.def = defs.get(r.req.definitionApiName);
            r.idempotencyKey = r.req.pendingEntry != null ? r.req.pendingEntry.Idempotency_Key__c : idempotencyKey(r.req, r.def);
            if (r.req.pendingEntry == null && r.req.recordId != null && r.def != null) {
                keys.add(r.idempotencyKey);
            }
        }
        Set<String> recent = keys.isEmpty() ? new Set<String>() : Gavel_Ledger.recentKeys(keys, DUPLICATE_WINDOW_SECONDS);
        Set<String> seenInBatch = new Set<String>();

        // Phase 1: reads and callouts only.
        for (RunState r : runs) {
            try {
                Boolean duplicate = false;
                if (r.req.pendingEntry == null && r.req.recordId != null && r.def != null) {
                    duplicate = recent.contains(r.idempotencyKey) || seenInBatch.contains(r.idempotencyKey);
                    seenInBatch.add(r.idempotencyKey);
                }
                judge(r, duplicate);
            } catch (Exception e) {
                finish(r, Gavel_Outcome.ERROR, 'internal_error:' + e.getTypeName());
            }
        }

        // Phase 2: DML.
        persist(runs);
        List<RunResult> results = new List<RunResult>();
        for (RunState r : runs) {
            results.add(r.res);
        }
        return results;
    }

    private static void judge(RunState r, Boolean duplicate) {
        r.entry = baseEntry(r);
        Gavel_Definition def = r.def;
        if (def == null) {
            finish(r, Gavel_Outcome.ERROR, 'definition_not_found');
            return;
        }
        if (def.mode == Gavel_Definition.MODE_RETIRED) {
            finish(r, Gavel_Outcome.SKIP, 'definition_retired');
            return;
        }
        Gavel_DefinitionValidator.Result validation = Gavel_DefinitionValidator.validate(def);
        if (!validation.valid) {
            String code = validation.firstError();
            if (code == 'definition_hash_mismatch') {
                Gavel_Alerts.raise('definition_hash_mismatch', Gavel_Alerts.CRITICAL, def.apiName, 'Definition changed without a version bump');
            }
            finish(r, Gavel_Outcome.ERROR, code);
            return;
        }
        if (duplicate) {
            finish(r, Gavel_Outcome.SKIP, 'duplicate_inflight');
            return;
        }
        if (!Gavel_Config.ops().egressEnabled) {
            finish(r, Gavel_Outcome.SKIP, Gavel_StateBuilder.EGRESS_DISABLED);
            return;
        }
        Gavel_Guardrails.Decision pre = Gavel_Guardrails.preflight(def);
        if (!pre.allowed) {
            finish(r, Gavel_Outcome.SKIP, pre.reason);
            return;
        }
        r.state = Gavel_StateBuilder.build(r.req.recordId, def, r.req.inputs);
        stampState(r);
        if (r.state.blockedReason == Gavel_StateBuilder.BAD_FIELD_PATH) {
            Gavel_Alerts.raise('bad_field_path', Gavel_Alerts.CRITICAL, def.apiName, 'Unknown field path: ' + String.join(r.state.badPaths, ', '));
            finish(r, Gavel_Outcome.ERROR, Gavel_StateBuilder.BAD_FIELD_PATH);
            return;
        }
        if (r.state.blockedReason != null) {
            finish(r, Gavel_Outcome.SKIP, r.state.blockedReason);
            return;
        }

        Gavel_JudgmentRequest jr = new Gavel_JudgmentRequest();
        jr.definitionApiName = def.apiName;
        jr.definitionVersion = def.version;
        jr.model = def.model;
        jr.state = r.state.state;
        jr.stateJson = r.state.stateJson;
        jr.assets = r.state.assets;
        jr.timeoutMs = def.timeoutMs;
        jr.live = def.isLive();
        jr.allowRetry = r.req.isAsync == true;
        jr.namedCredential = def.namedCredential;
        jr.endpointPath = def.endpointPath;
        jr.questions = new List<Gavel_Question>();
        Boolean dynamicOptions = false;
        for (Gavel_Question q : def.questions) {
            if (String.isNotBlank(q.optionSource)) {
                dynamicOptions = true;
                List<Gavel_Option> opts;
                try {
                    opts = runtimeOptions(r, q);
                } catch (Gavel_SkipException skip) {
                    finish(r, Gavel_Outcome.SKIP, skip.getMessage());
                    return;
                }
                if (opts == null) {
                    finish(r, Gavel_Outcome.ERROR, 'option_source_failed');
                    return;
                }
                jr.questions.add(q.cloneWithOptions(opts));
            } else {
                jr.questions.add(q);
            }
        }

        Gavel_JudgmentResponse resp = Gavel_Guardrails.cached(def, r.state.stateHash);
        if (resp != null) {
            r.res.cacheHit = true;
            r.entry.Cache_Hit__c = true;
        } else {
            Gavel_JudgmentProvider prov = provider(def);
            if (prov == null) {
                finish(r, Gavel_Outcome.ERROR, 'provider_not_found');
                return;
            }
            try {
                resp = prov.judge(jr);
            } catch (Exception e) {
                resp = Gavel_JudgmentResponse.failure(Gavel_JudgmentResponse.INVALID_RESPONSE, null, 'provider_exception:' + e.getTypeName());
            }
            if (resp == null) {
                resp = Gavel_JudgmentResponse.failure(Gavel_JudgmentResponse.INVALID_RESPONSE, null, 'provider_returned_null');
            }
            Gavel_Guardrails.record(def, resp);
            Gavel_Guardrails.cachePut(def, r.state.stateHash, resp);
        }
        r.resp = resp;
        r.res.response = resp;

        // Evaluate against the questions actually asked (runtime options included).
        Gavel_Definition asked = dynamicOptions ? def.copyWithQuestions(jr.questions) : def;
        Gavel_Outcome o = Gavel_PolicyEngine.evaluate(asked, resp);
        if (resp.status == Gavel_JudgmentResponse.INVALID_REQUEST && resp.errorCode != null) {
            o.reason = resp.errorCode;
        }
        r.outcome = o;
        stampJudgment(r);
        finish(r, o.outcome, o.reason);
    }

    private static List<Gavel_Option> runtimeOptions(RunState r, Gavel_Question q) {
        try {
            // "Class" or "Class:args"; the source reads its own args from question.optionSource.
            Type t = Type.forName(q.optionSource.substringBefore(':').trim());
            Object instance = t == null ? null : t.newInstance();
            if (!(instance instanceof Gavel_OptionSource)) {
                return null;
            }
            return ((Gavel_OptionSource) instance).options(r.req.recordId, r.def, q, r.state.state);
        } catch (Gavel_SkipException skip) {
            throw skip;
        } catch (Exception e) {
            return null;
        }
    }

    private static Gavel_JudgmentProvider provider(Gavel_Definition def) {
        if (String.isBlank(def.providerClass)) {
            return null;
        }
        Type t = Type.forName(def.providerClass);
        if (t == null) {
            return null;
        }
        Object instance = t.newInstance();
        return instance instanceof Gavel_JudgmentProvider ? (Gavel_JudgmentProvider) instance : null;
    }

    /** recordId (or input hash) + definition + version: the duplicate_inflight key (F4 edge case). */
    public static String idempotencyKey(RunRequest req, Gavel_Definition def) {
        String version = def == null || def.version == null ? '0' : String.valueOf(def.version);
        String subject = req.recordId != null
            ? String.valueOf(req.recordId)
            : 'input-' + Gavel_Json.sha256Hex(Gavel_Json.canonical(req.inputs == null ? new Map<String, Object>() : req.inputs)).left(16);
        return (subject + ':' + req.definitionApiName + ':' + version).abbreviate(255);
    }

    private static Gavel_Decision_Log__c baseEntry(RunState r) {
        Gavel_Decision_Log__c e = Gavel_Ledger.newEntry(r.def, r.req.definitionApiName, r.req.recordId, r.idempotencyKey);
        if (r.req.pendingEntry != null) {
            e.Id = r.req.pendingEntry.Id;
            e.Record_Id__c = r.req.pendingEntry.Record_Id__c;
            e.Definition__c = r.req.pendingEntry.Definition__c;
            e.Idempotency_Key__c = r.req.pendingEntry.Idempotency_Key__c;
        }
        return e;
    }

    private static void stampState(RunState r) {
        if (r.state == null) {
            return;
        }
        r.entry.State_Hash__c = r.state.stateHash;
        r.entry.Redaction_Summary__c = r.state.redactionSummary().abbreviate(255);
        r.entry.State_Truncated__c = r.state.truncated == true;
        if (Gavel_Config.ops().storeState && r.state.stateJson != null) {
            r.entry.State_JSON__c = r.state.stateJson.left(131072);
        }
    }

    private static void stampJudgment(RunState r) {
        Gavel_JudgmentResponse resp = r.resp;
        r.entry.Provider_Status__c = resp.status;
        r.entry.Model_Version__c = resp.modelVersion == null ? null : resp.modelVersion.abbreviate(80);
        r.entry.Latency_Ms__c = resp.latencyMs;
        r.entry.Http_Status__c = resp.httpStatus;
        r.entry.Asymmetric_Reason__c = r.outcome.asymmetricReason;

        Map<String, Object> outcomes = new Map<String, Object>();
        for (Gavel_Outcome.QuestionResult qr : r.outcome.questions.values()) {
            outcomes.put(qr.key, new Map<String, Object>{
                'type' => qr.questionType, 'outcome' => qr.outcome, 'reason' => qr.reason, 'answer' => qr.answerValue,
                'policyValue' => qr.policyValue, 'calibrationValue' => qr.calibrationValue, 'margin' => qr.margin,
                'participating' => qr.participating
            });
            r.res.perQuestion.put(qr.key, qr.outcome + ':' + qr.reason);
            r.res.answerValues.put(qr.key, qr.answerValue);
        }
        Map<String, Object> doc = new Map<String, Object>{
            'status' => resp.status, 'errorCode' => resp.errorCode, 'answers' => resp.answers,
            'outcomes' => outcomes, 'warnings' => resp.warnings
        };
        String full = JSON.serialize(doc);
        r.res.answersJson = full;
        r.entry.Answers_Hash__c = Gavel_Json.sha256Hex(full);
        if (full.length() > 32768) {
            r.entry.Answers_JSON__c = full.left(32768);
            r.entry.Answers_Truncated__c = true;
        } else {
            r.entry.Answers_JSON__c = full;
        }

        for (Gavel_Question q : r.def.questions) {
            if (q.isChoice() && resp.answers != null && resp.answers.containsKey(q.key) && resp.answers.get(q.key).isValid()) {
                Gavel_Answer a = resp.answers.get(q.key);
                r.res.topChoice = a.choice;
                r.res.topConfidence = a.confidence;
                r.entry.Top_Choice__c = a.choice == null ? null : a.choice.abbreviate(80);
                r.entry.Top_Confidence__c = a.confidence == null ? null : a.confidence.setScale(4);
                break;
            }
        }
    }

    private static void finish(RunState r, String outcome, String reason) {
        if (r.entry == null) {
            r.entry = baseEntry(r);
        }
        r.done = true;
        r.entry.Outcome__c = outcome;
        r.entry.Reason__c = reason == null ? null : reason.abbreviate(255);
        r.entry.Run_At__c = Gavel_Ledger.nowToSecond();
        if (reason == Gavel_StateBuilder.RECORD_NOT_FOUND) {
            // The record is gone: a lookup to it would make the ledger write fail. Record_Id__c keeps the id.
            r.entry.Case__c = null;
            r.entry.Lead__c = null;
            r.entry.Contact__c = null;
            r.entry.Opportunity__c = null;
        }
        if (r.outcome == null) {
            r.outcome = Gavel_Outcome.create(outcome, reason);
        }
        r.res.outcome = outcome;
        r.res.reason = r.entry.Reason__c;
    }

    private static void persist(List<RunState> runs) {
        // 1. Actions (Live + AUTO only).
        List<Gavel_ActionExecutor.Step> steps = new List<Gavel_ActionExecutor.Step>();
        for (RunState r : runs) {
            String taken = 'none';
            Boolean suppressed = r.outcome != null && r.outcome.actionSuppressed == true;
            if (suppressed) {
                taken = r.outcome.suppressReason;
            } else if (r.outcome != null && r.outcome.isAuto() && r.def != null && r.def.isLive()) {
                List<Gavel_ActionExecutor.Step> planned = Gavel_ActionExecutor.plan(r.def, r.req.recordId, r.outcome, r.index);
                if (!planned.isEmpty()) {
                    if (r.req.applyActions == false) {
                        taken = DEFERRED;
                    } else {
                        steps.addAll(planned);
                    }
                }
            }
            r.entry.Action_Taken__c = taken;
            r.entry.Action_Suppressed__c = suppressed;
        }
        Map<Integer, Gavel_ActionExecutor.RunActions> applied = new Map<Integer, Gavel_ActionExecutor.RunActions>();
        try {
            applied = Gavel_ActionExecutor.execute(steps);
        } catch (Exception e) {
            applied = new Map<Integer, Gavel_ActionExecutor.RunActions>();
        }
        for (RunState r : runs) {
            if (applied.containsKey(r.index)) {
                r.entry.Action_Taken__c = applied.get(r.index).text();
            }
        }

        // 2. Ledger: new entries are inserted, pending ones finalized.
        List<Gavel_Decision_Log__c> inserts = new List<Gavel_Decision_Log__c>();
        List<Gavel_Decision_Log__c> finals = new List<Gavel_Decision_Log__c>();
        for (RunState r : runs) {
            if (r.entry.Id == null) {
                inserts.add(r.entry);
            } else {
                finals.add(r.entry);
            }
        }
        try {
            Gavel_Ledger.write(inserts);
        } catch (Exception e) {
            Gavel_Alerts.raise('ledger_write_failed', Gavel_Alerts.CRITICAL, null, 'Ledger insert failed: ' + e.getTypeName());
        }
        try {
            Gavel_Ledger.finalizeEntries(finals);
        } catch (Exception e) {
            Gavel_Alerts.raise('ledger_write_failed', Gavel_Alerts.CRITICAL, null, 'Ledger finalize failed: ' + e.getTypeName());
        }

        // 3. Action logs and review items need ledger ids.
        List<Gavel_Action_Log__c> logs = new List<Gavel_Action_Log__c>();
        List<Gavel_ReviewService.Item> reviews = new List<Gavel_ReviewService.Item>();
        for (RunState r : runs) {
            r.res.ledgerId = r.entry.Id;
            r.res.actionTaken = r.entry.Action_Taken__c;
            r.res.actionSuppressed = r.entry.Action_Suppressed__c;
            if (applied.containsKey(r.index)) {
                for (Gavel_Action_Log__c l : applied.get(r.index).logs) {
                    l.Decision_Log__c = r.entry.Id;
                    logs.add(l);
                }
            }
            if (r.entry.Id != null && Gavel_ReviewService.needsReview(r.def, r.outcome)) {
                Gavel_ReviewService.Item item = new Gavel_ReviewService.Item();
                item.def = r.def;
                item.entry = r.entry;
                item.outcome = r.outcome;
                reviews.add(item);
            }
        }
        try {
            Gavel_ActionExecutor.writeLogs(logs);
        } catch (Exception e) {
            Gavel_Alerts.raise('action_log_failed', Gavel_Alerts.WARNING, null, 'Action log insert failed');
        }
        try {
            Map<Id, Gavel_Review__c> created = Gavel_ReviewService.create(reviews);
            for (RunState r : runs) {
                if (r.entry.Id != null && created.containsKey(r.entry.Id)) {
                    r.res.reviewId = created.get(r.entry.Id).Id;
                }
            }
        } catch (Exception e) {
            Gavel_Alerts.raise('review_create_failed', Gavel_Alerts.WARNING, null, 'Review item could not be created');
        }
        Gavel_Guardrails.flush();
        Gavel_Alerts.flush();
    }

    /**
     * Apply Outcome (FLOW-001.3): executes actions for a ledger entry that is AUTO on a Live definition whose
     * actions were deferred. Anything else returns applied=false with the reason. Never throws.
     */
    public static List<ApplyResult> applyOutcome(List<Id> ledgerIds) {
        List<ApplyResult> results = new List<ApplyResult>();
        Map<Id, Gavel_Decision_Log__c> entries = Gavel_Ledger.load(new Set<Id>(ledgerIds));
        Set<Id> alreadyApplied = Gavel_Ledger.idsWithAppliedActions(entries.keySet());
        List<Gavel_ActionExecutor.Step> steps = new List<Gavel_ActionExecutor.Step>();
        Map<Integer, ApplyResult> byIndex = new Map<Integer, ApplyResult>();
        for (Integer i = 0; i < ledgerIds.size(); i++) {
            ApplyResult ar = new ApplyResult();
            ar.ledgerId = ledgerIds[i];
            results.add(ar);
            try {
                Gavel_Decision_Log__c e = entries.get(ledgerIds[i]);
                if (e == null) {
                    ar.actions = 'ledger_entry_not_found';
                    continue;
                }
                if (e.Action_Suppressed__c == true) {
                    ar.actions = e.Action_Taken__c;
                    continue;
                }
                if (e.Outcome__c != Gavel_Outcome.AUTO) {
                    ar.actions = 'not_auto';
                    continue;
                }
                if (e.Mode__c != Gavel_Definition.MODE_LIVE) {
                    ar.actions = Gavel_PolicyEngine.SUPPRESS_SHADOW;
                    continue;
                }
                if (alreadyApplied.contains(e.Id) || e.Action_Taken__c != DEFERRED) {
                    ar.actions = 'already_applied_or_none';
                    continue;
                }
                Gavel_Definition def = Gavel_DefinitionRepo.get(e.Definition__c);
                if (def == null || !def.isLive() || def.version != e.Version__c || def.definitionHash != e.Definition_Hash__c) {
                    ar.actions = 'definition_changed';
                    continue;
                }
                if (def.autoApply != true) {
                    ar.actions = Gavel_PolicyEngine.SUPPRESS_AUTO_APPLY_OFF;
                    continue;
                }
                Gavel_Outcome o = outcomeFromLedger(e);
                Id recordId = toId(e.Record_Id__c);
                for (Gavel_ActionExecutor.Step s : Gavel_ActionExecutor.plan(def, recordId, o, i)) {
                    steps.add(s);
                }
                byIndex.put(i, ar);
            } catch (Exception ex) {
                ar.actions = 'error:' + ex.getTypeName();
            }
        }
        Map<Integer, Gavel_ActionExecutor.RunActions> applied = Gavel_ActionExecutor.execute(steps);
        List<Gavel_Action_Log__c> logs = new List<Gavel_Action_Log__c>();
        for (Integer i : byIndex.keySet()) {
            ApplyResult ar = byIndex.get(i);
            Gavel_ActionExecutor.RunActions ra = applied.get(i);
            if (ra == null) {
                ar.actions = 'none';
                continue;
            }
            ar.applied = ra.applied > 0;
            ar.actions = ra.text();
            for (Gavel_Action_Log__c l : ra.logs) {
                l.Decision_Log__c = ar.ledgerId;
                logs.add(l);
            }
        }
        Gavel_ActionExecutor.writeLogs(logs);
        Gavel_Alerts.flush();
        return results;
    }

    private static Id toId(String value) {
        try {
            return String.isBlank(value) ? null : Id.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }

    /** Rebuilds per-question outcomes from Answers_JSON__c ("outcomes" map). */
    @TestVisible
    private static Gavel_Outcome outcomeFromLedger(Gavel_Decision_Log__c e) {
        Gavel_Outcome o = Gavel_Outcome.create(e.Outcome__c, e.Reason__c);
        if (String.isBlank(e.Answers_JSON__c) || e.Answers_Truncated__c == true) {
            return o;
        }
        Map<String, Object> doc = (Map<String, Object>) JSON.deserializeUntyped(e.Answers_JSON__c);
        Object raw = doc.get('outcomes');
        if (raw instanceof Map<String, Object>) {
            Map<String, Object> outcomes = (Map<String, Object>) raw;
            for (String k : outcomes.keySet()) {
                Map<String, Object> q = (Map<String, Object>) outcomes.get(k);
                Gavel_Outcome.QuestionResult qr = new Gavel_Outcome.QuestionResult();
                qr.key = k;
                qr.outcome = (String) q.get('outcome');
                qr.reason = (String) q.get('reason');
                qr.answerValue = (String) q.get('answer');
                qr.participating = q.get('participating') instanceof Boolean && (Boolean) q.get('participating');
                o.questions.put(k, qr);
            }
        }
        return o;
    }
}
