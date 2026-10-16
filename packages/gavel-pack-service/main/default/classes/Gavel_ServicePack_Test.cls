@IsTest
private class Gavel_ServicePack_Test {
    private static final List<String> DEFINITIONS = new List<String>{
        'Gavel_Case_Triage', 'Gavel_Case_Urgency', 'Gavel_KB_Coverage', 'Gavel_Closure_Check', 'Gavel_Reply_Check',
        'Gavel_Return_Triage', 'Gavel_Return_Photo_Check'
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

    private static Case returnCase(Integer daysAgo, Decimal price, String description) {
        Account acct = new Account(Name = 'Return Customer');
        insert acct;
        Case c = Gavel_TestFactory.newCase('Return request', description);
        c.AccountId = acct.Id;
        if (daysAgo != null) {
            Asset a = new Asset(Name = 'Aria headphones', AccountId = acct.Id, PurchaseDate = Date.today().addDays(-daysAgo), Price = price);
            insert a;
            c.AssetId = a.Id;
        }
        insert c;
        return c;
    }

    private static Map<String, Boolean> offered(Id caseId) {
        Gavel_Runtime.RunResult r = Gavel_Runtime.run(caseId, 'Gavel_Return_Triage');
        Assert.areNotEqual('ERROR', r.outcome, 'detail: ' + r.reason);
        Map<String, Boolean> escapeByKey = new Map<String, Boolean>();
        for (Gavel_Option o : Gavel_MockProvider.lastRequest.questions[0].options) {
            escapeByKey.put(o.key, o.isEscape);
        }
        return escapeByKey;
    }

    // Returns: the policy is enforced in code before Jev is asked (Gavel_ReturnOptions:30:500)
    @IsTest
    static void returnPolicyEnforcedInCode() {
        Gavel_TestFactory.ops(true);
        withMock('Gavel_Return_Triage');

        Map<String, Boolean> inWindow = offered(returnCase(10, 120, 'Left earcup stopped working after a week.').Id);
        Assert.areEqual(new Set<String>{ 'refund', 'replace', 'repair', 'reject_policy', 'human_review' }, inWindow.keySet());
        Assert.isFalse(inWindow.get('refund'), 'cheap and in window: refund can be automatic');
        Assert.isTrue(inWindow.get('human_review'));

        Map<String, Boolean> late = offered(returnCase(45, 120, 'Changed my mind, want my money back.').Id);
        Assert.isFalse(late.containsKey('refund'), 'outside the window refund is not offered');
        Assert.isFalse(late.containsKey('replace'), 'outside the window replace is not offered');
        Assert.isTrue(late.containsKey('repair'));

        Map<String, Boolean> pricey = offered(returnCase(5, 900, 'Arrived with a cracked headband.').Id);
        Assert.isTrue(pricey.get('refund'), 'above the refund limit a refund always goes to review');
        Assert.isFalse(pricey.get('replace'));

        Map<String, Boolean> noAsset = offered(returnCase(null, null, 'I want to return the thing I bought.').Id);
        Assert.isTrue(noAsset.get('refund'), 'unknown purchase: refund goes to review');
        Assert.isTrue(noAsset.get('replace'), 'unknown purchase: replace goes to review');
    }

    @IsTest
    static void refundAboveLimitGoesToReview() {
        Gavel_TestFactory.ops(true);
        withMock('Gavel_Return_Triage');
        Gavel_MockProvider.respondWith('Gavel_Return_Triage', new Gavel_MockProvider.Body()
            .choice('outcome', new Map<String, Decimal>{ 'refund' => 0.94, 'replace' => 0.02, 'repair' => 0.02, 'reject_policy' => 0.01, 'human_review' => 0.01 }, 0.9)
            .noul('customer_caused', 0.03)
            .json());
        Case c = returnCase(5, 900, 'Arrived with a cracked headband.');
        Gavel_Runtime.RunResult r = Gavel_Runtime.run(c.Id, 'Gavel_Return_Triage');
        Assert.areEqual('REVIEW', r.outcome);
        Assert.areEqual('escape_selected', r.reason, 'a confident refund above the limit still needs a person');
    }

    @IsTest
    static void liveReturnSetsOutcomeField() {
        Gavel_TestFactory.ops(true);
        Gavel_Definition d = withMock('Gavel_Return_Triage');
        d.mode = 'Live';
        d.autoApply = true;
        Gavel_MockProvider.respondWith('Gavel_Return_Triage', new Gavel_MockProvider.Body()
            .choice('outcome', new Map<String, Decimal>{ 'refund' => 0.94, 'replace' => 0.02, 'repair' => 0.02, 'reject_policy' => 0.01, 'human_review' => 0.01 }, 0.9)
            .noul('customer_caused', 0.03)
            .json());
        Case c = returnCase(10, 120, 'Left earcup stopped working after a week.');
        User runtimeUser = Gavel_TestFactory.user('System Administrator');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = runtimeUser.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Gavel_Service_Pack'].Id);
        }
        Gavel_Runtime.RunResult r;
        System.runAs(runtimeUser) {
            r = Gavel_Runtime.run(c.Id, 'Gavel_Return_Triage');
        }
        Assert.areEqual('AUTO', r.outcome, 'detail: ' + r.reason);
        Assert.areEqual('refund', [SELECT Gavel_Return_Outcome__c FROM Case WHERE Id = :c.Id].Gavel_Return_Outcome__c,
            'Gavel records the outcome; it never moves money');
    }

