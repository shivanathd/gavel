/**
 * The only writer of Gavel_Decision_Log__c (F6, contracts/ledger-contract.md).
 *
 * Runs in system mode on purpose: a decision must be recorded even when the running user has no access
 * to the ledger object, and the immutability trigger only accepts writes that come through this class.
 *  - write(): final entries, hash-chained per definition (LEDG-001.4), one DML, fallback event on failure (LEDG-001.7)
 *  - insertPending()/finalizeEntries(): async runs insert one PENDING entry that is finalized exactly once
 *  - purge(): retention only (LEDG-001.5)
 */
public without sharing class Gavel_Ledger {
    public static final String BYPASS_RETENTION = 'RETENTION';
    public static final String BYPASS_FINALIZE = 'FINALIZE';
    public static final String IMMUTABLE = 'gavel_ledger_immutable';
    public static final String RUNTIME_ONLY = 'gavel_ledger_runtime_only';
    private static final String CHAIN_PREFIX = 'chain:';

    @TestVisible
    private static String bypass;
    @TestVisible
    private static Boolean runtimeInsert = false;

    public static Boolean isRuntimeInsert() {
        return runtimeInsert == true;
    }

    public static String activeBypass() {
        return bypass;
    }

    /** Base entry with the contract's always-required fields. */
    public static Gavel_Decision_Log__c newEntry(Gavel_Definition def, String definitionApiName, Id recordId, String idempotencyKey) {
        Gavel_Decision_Log__c e = new Gavel_Decision_Log__c();
        e.Record_Id__c = recordId == null ? 'none' : String.valueOf(recordId);
        e.Object__c = recordId == null ? (def == null ? null : def.targetObject) : recordId.getSObjectType().getDescribe().getName();
        e.Definition__c = def == null ? definitionApiName : def.apiName;
        e.Version__c = def == null || def.version == null ? 0 : def.version;
        e.Definition_Hash__c = def == null ? null : def.definitionHash;
        e.Mode__c = def == null ? null : def.mode;
        e.Idempotency_Key__c = idempotencyKey;
        e.Running_User__c = UserInfo.getUserId();
        e.Run_At__c = nowToSecond();
        if (recordId != null) {
            String objectName = e.Object__c;
            if (objectName == 'Case') {
                e.Case__c = recordId;
            } else if (objectName == 'Lead') {
                e.Lead__c = recordId;
            } else if (objectName == 'Contact') {
                e.Contact__c = recordId;
            } else if (objectName == 'Opportunity') {
                e.Opportunity__c = recordId;
            }
        }
        return e;
    }

    public static Datetime nowToSecond() {
        Datetime n = System.now();
        return Datetime.newInstanceGmt(n.yearGmt(), n.monthGmt(), n.dayGmt(), n.hourGmt(), n.minuteGmt(), n.secondGmt());
    }

    /** Inserts final entries (chained). Returns the same list with Ids where the insert succeeded. */
    public static List<Gavel_Decision_Log__c> write(List<Gavel_Decision_Log__c> entries) {
        if (entries == null || entries.isEmpty()) {
            return entries;
        }
        try {
            chain(entries);
        } catch (Exception e) {
            // Never lose the entry: write it unchained; the verifier will report the gap.
            Gavel_Alerts.raise('ledger_chain_failed', Gavel_Alerts.CRITICAL, entries[0].Definition__c, 'Hash chain head could not be locked');
        }
        runtimeInsert = true;
        List<Database.SaveResult> results;
        try {
            results = Database.insert(entries, false);
        } finally {
            runtimeInsert = false;
        }
        List<Gavel_Decision_Log__c> failed = new List<Gavel_Decision_Log__c>();
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                failed.add(entries[i]);
            }
        }
        fallback(failed);
        return entries;
    }

    /** Idempotency keys with an entry in the last N seconds (duplicate_inflight), across all users. */
    public static Set<String> recentKeys(Set<String> keys, Integer seconds) {
        Datetime since = System.now().addSeconds(-seconds);
        Set<String> found = new Set<String>();
        for (Gavel_Decision_Log__c e : [
            SELECT Idempotency_Key__c FROM Gavel_Decision_Log__c
            WHERE Idempotency_Key__c IN :keys AND CreatedDate >= :since
        ]) {
            found.add(e.Idempotency_Key__c);
        }
        return found;
    }

    public static Map<Id, Gavel_Decision_Log__c> load(Set<Id> ids) {
        return new Map<Id, Gavel_Decision_Log__c>([
            SELECT Id, Record_Id__c, Object__c, Definition__c, Version__c, Definition_Hash__c, Mode__c, Outcome__c,
                Reason__c, Idempotency_Key__c, Running_User__c, Model_Version__c, State_Hash__c, Answers_JSON__c,
                Answers_Truncated__c, Action_Taken__c, Action_Suppressed__c, Run_At__c, Case__c, Lead__c,
                Contact__c, Opportunity__c, Top_Choice__c, Top_Confidence__c
            FROM Gavel_Decision_Log__c
            WHERE Id IN :ids
        ]);
    }

    public static Set<Id> idsWithAppliedActions(Set<Id> ledgerIds) {
        Set<Id> result = new Set<Id>();
        for (Gavel_Action_Log__c l : [
            SELECT Decision_Log__c FROM Gavel_Action_Log__c
            WHERE Decision_Log__c IN :ledgerIds AND Status__c = 'applied'
        ]) {
            result.add(l.Decision_Log__c);
        }
        return result;
    }

    /** Action logs are insert-only too and are written through the same runtime gate. */
    public static void insertActionLogs(List<Gavel_Action_Log__c> logs) {
        runtimeInsert = true;
        try {
            Database.insert(logs, false);
        } finally {
            runtimeInsert = false;
        }
    }

    /** PENDING entries for async runs. Not chained until finalized. */
    public static List<Gavel_Decision_Log__c> insertPending(List<Gavel_Decision_Log__c> entries) {
        for (Gavel_Decision_Log__c e : entries) {
            e.Outcome__c = Gavel_Outcome.PENDING;
            if (e.Reason__c == null) {
                e.Reason__c = 'queued';
            }
        }
        runtimeInsert = true;
        try {
            insert entries;
        } finally {
            runtimeInsert = false;
        }
        return entries;
    }

    /** One-time PENDING -> final transition (see PROGRESS.md B3). Entries must carry the pending Id. */
    public static void finalizeEntries(List<Gavel_Decision_Log__c> entries) {
        if (entries == null || entries.isEmpty()) {
            return;
        }
        // Only rows that are still PENDING can be finalized; never advance the chain head for a row the trigger will reject.
        Set<Id> ids = new Set<Id>();
        for (Gavel_Decision_Log__c e : entries) {
            ids.add(e.Id);
        }
        Set<Id> stillPending = new Map<Id, Gavel_Decision_Log__c>([
            SELECT Id FROM Gavel_Decision_Log__c WHERE Id IN :ids AND Outcome__c = 'PENDING'
        ]).keySet();
        List<Gavel_Decision_Log__c> finalizable = new List<Gavel_Decision_Log__c>();
        for (Gavel_Decision_Log__c e : entries) {
            if (stillPending.contains(e.Id)) {
                finalizable.add(e);
            }
        }
        if (finalizable.isEmpty()) {
            return;
        }
        entries = finalizable;
        chain(entries);
        bypass = BYPASS_FINALIZE;
        try {
            Database.update(entries, false);
        } finally {
            bypass = null;
        }
    }

    /** Retention purge: deletes entries and records a purge summary that anchors the chain. */
    public static Gavel_Ledger_Purge__c purge(String definition, List<Gavel_Decision_Log__c> entries, Datetime cutoff) {
        if (entries == null || entries.isEmpty()) {
            return null;
        }
        Gavel_Decision_Log__c last = null;
        for (Gavel_Decision_Log__c e : entries) {
            if (e.Chain_Seq__c != null && (last == null || e.Chain_Seq__c > last.Chain_Seq__c)) {
                last = e;
            }
        }
        Gavel_Ledger_Purge__c summary = new Gavel_Ledger_Purge__c(
            Definition__c = definition,
            Purged_Count__c = entries.size(),
            Last_Purged_Seq__c = last == null ? null : last.Chain_Seq__c,
            Last_Purged_Hash__c = last == null ? null : last.Entry_Hash__c,
            Cutoff__c = cutoff,
            Purged_At__c = System.now()
        );
        bypass = BYPASS_RETENTION;
        try {
            delete entries;
        } finally {
            bypass = null;
        }
        insert summary;
        return summary;
    }

    /** Test hook for AS-6.3: alters a stored hash through the retention bypass. */
    @TestVisible
    private static void tamperForTest(Id entryId, String field, Object value) {
        Gavel_Decision_Log__c e = new Gavel_Decision_Log__c(Id = entryId);
        e.put(field, value);
        bypass = BYPASS_RETENTION;
        try {
            update e;
        } finally {
            bypass = null;
        }
    }

    /** Subscriber side of Gavel_Ledger_Fallback__e: re-insert entries whose first insert failed. */
    public static void replay(List<Gavel_Ledger_Fallback__e> events) {
        List<Gavel_Decision_Log__c> entries = new List<Gavel_Decision_Log__c>();
        for (Gavel_Ledger_Fallback__e ev : events) {
            try {
                Gavel_Decision_Log__c e = (Gavel_Decision_Log__c) JSON.deserialize(ev.Payload__c, Gavel_Decision_Log__c.class);
                e.Id = null;
                entries.add(e);
            } catch (Exception ex) {
                Gavel_Alerts.raise('ledger_fallback_unreadable', Gavel_Alerts.CRITICAL, null, 'Fallback payload could not be read');
            }
        }
        if (!entries.isEmpty()) {
            runtimeInsert = true;
            List<Database.SaveResult> results;
            try {
                results = Database.insert(entries, false);
            } finally {
                runtimeInsert = false;
            }
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    Gavel_Alerts.raise('ledger_write_failed', Gavel_Alerts.CRITICAL, entries[i].Definition__c, 'Ledger entry could not be written after fallback');
                }
            }
        }
        Gavel_Alerts.flush();
    }

    private static void fallback(List<Gavel_Decision_Log__c> failed) {
        if (failed.isEmpty()) {
            return;
        }
        List<Gavel_Ledger_Fallback__e> events = new List<Gavel_Ledger_Fallback__e>();
        for (Gavel_Decision_Log__c e : failed) {
            String payload = JSON.serialize(e);
            if (payload.length() > 131072) {
                Gavel_Alerts.raise('ledger_write_failed', Gavel_Alerts.CRITICAL, e.Definition__c, 'Ledger entry too large for fallback');
                continue;
            }
            events.add(new Gavel_Ledger_Fallback__e(Payload__c = payload));
        }
        if (events.isEmpty()) {
            return;
        }
        List<Database.SaveResult> published = EventBus.publish(events);
        for (Database.SaveResult r : published) {
            if (!r.isSuccess()) {
                Gavel_Alerts.raise('ledger_write_failed', Gavel_Alerts.CRITICAL, null, 'Ledger fallback event could not be published');
            }
        }
    }

    /** Assigns Chain_Seq__c, Prev_Hash__c and Entry_Hash__c per definition under a row lock on the chain head. */
    private static void chain(List<Gavel_Decision_Log__c> entries) {
        Set<String> keys = new Set<String>();
        for (Gavel_Decision_Log__c e : entries) {
            keys.add(CHAIN_PREFIX + e.Definition__c);
        }
        Map<String, Gavel_Counter__c> heads = new Map<String, Gavel_Counter__c>();
        for (Gavel_Counter__c c : [SELECT Id, Key__c, Count__c, Value__c FROM Gavel_Counter__c WHERE Key__c IN :keys FOR UPDATE]) {
            heads.put(c.Key__c, c);
        }
        for (String k : keys) {
            if (!heads.containsKey(k)) {
                heads.put(k, new Gavel_Counter__c(Name = k.abbreviate(80), Key__c = k, Count__c = 0, Value__c = ''));
            }
        }
        for (Gavel_Decision_Log__c e : entries) {
            Gavel_Counter__c head = heads.get(CHAIN_PREFIX + e.Definition__c);
            Decimal seq = (head.Count__c == null ? 0 : head.Count__c) + 1;
            e.Chain_Seq__c = seq;
            e.Prev_Hash__c = String.isBlank(head.Value__c) ? null : head.Value__c;
            e.Entry_Hash__c = entryHash(e);
            head.Count__c = seq;
            head.Value__c = e.Entry_Hash__c;
            head.Updated_At__c = System.now();
        }
        upsert heads.values() Gavel_Counter__c.Key__c;
    }

    /** SHA-256 over the previous hash and every content field (format "gavel-ledger-v1"). */
    public static String entryHash(Gavel_Decision_Log__c e) {
        List<String> parts = new List<String>{
            'gavel-ledger-v1',
            'prev=' + s(e.Prev_Hash__c),
            'seq=' + n(e.Chain_Seq__c),
            'record=' + s(e.Record_Id__c),
            'object=' + s(e.Object__c),
            'definition=' + s(e.Definition__c),
            'version=' + n(e.Version__c),
            'definitionHash=' + s(e.Definition_Hash__c),
            'mode=' + s(e.Mode__c),
            'outcome=' + s(e.Outcome__c),
            'reason=' + s(e.Reason__c),
            'idempotency=' + s(e.Idempotency_Key__c),
            'user=' + s(e.Running_User__c),
            'model=' + s(e.Model_Version__c),
            'stateHash=' + s(e.State_Hash__c),
            'state=' + s(e.State_JSON__c),
            'redactions=' + s(e.Redaction_Summary__c),
            'truncated=' + b(e.State_Truncated__c),
            'answers=' + s(e.Answers_JSON__c),
            'answersTruncated=' + b(e.Answers_Truncated__c),
            'answersHash=' + s(e.Answers_Hash__c),
            'providerStatus=' + s(e.Provider_Status__c),
            'latency=' + n(e.Latency_Ms__c),
            'http=' + n(e.Http_Status__c),
            'cache=' + b(e.Cache_Hit__c),
            'action=' + s(e.Action_Taken__c),
            'suppressed=' + b(e.Action_Suppressed__c),
            'asymmetric=' + s(e.Asymmetric_Reason__c),
            'topChoice=' + s(e.Top_Choice__c),
            'topConfidence=' + n(e.Top_Confidence__c),
            'runAt=' + (e.Run_At__c == null ? '' : e.Run_At__c.formatGmt('yyyy-MM-dd HH:mm:ss'))
        };
        List<String> encoded = new List<String>();
        for (String p : parts) {
            encoded.add(p.length() + ':' + p);
        }
        return Gavel_Json.sha256Hex(String.join(encoded, '\n'));
    }

    private static String s(Object v) {
        return v == null ? '' : String.valueOf(v);
    }

    private static String n(Decimal v) {
        if (v == null) {
            return '';
        }
        return v == 0 ? '0' : v.stripTrailingZeros().toPlainString();
    }

    private static String b(Boolean v) {
        return v == true ? 'true' : 'false';
    }
}
