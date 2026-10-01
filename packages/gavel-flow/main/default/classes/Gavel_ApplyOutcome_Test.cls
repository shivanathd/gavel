@IsTest
private class Gavel_ApplyOutcome_Test {
    private static Gavel_Definition liveRouting(String name) {
        Gavel_Definition d = Gavel_TestFactory.triage(name);
        d.mode = Gavel_Definition.MODE_LIVE;
        d.actionMaps.add(new Gavel_Definition.ActionMap('category', 'BILLING', 'set_field', 'Case.Subject', 'Routed: {answer}'));
        d.actionMaps.add(new Gavel_Definition.ActionMap('category', 'BILLING', 'create_task', null, 'Follow up on billing case'));
        return Gavel_TestFactory.register(d);
    }

    private static void billing(String def, Decimal top) {
        Decimal rest = (1 - top) / 3;
        Gavel_MockProvider.respondWith(def, new Gavel_MockProvider.Body()
            .choice('category', new Map<String, Decimal>{ 'BILLING' => top, 'FRAUD' => rest, 'TECHNICAL' => rest, 'ACCOUNT' => 1 - top - 2 * rest }, 0.9)
            .noul('fraud_concern', 0.02).json());
    }

    private static Gavel_ApplyOutcome.ApplyInput input(Id ledgerId) {
        Gavel_ApplyOutcome.ApplyInput i = new Gavel_ApplyOutcome.ApplyInput();
        i.ledgerId = ledgerId;
        return i;
    }

