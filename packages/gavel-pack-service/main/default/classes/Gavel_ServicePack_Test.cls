@IsTest
private class Gavel_ServicePack_Test {
    private static final List<String> DEFINITIONS = new List<String>{
        'Gavel_Case_Triage', 'Gavel_Case_Urgency', 'Gavel_KB_Coverage', 'Gavel_Closure_Check', 'Gavel_Reply_Check'
    };

    private static Gavel_Definition withMock(String api) {
        Gavel_Definition d = Gavel_DefinitionRepo.get(api);
        Assert.isNotNull(d, api + ' must be deployed with the pack');
        d.providerClass = Gavel_TestFactory.MOCK_PROVIDER;
        return d;
    }

    // AS-11.1 Install in shadow
    @IsTest
    static void installsInShadow() {
        for (String api : DEFINITIONS) {
            Gavel_Definition d = Gavel_DefinitionRepo.get(api);
            Assert.areEqual('Shadow', d.mode, api + ' must install in Shadow (SVC-001.6)');
            Gavel_DefinitionValidator.Result v = Gavel_DefinitionValidator.validate(d);
            Assert.isTrue(v.valid, api + ': ' + v.errors + ' canonical=' + Gavel_DefinitionHasher.canonical(d));
        }
        Case c = Gavel_TestFactory.newCase('Charged twice this month', 'I was charged twice. Please refund the duplicate payment.');
        c.Priority = 'Medium';
        insert c;
        Assert.areEqual(0, [SELECT COUNT() FROM Gavel_Decision_Log__c], 'no flow is active after install');
        Case before = [SELECT Type, OwnerId, Status, Priority, Reason FROM Case WHERE Id = :c.Id];

        // Even when a shadow definition runs and is confident, no Case field changes.
        Gavel_TestFactory.ops(true);
        withMock('Gavel_Case_Triage');
        Gavel_Runtime.RunResult r = Gavel_Runtime.run(c.Id, 'Gavel_Case_Triage');
        Assert.areEqual('AUTO', r.outcome, 'detail: ' + r.reason);
        Assert.areEqual('BILLING', r.topChoice);
        Assert.areEqual('action_suppressed_shadow', r.actionTaken);
        Case after = [SELECT Type, OwnerId, Status, Priority, Reason FROM Case WHERE Id = :c.Id];
        Assert.areEqual(before, after, 'no Case field changes');
    }

    // AS-11.2 KB gap
    @IsTest
    static void kbGapCreated() {
        Gavel_TestFactory.ops(true);
        withMock('Gavel_KB_Coverage');
        Gavel_Option a = new Gavel_Option('ka0000000000001AAA', 'Configure single sign-on');
        a.description = 'How to set up SSO with your identity provider.';
        Gavel_Option b = new Gavel_Option('ka0000000000002AAA', 'Reset a user password');
        Gavel_KBCandidates.testCandidates = new List<Gavel_Option>{ a, b };
        Gavel_MockProvider.respondWith('Gavel_KB_Coverage', new Gavel_MockProvider.Body()
            .choice('article', new Map<String, Decimal>{ 'ka0000000000001AAA' => 0.06, 'ka0000000000002AAA' => 0.04, 'none' => 0.9 }, 0.88)
            .noul('answers_question', 0.08)
            .json());
        Case c = Gavel_TestFactory.newCase('SAML certificate rotation', 'Our IdP rotates its SAML signing certificate next week. Contact me at it-admin@example.com.');
        insert c;
        Gavel_KBCoverage.Result r = Gavel_KBCoverage.check(new List<Id>{ c.Id })[0];
        Assert.isTrue(r.gapCreated);
        Assert.areEqual('none', r.articleId);
        Gavel_KB_Gap__c gap = [SELECT Case__c, Top_Candidates__c, Question_Text__c, Decision_Log__c, Status__c FROM Gavel_KB_Gap__c];
        Assert.areEqual(c.Id, gap.Case__c, 'gap links to the case');
        Assert.areEqual('ka0000000000001AAA,ka0000000000002AAA', gap.Top_Candidates__c, 'top candidate ids, most likely first');
        Assert.areEqual(r.ledgerId, gap.Decision_Log__c);
        Assert.isTrue(gap.Question_Text__c.contains('SAML'));
        Assert.isFalse(gap.Question_Text__c.contains('it-admin@example.com'), 'question text is redacted');
        // The request asked over the candidates plus "none".
        Assert.areEqual(3, Gavel_MockProvider.lastRequest.questions[0].options.size());
    }

