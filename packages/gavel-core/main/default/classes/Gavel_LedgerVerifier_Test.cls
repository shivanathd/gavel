@IsTest
private class Gavel_LedgerVerifier_Test {
    private static void writeChain(String definition, Integer n) {
        List<Gavel_Decision_Log__c> rows = new List<Gavel_Decision_Log__c>();
        for (Integer i = 1; i <= n; i++) {
            Gavel_Decision_Log__c e = Gavel_Ledger.newEntry(null, definition, null, definition + i);
            e.Outcome__c = Math.mod(i, 2) == 0 ? 'AUTO' : 'REVIEW';
            e.Reason__c = 'test';
            e.Answers_JSON__c = '{"i":' + i + '}';
            e.Top_Confidence__c = 0.8123;
            e.Latency_Ms__c = 120 + i;
            rows.add(e);
        }
        Gavel_Ledger.write(rows);
    }

    @IsTest
    static void chainsAreIndependentPerDefinition() {
        writeChain('Chain_A', 5);
        writeChain('Chain_B', 3);
        writeChain('Chain_A', 2);
        Gavel_LedgerVerifier.Result a = Gavel_LedgerVerifier.verify('Chain_A');
        Gavel_LedgerVerifier.Result b = Gavel_LedgerVerifier.verify('Chain_B');
        Assert.isTrue(a.ok, 'detail: ' + a.reason);
        Assert.areEqual(7, a.checked);
        Assert.isTrue(b.ok, 'detail: ' + b.reason);
        Assert.areEqual(3, b.checked);
        Assert.areEqual(1, [SELECT Chain_Seq__c FROM Gavel_Decision_Log__c WHERE Definition__c = 'Chain_B' ORDER BY Chain_Seq__c LIMIT 1].Chain_Seq__c);
        Gavel_Decision_Log__c first = [SELECT Prev_Hash__c FROM Gavel_Decision_Log__c WHERE Definition__c = 'Chain_A' AND Chain_Seq__c = 1];
        Assert.isNull(first.Prev_Hash__c, 'genesis entry has no previous hash');
    }

    @IsTest
    static void prevHashBreakDetected() {
        writeChain('Chain_P', 4);
        Gavel_Decision_Log__c second = [SELECT Id FROM Gavel_Decision_Log__c WHERE Definition__c = 'Chain_P' AND Chain_Seq__c = 2];
        Gavel_Ledger.tamperForTest(second.Id, 'Prev_Hash__c', '0'.repeat(64));
        Gavel_LedgerVerifier.Result r = Gavel_LedgerVerifier.verify('Chain_P');
        Assert.isFalse(r.ok);
        Assert.areEqual(2, r.brokenAtSeq);
        Assert.areEqual('prev_hash_mismatch', r.reason);
    }

    @IsTest
    static void deletionLeavesDetectableGap() {
        writeChain('Chain_G', 4);
        Gavel_Decision_Log__c third = [SELECT Id FROM Gavel_Decision_Log__c WHERE Definition__c = 'Chain_G' AND Chain_Seq__c = 3];
        // Simulate a deletion that bypassed retention (no purge summary written).
        Gavel_Ledger.bypass = Gavel_Ledger.BYPASS_RETENTION;
        delete third;
        Gavel_Ledger.bypass = null;
        Gavel_LedgerVerifier.Result r = Gavel_LedgerVerifier.verify('Chain_G');
        Assert.isFalse(r.ok);
        Assert.areEqual(3, r.brokenAtSeq);
        Assert.areEqual('sequence_gap', r.reason);
    }

    @IsTest
    static void hashIsStableAcrossReload() {
        writeChain('Chain_S', 1);
        Gavel_Decision_Log__c e = [
            SELECT Id, Record_Id__c, Object__c, Definition__c, Version__c, Definition_Hash__c, Mode__c, Outcome__c,
                Reason__c, Idempotency_Key__c, Running_User__c, Model_Version__c, State_Hash__c, State_JSON__c,
                Redaction_Summary__c, State_Truncated__c, Answers_JSON__c, Answers_Truncated__c, Answers_Hash__c,
                Provider_Status__c, Latency_Ms__c, Http_Status__c, Cache_Hit__c, Action_Taken__c, Action_Suppressed__c,
                Asymmetric_Reason__c, Top_Choice__c, Top_Confidence__c, Run_At__c, Chain_Seq__c, Prev_Hash__c, Entry_Hash__c
            FROM Gavel_Decision_Log__c WHERE Definition__c = 'Chain_S'
        ];
        Assert.areEqual(e.Entry_Hash__c, Gavel_Ledger.entryHash(e), 'stored values hash the same as in-memory values');
        Assert.isTrue(Gavel_LedgerVerifier.verify('Nothing_Here').ok);
    }
}
