@IsTest
private class Gavel_Ledger_Test {
    private static Gavel_Definition liveTriage(String name) {
        Gavel_Definition d = Gavel_TestFactory.triage(name);
        d.mode = Gavel_Definition.MODE_LIVE;
        return Gavel_TestFactory.register(d);
    }

    private static List<Gavel_Decision_Log__c> entriesFor(String definition) {
        return [
            SELECT Id, Record_Id__c, Object__c, Definition__c, Version__c, Definition_Hash__c, Mode__c, Outcome__c, Reason__c,
                Idempotency_Key__c, Running_User__c, Model_Version__c, State_Hash__c, Answers_JSON__c, Latency_Ms__c,
                Http_Status__c, Chain_Seq__c, Entry_Hash__c, Prev_Hash__c, Case__c, Action_Taken__c, Action_Suppressed__c,
                Redaction_Summary__c, Provider_Status__c, CreatedDate
            FROM Gavel_Decision_Log__c
            WHERE Definition__c = :definition
            ORDER BY Chain_Seq__c
        ];
    }

    // AS-6.1 Error still ledgered
    @IsTest
    static void errorStillLedgered() {
        Gavel_TestFactory.ops(true);
        liveTriage('Ledger_Timeout');
        Gavel_MockProvider.failWith('Ledger_Timeout', 'timeout', null);
        Case c = Gavel_TestFactory.newCase('Help', 'The portal is down');
        insert c;
        Gavel_Runtime.RunResult r = Gavel_Runtime.run(c.Id, 'Ledger_Timeout');
        Assert.areEqual('ERROR', r.outcome);
        Assert.areEqual('timeout', r.reason);
        List<Gavel_Decision_Log__c> entries = entriesFor('Ledger_Timeout');
        Assert.areEqual(1, entries.size(), 'exactly one entry');
        Gavel_Decision_Log__c e = entries[0];
        Assert.areEqual('ERROR', e.Outcome__c);
        Assert.areEqual('timeout', e.Reason__c);
        Assert.areEqual(r.ledgerId, e.Id);
        // Contract: always-required fields
        Assert.areEqual(String.valueOf(c.Id), e.Record_Id__c);
        Assert.areEqual('Case', e.Object__c);
        Assert.areEqual(1, e.Version__c);
        Assert.isNotNull(e.Definition_Hash__c);
        Assert.areEqual('Live', e.Mode__c);
        Assert.isNotNull(e.Idempotency_Key__c);
        Assert.areEqual(UserInfo.getUserId(), e.Running_User__c);
        Assert.areEqual(c.Id, e.Case__c);
        // A callout happened: state hash and provider status recorded
        Assert.isNotNull(e.State_Hash__c);
        Assert.areEqual('timeout', e.Provider_Status__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Gavel_Review__c WHERE Decision_Log__c = :e.Id], 'Live ERROR routes to a person');
    }

    // AS-6.2 Admin cannot edit
    @IsTest
    static void adminCannotEdit() {
        Gavel_TestFactory.ops(true);
        liveTriage('Ledger_Immutable');
        Case c = Gavel_TestFactory.newCase('Help', 'Billing question about invoice');
        insert c;
        Id ledgerId = Gavel_Runtime.run(c.Id, 'Ledger_Immutable').ledgerId;
        String original = [SELECT Outcome__c FROM Gavel_Decision_Log__c WHERE Id = :ledgerId].Outcome__c;
        User admin = Gavel_TestFactory.user('System Administrator');
        System.runAs(admin) {
            Gavel_Decision_Log__c e = new Gavel_Decision_Log__c(Id = ledgerId, Outcome__c = 'ESCALATE');
            try {
                update e;
                Assert.fail('System Administrator must not be able to edit the ledger');
            } catch (DmlException ex) {
                Assert.isTrue(ex.getMessage().contains('gavel_ledger_immutable'), '' + ex.getMessage());
            }
            try {
                delete new Gavel_Decision_Log__c(Id = ledgerId);
                Assert.fail('delete must be blocked');
            } catch (DmlException ex) {
                Assert.isTrue(ex.getMessage().contains('gavel_ledger_immutable'), '' + ex.getMessage());
            }
            try {
                insert new Gavel_Decision_Log__c(Definition__c = 'Forged', Outcome__c = 'AUTO');
                Assert.fail('forged insert must be blocked');
            } catch (DmlException ex) {
                Assert.isTrue(ex.getMessage().contains('gavel_ledger_runtime_only'), '' + ex.getMessage());
            }
        }
        Assert.areEqual(original, [SELECT Outcome__c FROM Gavel_Decision_Log__c WHERE Id = :ledgerId].Outcome__c, 'entry unchanged');
    }

    // AS-6.3 Tamper detected
    @IsTest
    static void tamperDetected() {
        List<Gavel_Decision_Log__c> rows = new List<Gavel_Decision_Log__c>();
        for (Integer i = 1; i <= 10; i++) {
            Gavel_Decision_Log__c e = Gavel_Ledger.newEntry(null, 'Chain_Def', null, 'k' + i);
            e.Outcome__c = 'REVIEW';
            e.Reason__c = 'confidence_below_auto_accept';
            rows.add(e);
        }
        Gavel_Ledger.write(rows);
        Gavel_LedgerVerifier.Result clean = Gavel_LedgerVerifier.verify('Chain_Def');
        Assert.isTrue(clean.ok, 'fresh chain verifies: ' + clean.reason);
        Assert.areEqual(10, clean.checked);

        Gavel_Decision_Log__c fifth = [SELECT Id FROM Gavel_Decision_Log__c WHERE Definition__c = 'Chain_Def' AND Chain_Seq__c = 5];
        Gavel_Ledger.tamperForTest(fifth.Id, 'Entry_Hash__c', 'deadbeef'.repeat(8));
        Gavel_LedgerVerifier.Result broken = Gavel_LedgerVerifier.verify('Chain_Def');
        Assert.isFalse(broken.ok);
        Assert.areEqual(5, broken.brokenAtSeq);
        Assert.areEqual(fifth.Id, broken.brokenEntryId);
        Assert.isTrue(Gavel_Alerts.wasRaised('ledger_tamper_detected'));
    }

    @IsTest
    static void contentTamperDetected() {
        List<Gavel_Decision_Log__c> rows = new List<Gavel_Decision_Log__c>();
        for (Integer i = 1; i <= 4; i++) {
            Gavel_Decision_Log__c e = Gavel_Ledger.newEntry(null, 'Chain_Content', null, 'c' + i);
            e.Outcome__c = 'ESCALATE';
            rows.add(e);
        }
        Gavel_Ledger.write(rows);
        Gavel_Decision_Log__c third = [SELECT Id FROM Gavel_Decision_Log__c WHERE Definition__c = 'Chain_Content' AND Chain_Seq__c = 3];
        Gavel_Ledger.tamperForTest(third.Id, 'Outcome__c', 'AUTO');
        Gavel_LedgerVerifier.Result r = Gavel_LedgerVerifier.verify('Chain_Content');
        Assert.areEqual(3, r.brokenAtSeq);
        Assert.areEqual('entry_hash_mismatch', r.reason);
    }

    @IsTest
    static void everyOutcomeTypeIsLedgered() {
        Gavel_TestFactory.ops(true);
        Gavel_Definition d = liveTriage('Ledger_All');
        Gavel_Definition retired = Gavel_TestFactory.triage('Ledger_Retired');
        retired.mode = Gavel_Definition.MODE_RETIRED;
        Gavel_TestFactory.register(retired);
        Case good = Gavel_TestFactory.newCase('Charged twice', 'Billing issue: two charges');
        Case empty = Gavel_TestFactory.newCase('No description', null);
        insert new List<Case>{ good, empty };
        Gavel_MockProvider.respondWith('Ledger_All', new Gavel_MockProvider.Body()
            .choice('category', new Map<String, Decimal>{ 'BILLING' => 0.95, 'FRAUD' => 0.02, 'TECHNICAL' => 0.02, 'ACCOUNT' => 0.01 }, 0.9)
            .noul('fraud_concern', 0.02).json());
        List<Gavel_Runtime.RunResult> results = Gavel_Runtime.runAll(new List<Gavel_Runtime.RunRequest>{
            new Gavel_Runtime.RunRequest(good.Id, 'Ledger_All'),
            new Gavel_Runtime.RunRequest(empty.Id, 'Ledger_All'),
            new Gavel_Runtime.RunRequest(good.Id, 'Ledger_Retired'),
            new Gavel_Runtime.RunRequest(good.Id, 'Does_Not_Exist'),
            new Gavel_Runtime.RunRequest(good.Id, 'Ledger_All') // same record twice in one batch
        });
        Assert.areEqual('AUTO', results[0].outcome);
        Assert.areEqual('BILLING', results[0].topChoice);
        Assert.areEqual('SKIP', results[1].outcome);
        Assert.areEqual('insufficient_state', results[1].reason);
        Assert.areEqual('definition_retired', results[2].reason);
        Assert.areEqual('definition_not_found', results[3].reason);
        Assert.areEqual('duplicate_inflight', results[4].reason);
        for (Gavel_Runtime.RunResult r : results) {
            Assert.isNotNull(r.ledgerId, 'every run is ledgered: ' + r.reason);
        }
        Assert.areEqual(5, [SELECT COUNT() FROM Gavel_Decision_Log__c]);
        // A second run on the same record within 60s is a duplicate.
        Assert.areEqual('duplicate_inflight', Gavel_Runtime.run(good.Id, 'Ledger_All').reason);
        Assert.isTrue(Gavel_LedgerVerifier.verify('Ledger_All').ok);
    }

    @IsTest
    static void pendingFinalizedExactlyOnce() {
        Gavel_TestFactory.ops(true);
        Gavel_Definition d = liveTriage('Ledger_Pending');
        Case c = Gavel_TestFactory.newCase('Help', 'Technical problem with login');
        insert c;
        Gavel_Decision_Log__c pending = Gavel_Ledger.newEntry(d, d.apiName, c.Id, c.Id + ':Ledger_Pending:1');
        Gavel_Ledger.insertPending(new List<Gavel_Decision_Log__c>{ pending });
        Assert.areEqual('PENDING', [SELECT Outcome__c FROM Gavel_Decision_Log__c WHERE Id = :pending.Id].Outcome__c);

        Gavel_Runtime.RunRequest req = new Gavel_Runtime.RunRequest(c.Id, d.apiName);
        req.pendingEntry = pending;
        req.isAsync = true;
        Gavel_Runtime.RunResult r = Gavel_Runtime.run(req);
        Assert.areEqual(pending.Id, r.ledgerId, 'the pending entry is finalized, not duplicated');
        Assert.areEqual(1, [SELECT COUNT() FROM Gavel_Decision_Log__c WHERE Definition__c = 'Ledger_Pending']);
        Gavel_Decision_Log__c fin = [SELECT Outcome__c, Chain_Seq__c, Entry_Hash__c FROM Gavel_Decision_Log__c WHERE Id = :pending.Id];
        Assert.areNotEqual('PENDING', fin.Outcome__c);
        Assert.areEqual(1, fin.Chain_Seq__c);

        // A second finalization is rejected by the trigger.
        Gavel_Decision_Log__c again = new Gavel_Decision_Log__c(Id = pending.Id, Outcome__c = 'AUTO', Definition__c = 'Ledger_Pending',
            Record_Id__c = String.valueOf(c.Id), Idempotency_Key__c = pending.Idempotency_Key__c);
        Gavel_Ledger.finalizeEntries(new List<Gavel_Decision_Log__c>{ again });
        Assert.areEqual(fin.Outcome__c, [SELECT Outcome__c FROM Gavel_Decision_Log__c WHERE Id = :pending.Id].Outcome__c);
    }

    @IsTest
    static void retentionPurgesAndAnchorsChain() {
        List<Gavel_Decision_Log__c> rows = new List<Gavel_Decision_Log__c>();
        for (Integer i = 1; i <= 6; i++) {
            Gavel_Decision_Log__c e = Gavel_Ledger.newEntry(null, 'Retained', null, 'r' + i);
            e.Outcome__c = 'SKIP';
            e.Reason__c = 'egress_disabled';
            e.Run_At__c = i <= 3 ? System.now().addDays(-400) : System.now();
            rows.add(e);
        }
        Gavel_Ledger.write(rows);
        Integer purged = Gavel_LedgerRetention.runNow(System.now().addDays(-365));
        Assert.areEqual(3, purged);
        Assert.areEqual(3, [SELECT COUNT() FROM Gavel_Decision_Log__c WHERE Definition__c = 'Retained']);
        Gavel_Ledger_Purge__c summary = [SELECT Purged_Count__c, Last_Purged_Seq__c, Last_Purged_Hash__c FROM Gavel_Ledger_Purge__c WHERE Definition__c = 'Retained'];
        Assert.areEqual(3, summary.Purged_Count__c);
        Assert.areEqual(3, summary.Last_Purged_Seq__c);
        Gavel_LedgerVerifier.Result r = Gavel_LedgerVerifier.verify('Retained');
        Assert.isTrue(r.ok, 'remaining chain verifies from the purge anchor: ' + r.reason);
        Assert.areEqual(3, r.checked);

        Test.startTest();
        Database.executeBatch(new Gavel_LedgerRetention(System.now().addDays(1)));
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Gavel_Decision_Log__c WHERE Definition__c = 'Retained']);
        new Gavel_LedgerRetention().execute((SchedulableContext) null);
    }

    @IsTest
    static void fallbackReplaysFailedInsert() {
        Gavel_Decision_Log__c e = Gavel_Ledger.newEntry(null, 'Fallback_Def', null, 'f1');
        e.Outcome__c = 'ERROR';
        e.Reason__c = 'http_error';
        Test.startTest();
        Gavel_Ledger.replay(new List<Gavel_Ledger_Fallback__e>{ new Gavel_Ledger_Fallback__e(Payload__c = JSON.serialize(e)) });
        Gavel_Ledger.replay(new List<Gavel_Ledger_Fallback__e>{ new Gavel_Ledger_Fallback__e(Payload__c = 'not json') });
        Test.stopTest();
        Assert.areEqual(1, [SELECT COUNT() FROM Gavel_Decision_Log__c WHERE Definition__c = 'Fallback_Def']);
        Assert.isTrue(Gavel_Alerts.wasRaised('ledger_fallback_unreadable'));
    }

    @IsTest
    static void recordComponentApi() {
        Gavel_TestFactory.ops(false);
        liveTriage('Ledger_Api');
        Case c = Gavel_TestFactory.newCase('Help', 'Anything');
        insert c;
        Gavel_Runtime.run(c.Id, 'Ledger_Api');
        // The LWC API runs in user mode: an auditor needs object and field access (Gavel_Auditor in the admin app).
        User auditor = Gavel_TestFactory.user('Standard User');
        Gavel_TestFactory.grantRead(auditor, 'Gavel_Decision_Log__c', new List<String>{
            'Definition__c', 'Version__c', 'Mode__c', 'Outcome__c', 'Reason__c', 'Top_Choice__c', 'Top_Confidence__c',
            'Model_Version__c', 'Action_Taken__c', 'Action_Suppressed__c', 'Cache_Hit__c', 'Latency_Ms__c', 'Run_At__c', 'Record_Id__c'
        });
        System.runAs(auditor) {
            List<Gavel_Decision_Log__c> rows = Gavel_LedgerController.entriesForRecord(String.valueOf(c.Id), 10);
            Assert.areEqual(1, rows.size());
            Assert.areEqual('egress_disabled', rows[0].Reason__c);
            Map<String, Object> v = Gavel_LedgerController.verifyChain('Ledger_Api');
            Assert.areEqual(true, v.get('ok'));
        }
    }
}
