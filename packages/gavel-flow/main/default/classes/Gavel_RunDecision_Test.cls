@IsTest
private class Gavel_RunDecision_Test {
    private class Http500 implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"internal"}');
            return res;
        }
    }

    private static Gavel_RunDecision.RunInput input(Id recordId, String def) {
        Gavel_RunDecision.RunInput i = new Gavel_RunDecision.RunInput();
        i.recordId = recordId;
        i.definitionApiName = def;
        return i;
    }

    // AS-4.1 Record-triggered async path: 200 records -> 10 queueables -> 200 ledger entries
    @IsTest
    static void bulk200Async() {
        Gavel_TestFactory.ops(true);
        Gavel_TestFactory.register(Gavel_TestFactory.triage('Bulk_Triage'));
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 200; i++) {
            cases.add(Gavel_TestFactory.newCase('Bulk ' + i, 'Data Loader case number ' + i));
        }
        insert cases;
        List<Gavel_RunDecisionAsync.AsyncInput> inputs = new List<Gavel_RunDecisionAsync.AsyncInput>();
        for (Case c : cases) {
            Gavel_RunDecisionAsync.AsyncInput i = new Gavel_RunDecisionAsync.AsyncInput();
            i.recordId = c.Id;
            i.definitionApiName = 'Bulk_Triage';
            inputs.add(i);
        }
        Test.startTest();
        List<Gavel_RunDecisionAsync.AsyncOutput> outs = Gavel_RunDecisionAsync.run(inputs);
        Assert.areEqual(10, Limits.getQueueableJobs(), '200 records / batch size 20 = 10 queueables');
        Test.stopTest();

        Assert.areEqual(200, outs.size());
        for (Gavel_RunDecisionAsync.AsyncOutput o : outs) {
            Assert.areEqual('PENDING', o.outcome);
            Assert.isNotNull(o.ledgerId);
        }
        Assert.areEqual(200, [SELECT COUNT() FROM Gavel_Decision_Log__c WHERE Definition__c = 'Bulk_Triage'], 'exactly one ledger entry per record');
        Assert.areEqual(0, [SELECT COUNT() FROM Gavel_Decision_Log__c WHERE Outcome__c = 'PENDING'], 'all finalized');
        Assert.areEqual(0, [SELECT COUNT() FROM Gavel_Decision_Log__c WHERE Reason__c LIKE '%Exception%'], 'no CalloutException');
        Assert.areEqual(10, [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'Gavel_DecisionQueueable']);
        Assert.areEqual(200, Gavel_MockProvider.callCount, 'one call per record');
        Assert.isTrue(Gavel_LedgerVerifier.verify('Bulk_Triage').ok);
    }

    // AS-4.2 Screen flow sync
    @IsTest
    static void screenFlowSync() {
        Gavel_TestFactory.ops(true);
        Gavel_Definition d = Gavel_TestFactory.definition('Lead_Check', 'Lead');
        d.questions.add(Gavel_TestFactory.choice('quality', new List<String>{ 'real_buyer', 'spam', 'manual_review' }));
        d.question('quality').findOption('manual_review').isEscape = true;
        d.policies.add(Gavel_TestFactory.policy('quality', 0.85, 0.5, 0.3));
        d.stateFields.add(new Gavel_Definition.StateField('Company', 'company', true));
        Gavel_TestFactory.register(d);
        Lead l = new Lead(LastName = 'Buyer', Company = 'Acme Manufacturing');
        insert l;
        Test.startTest();
        List<Gavel_RunDecision.RunOutput> outs = Gavel_RunDecision.run(new List<Gavel_RunDecision.RunInput>{ input(l.Id, 'Lead_Check') });
        Test.stopTest();
        Assert.areEqual(1, outs.size());
        Assert.areEqual('AUTO', outs[0].outcome, '' + outs[0].reason);
        Assert.areEqual('real_buyer', outs[0].topChoice);
        Assert.isNotNull(outs[0].answersJson);
        Assert.areEqual(1, [SELECT COUNT() FROM Gavel_Decision_Log__c WHERE Id = :outs[0].ledgerId AND Lead__c = :l.Id], 'ledger entry exists');
    }

    // AS-4.3 Error surfaces as outcome
    @IsTest
    static void errorSurfacesAsOutcome() {
        Gavel_TestFactory.ops(true);
        Gavel_Definition d = Gavel_TestFactory.triage('Http_Triage');
        d.providerClass = 'Gavel_TypeSafeProvider';
        d.namedCredential = 'Gavel_TypeSafe';
        d.endpointPath = '/v1/systemone';
        Gavel_TestFactory.register(d);
        Case c = Gavel_TestFactory.newCase('Help', 'Router keeps rebooting');
        insert c;
        Test.setMock(HttpCalloutMock.class, new Http500());
        Test.startTest();
        List<Gavel_RunDecision.RunOutput> outs = Gavel_RunDecision.run(new List<Gavel_RunDecision.RunInput>{ input(c.Id, 'Http_Triage') });
        Test.stopTest();
        Assert.areEqual('ERROR', outs[0].outcome);
        Assert.areEqual('http_error', outs[0].reason);
        Assert.isNotNull(outs[0].ledgerId, 'still ledgered');
    }

    @IsTest
    static void invocablesNeverThrow() {
        Assert.areEqual(0, Gavel_RunDecision.run(null).size());
        List<Gavel_RunDecision.RunOutput> outs = Gavel_RunDecision.run(new List<Gavel_RunDecision.RunInput>{ input(null, 'Nope') });
        Assert.areEqual('ERROR', outs[0].outcome);
        Assert.areEqual('definition_not_found', outs[0].reason);
        Assert.areEqual(0, Gavel_RunDecisionAsync.run(null).size());
        Gavel_RunDecisionAsync.AsyncInput a = new Gavel_RunDecisionAsync.AsyncInput();
        a.definitionApiName = 'Nope';
        Assert.areEqual('ERROR', Gavel_RunDecisionAsync.run(new List<Gavel_RunDecisionAsync.AsyncInput>{ a })[0].outcome);
        Assert.areEqual('sync_limit_exceeded_use_async', Gavel_RunDecision.error('sync_limit_exceeded_use_async').reason);
    }

    @IsTest
    static void apexApi() {
        Gavel_TestFactory.ops(true);
        Gavel_TestFactory.register(Gavel_TestFactory.triage('Api_Triage'));
        Case a = Gavel_TestFactory.newCase('A', 'first description');
        Case b = Gavel_TestFactory.newCase('B', 'second description');
        Case c = Gavel_TestFactory.newCase('C', 'third description');
        insert new List<Case>{ a, b, c };
        Test.startTest();
        Assert.areEqual('AUTO', Gavel.run(a.Id, 'Api_Triage').outcome);
        Assert.areEqual(1, Gavel.run(new List<Id>{ b.Id }, 'Api_Triage').size());
        Id pending = Gavel.runAsync(c.Id, 'Api_Triage');
        Test.stopTest();
        Assert.areNotEqual('PENDING', [SELECT Outcome__c FROM Gavel_Decision_Log__c WHERE Id = :pending].Outcome__c);
    }
}