    // Returns photo check (jev-1.14.0): the Case photo goes as an image; no photo -> SKIP
    @IsTest
    static void photoCheckSendsTheImage() {
        Gavel_TestFactory.ops(true);
        Gavel_Definition d = withMock('Gavel_Return_Photo_Check');
        Assert.areEqual('jev-1.14.0', d.model, 'pinned, so it can be promoted to Live');
        Gavel_MockProvider.respondWith('Gavel_Return_Photo_Check', new Gavel_MockProvider.Body().withModel('jev-1.14.0')
            .noul('damage_visible', 0.95)
            .noul('matches_claim', 0.92)
            .box('damage_area', 0.3, 0.55, 0.4, 0.7, 0.88)
            .json());
        Case c = returnCase(10, 120, 'The headband arrived cracked, photo attached.');
        Gavel_TestFactory.attachImage(c.Id, 'photo.png', Gavel_TestFactory.png());
        Gavel_Runtime.RunResult r = Gavel_Runtime.run(c.Id, 'Gavel_Return_Photo_Check');
        Assert.areEqual('AUTO', r.outcome, 'detail: ' + r.reason);
        Gavel_JudgmentRequest sent = Gavel_MockProvider.lastRequest;
        Assert.areEqual(1, sent.assets.size());
        Assert.areEqual(sent.assets[0].reference, sent.state.get('photo'));
        Assert.areEqual('0.3,0.55,0.4,0.7', r.answerValues.get('damage_area'), 'the box is recorded for the reviewer');
        Gavel_Decision_Log__c e = [SELECT State_JSON__c, Answers_JSON__c FROM Gavel_Decision_Log__c WHERE Id = :r.ledgerId];
        Assert.isTrue(e.Answers_JSON__c.contains('"box"'), 'box coordinates are in the ledger');

        Case bare = returnCase(10, 120, 'No photo on this one.');
        Gavel_Runtime.RunResult skipped = Gavel_Runtime.run(bare.Id, 'Gavel_Return_Photo_Check');
        Assert.areEqual('SKIP', skipped.outcome);
        Assert.areEqual('insufficient_state', skipped.reason);
    }

    // A photo that does not match the claim sends a confident refund or replace to a person
    @IsTest
    static void photoMismatchSendsMoneyOutcomesToReview() {
        Gavel_TestFactory.ops(true);
        withMock('Gavel_Return_Photo_Check');
        withMock('Gavel_Return_Triage');
        Case c = returnCase(10, 120, 'The headband arrived cracked, photo attached.');
        Gavel_TestFactory.attachImage(c.Id, 'photo.png', Gavel_TestFactory.png());
        Gavel_MockProvider.respondWith('Gavel_Return_Photo_Check', new Gavel_MockProvider.Body().withModel('jev-1.14.0')
            .noul('damage_visible', 0.22)
            .noul('matches_claim', 0.05)
            .box('damage_area', 0.54, 0.95, 0.05, 0.22, 0.02)
            .json());
        Gavel_Runtime.RunResult photo = Gavel_Runtime.run(c.Id, 'Gavel_Return_Photo_Check');
        Assert.areEqual('false', photo.answerValues.get('matches_claim'));

        Gavel_MockProvider.respondWith('Gavel_Return_Triage', new Gavel_MockProvider.Body()
            .choice('outcome', new Map<String, Decimal>{ 'refund' => 0, 'replace' => 0.95, 'repair' => 0, 'reject_policy' => 0.01, 'human_review' => 0.04 }, 0.94)
            .noul('customer_caused', 0.03)
            .json());
        Gavel_Runtime.RunResult triage = Gavel_Runtime.run(c.Id, 'Gavel_Return_Triage');
        Assert.areEqual('REVIEW', triage.outcome, 'the text alone says replace; the photo says otherwise');
        Assert.areEqual('escape_selected', triage.reason);
    }
}
