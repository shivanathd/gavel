@IsTest
private class Gavel_DecisionQueueable_Test {
    @IsTest
    static void recordDeletedBeforeQueueableRuns() {
        Gavel_TestFactory.ops(true);
        Gavel_TestFactory.register(Gavel_TestFactory.triage('Q_Triage'));
        Case c = Gavel_TestFactory.newCase('Gone', 'Will be deleted');
        insert c;
        Test.startTest();
        Id pending = Gavel.runAsync(c.Id, 'Q_Triage');
        delete c;
        Test.stopTest();
        Gavel_Decision_Log__c e = [SELECT Outcome__c, Reason__c FROM Gavel_Decision_Log__c WHERE Id = :pending];
        Assert.areEqual('SKIP', e.Outcome__c);
        Assert.areEqual('record_not_found', e.Reason__c);
    }

    @IsTest
    static void duplicateWithinSixtySeconds() {
        Gavel_TestFactory.ops(true);
        Gavel_TestFactory.register(Gavel_TestFactory.triage('Q_Dup'));
        Case c = Gavel_TestFactory.newCase('Twice', 'Triggered twice');
        insert c;
        Test.startTest();
        Id first = Gavel.runAsync(c.Id, 'Q_Dup');
        Id second = Gavel.runAsync(c.Id, 'Q_Dup');
        Test.stopTest();
        Assert.areEqual('duplicate_inflight', [SELECT Reason__c FROM Gavel_Decision_Log__c WHERE Id = :second].Reason__c);
        Assert.areNotEqual('PENDING', [SELECT Outcome__c FROM Gavel_Decision_Log__c WHERE Id = :first].Outcome__c);
        Assert.areEqual(2, [SELECT COUNT() FROM Gavel_Decision_Log__c WHERE Definition__c = 'Q_Dup']);
    }

    @IsTest
    static void overflowStaysPendingForSweeper() {
        Gavel_Config.Ops ops = Gavel_TestFactory.ops(true);
        ops.batchSize = 1;
        Gavel_TestFactory.register(Gavel_TestFactory.triage('Q_Sweep'));
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 3; i++) {
            cases.add(Gavel_TestFactory.newCase('Sweep ' + i, 'Sweeper case ' + i));
        }
        insert cases;
        // Simulate a transaction that has no queueable slots left: entries stay PENDING.
        List<Gavel_Decision_Log__c> pending = new List<Gavel_Decision_Log__c>();
        Gavel_Definition d = Gavel_DefinitionRepo.get('Q_Sweep');
        for (Case c : cases) {
            pending.add(Gavel_Ledger.newEntry(d, d.apiName, c.Id, c.Id + ':Q_Sweep:1'));
        }
        Gavel_Ledger.insertPending(pending);
        Assert.areEqual(3, [SELECT COUNT() FROM Gavel_Decision_Log__c WHERE Outcome__c = 'PENDING']);

        Test.startTest();
        Database.executeBatch(new Gavel_PendingSweeper(0), 20);
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Gavel_Decision_Log__c WHERE Outcome__c = 'PENDING'], 'sweeper finalized them');
        Assert.areEqual(3, [SELECT COUNT() FROM Gavel_Decision_Log__c WHERE Definition__c = 'Q_Sweep']);
    }

    @IsTest
    static void backlogCarriedByLastJob() {
        Gavel_Config.Ops ops = Gavel_TestFactory.ops(true);
        ops.batchSize = 1;
        Gavel_TestFactory.register(Gavel_TestFactory.triage('Q_Backlog'));
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 3; i++) {
            cases.add(Gavel_TestFactory.newCase('Backlog ' + i, 'Backlog case ' + i));
        }
        insert cases;
        Test.startTest();
        List<Id> ids = Gavel.runAsync(new List<Id>{ cases[0].Id, cases[1].Id, cases[2].Id }, 'Q_Backlog');
        Assert.areEqual(3, Limits.getQueueableJobs(), 'one job per record at batch size 1');
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Gavel_Decision_Log__c WHERE Id IN :ids AND Outcome__c = 'PENDING']);
    }

    @IsTest
    static void egressOffEndsImmediately() {
        Gavel_TestFactory.ops(false);
        Gavel_TestFactory.register(Gavel_TestFactory.triage('Q_Off'));
        Case c = Gavel_TestFactory.newCase('Off', 'Egress is off');
        insert c;
        Test.startTest();
        Id lid = Gavel.runAsync(c.Id, 'Q_Off');
        Assert.areEqual(0, Limits.getQueueableJobs(), 'nothing queued when egress is off');
        Test.stopTest();
        Assert.areEqual('egress_disabled', [SELECT Reason__c FROM Gavel_Decision_Log__c WHERE Id = :lid].Reason__c);
    }

    @IsTest
    static void sweeperSchedules() {
        Test.startTest();
        String jobId = System.schedule('Gavel sweeper test', '0 0 1 * * ?', new Gavel_PendingSweeper());
        Test.stopTest();
        Assert.isNotNull(jobId);
        Assert.areEqual(0, Gavel_DecisionQueueable.process(null).size());
    }
}
