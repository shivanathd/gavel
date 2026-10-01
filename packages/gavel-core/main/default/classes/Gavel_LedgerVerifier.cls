/**
 * Walks a definition's hash chain and reports the first break (LEDG-001.4, AS-6.3).
 * Starts from the latest retention purge anchor when one exists.
 */
public without sharing class Gavel_LedgerVerifier {
    public class Result {
        public String definition;
        public Boolean ok = true;
        public Integer checked = 0;
        public Decimal brokenAtSeq;
        public Id brokenEntryId;
        public String reason;
    }

    public static Result verify(String definition) {
        Result r = new Result();
        r.definition = definition;
        String expectedPrev = null;
        Decimal expectedSeq = 1;
        List<Gavel_Ledger_Purge__c> anchors = [
            SELECT Last_Purged_Seq__c, Last_Purged_Hash__c
            FROM Gavel_Ledger_Purge__c
            WHERE Definition__c = :definition AND Last_Purged_Seq__c != NULL
            ORDER BY Last_Purged_Seq__c DESC
            LIMIT 1
        ];
        if (!anchors.isEmpty()) {
            expectedPrev = anchors[0].Last_Purged_Hash__c;
            expectedSeq = anchors[0].Last_Purged_Seq__c + 1;
        }
        for (Gavel_Decision_Log__c e : [
            SELECT Id, Record_Id__c, Object__c, Definition__c, Version__c, Definition_Hash__c, Mode__c, Outcome__c,
                Reason__c, Idempotency_Key__c, Running_User__c, Model_Version__c, State_Hash__c, State_JSON__c,
                Redaction_Summary__c, State_Truncated__c, Answers_JSON__c, Answers_Truncated__c, Answers_Hash__c,
                Provider_Status__c, Latency_Ms__c, Http_Status__c, Cache_Hit__c, Action_Taken__c, Action_Suppressed__c,
                Asymmetric_Reason__c, Top_Choice__c, Top_Confidence__c, Run_At__c, Chain_Seq__c, Prev_Hash__c, Entry_Hash__c
            FROM Gavel_Decision_Log__c
            WHERE Definition__c = :definition AND Chain_Seq__c != NULL
            ORDER BY Chain_Seq__c ASC
            LIMIT 50000
        ]) {
            r.checked++;
            String failure = null;
            if (e.Chain_Seq__c != expectedSeq) {
                failure = 'sequence_gap';
            } else if (!(e.Prev_Hash__c == null ? '' : e.Prev_Hash__c).equals(expectedPrev == null ? '' : expectedPrev)) {
                failure = 'prev_hash_mismatch';
            } else if (!Gavel_Ledger.entryHash(e).equals(e.Entry_Hash__c == null ? '' : e.Entry_Hash__c)) {
                failure = 'entry_hash_mismatch';
            }
            if (failure != null) {
                r.ok = false;
                r.brokenAtSeq = expectedSeq;
                r.brokenEntryId = e.Id;
                r.reason = failure;
                Gavel_Alerts.raise('ledger_tamper_detected', Gavel_Alerts.CRITICAL, definition, 'Hash chain broken at entry ' + expectedSeq + ' (' + failure + ')');
                Gavel_Alerts.flush();
                return r;
            }
            expectedPrev = e.Entry_Hash__c;
            expectedSeq = e.Chain_Seq__c + 1;
        }
        return r;
    }
}