    @IsTest
    static void appliesDeferredAutoOnceOnLive() {
        Gavel_TestFactory.ops(true);
        liveRouting('Apply_Live');
        billing('Apply_Live', 0.95);
        Case c = Gavel_TestFactory.newCase('Original', 'Charged twice this month');
        insert c;
        Gavel_RunDecision.RunInput ri = new Gavel_RunDecision.RunInput();
        ri.recordId = c.Id;
        ri.definitionApiName = 'Apply_Live';
        Gavel_RunDecision.RunOutput run = Gavel_RunDecision.run(new List<Gavel_RunDecision.RunInput>{ ri })[0];
        Assert.areEqual('AUTO', run.outcome);
        Assert.areEqual('Original', [SELECT Subject FROM Case WHERE Id = :c.Id].Subject, 'sync action defers application');
        Assert.areEqual('deferred', [SELECT Action_Taken__c FROM Gavel_Decision_Log__c WHERE Id = :run.ledgerId].Action_Taken__c);

        Gavel_ApplyOutcome.ApplyOutput out = Gavel_ApplyOutcome.apply(new List<Gavel_ApplyOutcome.ApplyInput>{ input(run.ledgerId) })[0];
        Assert.isTrue(out.applied, 'detail: ' + out.actions);
        Assert.areEqual('Routed: BILLING', [SELECT Subject FROM Case WHERE Id = :c.Id].Subject);
        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :c.Id]);
        Assert.areEqual(2, [SELECT COUNT() FROM Gavel_Action_Log__c WHERE Decision_Log__c = :run.ledgerId AND Status__c = 'applied']);

        Gavel_ApplyOutcome.ApplyOutput again = Gavel_ApplyOutcome.apply(new List<Gavel_ApplyOutcome.ApplyInput>{ input(run.ledgerId) })[0];
        Assert.isFalse(again.applied, 'actions apply at most once');
    }

    @IsTest
    static void onlyAutoOnLiveActs() {
        Gavel_TestFactory.ops(true);
        liveRouting('Apply_Review');
        billing('Apply_Review', 0.6); // REVIEW band
        Gavel_Definition shadow = Gavel_TestFactory.triage('Apply_Shadow');
        shadow.actionMaps.add(new Gavel_Definition.ActionMap('category', 'BILLING', 'set_field', 'Case.Subject', 'X'));
        Gavel_TestFactory.register(shadow);
        billing('Apply_Shadow', 0.95);
        Case a = Gavel_TestFactory.newCase('A', 'needs review');
        Case b = Gavel_TestFactory.newCase('B', 'shadow only');
        insert new List<Case>{ a, b };
        Gavel_Runtime.RunRequest ra = new Gavel_Runtime.RunRequest(a.Id, 'Apply_Review');
        ra.applyActions = false;
        Gavel_Runtime.RunRequest rb = new Gavel_Runtime.RunRequest(b.Id, 'Apply_Shadow');
        rb.applyActions = false;
        List<Gavel_Runtime.RunResult> rs = Gavel_Runtime.runAll(new List<Gavel_Runtime.RunRequest>{ ra, rb });
        Assert.areEqual('REVIEW', rs[0].outcome);
        Assert.isNotNull(rs[0].reviewId, 'REVIEW on Live creates a work item');
        Gavel_Review__c review = [SELECT Status__c, OwnerId, Question_Key__c, Gavel_Value__c, Case__c FROM Gavel_Review__c WHERE Id = :rs[0].reviewId];
        Assert.areEqual('Open', review.Status__c);
        Assert.areEqual([SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Gavel_Review_Queue'].Id, review.OwnerId, 'assigned to the review queue');
        Assert.areEqual('category', review.Question_Key__c);
        Assert.areEqual('BILLING', review.Gavel_Value__c);
        Assert.areEqual(a.Id, review.Case__c);

        List<Gavel_ApplyOutcome.ApplyOutput> outs = Gavel_ApplyOutcome.apply(new List<Gavel_ApplyOutcome.ApplyInput>{
            input(rs[0].ledgerId), input(rs[1].ledgerId), input(null)
        });
        Assert.isFalse(outs[0].applied);
        Assert.areEqual('not_auto', outs[0].actions);
        Assert.isFalse(outs[1].applied);
        Assert.areEqual('action_suppressed_shadow', outs[1].actions);
        Assert.areEqual('ledger_entry_not_found', outs[2].actions);
        Assert.areEqual('A', [SELECT Subject FROM Case WHERE Id = :a.Id].Subject);
        Assert.areEqual('B', [SELECT Subject FROM Case WHERE Id = :b.Id].Subject);
    }

    @IsTest
    static void changedDefinitionIsNotApplied() {
        Gavel_TestFactory.ops(true);
        Gavel_Definition d = liveRouting('Apply_Changed');
        billing('Apply_Changed', 0.95);
        Case c = Gavel_TestFactory.newCase('C', 'billing please');
        insert c;
        Gavel_Runtime.RunRequest r = new Gavel_Runtime.RunRequest(c.Id, 'Apply_Changed');
        r.applyActions = false;
        Id ledgerId = Gavel_Runtime.run(r).ledgerId;
        d.version = 2;
        Gavel_TestFactory.register(d);
        Gavel_ApplyOutcome.ApplyOutput out = Gavel_ApplyOutcome.apply(new List<Gavel_ApplyOutcome.ApplyInput>{ input(ledgerId) })[0];
        Assert.isFalse(out.applied);
        Assert.areEqual('definition_changed', out.actions);
        Assert.areEqual(0, Gavel_ApplyOutcome.apply(null).size());
    }

    @IsTest
    static void asyncAppliesLiveAutoInline() {
        Gavel_TestFactory.ops(true);
        liveRouting('Apply_Async');
        billing('Apply_Async', 0.95);
        Case c = Gavel_TestFactory.newCase('Async', 'double charge');
        insert c;
        Test.startTest();
        Id lid = Gavel.runAsync(c.Id, 'Apply_Async');
        Test.stopTest();
        Assert.areEqual('Routed: BILLING', [SELECT Subject FROM Case WHERE Id = :c.Id].Subject, 'queueable applies Live AUTO actions');
        Assert.isTrue([SELECT Action_Taken__c FROM Gavel_Decision_Log__c WHERE Id = :lid].Action_Taken__c.startsWith('set_field'));
    }
}