    // AS-11.3 Urgency independent of priority
    @IsTest
    static void urgencyIndependentOfPriority() {
        Gavel_Config.Ops ops = Gavel_TestFactory.ops(true);
        ops.storeState = true; // show both values on the ledger entry
        withMock('Gavel_Case_Urgency');
        Case c = Gavel_TestFactory.newCase('Need help', 'fourth call, need this resolved today, payroll blocked');
        c.Priority = 'Low';
        insert c;
        Gavel_Runtime.RunResult r = Gavel_Runtime.run(c.Id, 'Gavel_Case_Urgency');
        Assert.areEqual('AUTO', r.outcome, 'detail: ' + r.reason);
        Decimal score = Decimal.valueOf(r.answerValues.get('urgency'));
        Assert.isTrue(score >= 3, 'urgency score ' + score);
        Gavel_Decision_Log__c e = [SELECT Answers_JSON__c, State_JSON__c FROM Gavel_Decision_Log__c WHERE Id = :r.ledgerId];
        Assert.isTrue(e.State_JSON__c.contains('"customer_priority":"Low"'), '' + e.State_JSON__c);
        Assert.isTrue(e.Answers_JSON__c.contains('"score":3.6'), '' + e.Answers_JSON__c);
    }

    @IsTest
    static void noCandidatesIsAGap() {
        Gavel_TestFactory.ops(true);
        withMock('Gavel_KB_Coverage');
        Gavel_KBCandidates.testCandidates = new List<Gavel_Option>();
        Case c = Gavel_TestFactory.newCase('Obscure question', 'Something nobody wrote about');
        insert c;
        Gavel_KBCoverage.Request req = new Gavel_KBCoverage.Request();
        req.caseId = c.Id;
        Gavel_KBCoverage.Result r = Gavel_KBCoverage.invoke(new List<Gavel_KBCoverage.Request>{ req })[0];
        Assert.areEqual('SKIP', r.outcome);
        Assert.isTrue(r.gapCreated);
        Assert.areEqual('no_kb_candidates', [SELECT Reason__c FROM Gavel_Decision_Log__c WHERE Id = :r.ledgerId].Reason__c);
    }

    @IsTest
    static void triageClosureAndEmptyCase() {
        Gavel_TestFactory.ops(true);
        withMock('Gavel_Case_Triage');
        withMock('Gavel_Closure_Check');
        Case fraud = Gavel_TestFactory.newCase('Unauthorized charge', 'Someone used our stolen card.');
        Case empty = Gavel_TestFactory.newCase('No details', null);
        insert new List<Case>{ fraud, empty };
        insert new EmailMessage(ParentId = fraud.Id, Incoming = true, Subject = 'Re: case', TextBody = 'Thanks, it works now. You can close this.', MessageDate = System.now());
        List<Gavel_Runtime.RunResult> rs = Gavel_Runtime.runAll(new List<Gavel_Runtime.RunRequest>{
            new Gavel_Runtime.RunRequest(fraud.Id, 'Gavel_Case_Triage'),
            new Gavel_Runtime.RunRequest(empty.Id, 'Gavel_Case_Triage'),
            new Gavel_Runtime.RunRequest(fraud.Id, 'Gavel_Closure_Check')
        });
        Assert.areEqual('FRAUD', rs[0].topChoice);
        Assert.areEqual('true', rs[0].answerValues.get('fraud_concern'));
        Assert.areEqual('SKIP', rs[1].outcome);
        Assert.areEqual('insufficient_state', rs[1].reason, 'case with no description or emails');
        Assert.areEqual('true', rs[2].answerValues.get('customer_confirmed_resolved'));
    }

    @IsTest
    static void candidatesFromSearchWhenKnowledgeIsAvailable() {
        Gavel_TestFactory.ops(true);
        Gavel_Definition d = withMock('Gavel_KB_Coverage');
        Gavel_KBCandidates.top = 5;
        try {
            List<Gavel_Option> opts = new Gavel_KBCandidates().options(null, d, d.question('article'), new Map<String, Object>{ 'subject' => 'password reset' });
            Assert.areEqual('none', opts[opts.size() - 1].key, 'none is always offered');
        } catch (Gavel_SkipException e) {
            Assert.isTrue(new Set<String>{ 'no_kb_candidates', 'knowledge_not_enabled', 'knowledge_unavailable' }.contains(e.getMessage()), '' + e.getMessage());
        }
        Gavel_StateContext ctx = new Gavel_StateContext();
        Assert.isNull(new Gavel_ServiceSources.LinkedArticle().resolve(ctx));
    }
}
