@IsTest
private class Gavel_SalesMarketingPack_Test {
    private static final List<String> DEFINITIONS = new List<String>{
        'Gavel_Lead_Quality', 'Gavel_Reply_Intent', 'Gavel_Opt_Out_Detect', 'Gavel_Persona', 'Gavel_Stage_Evidence'
    };

    private static Gavel_Definition withMock(String api) {
        Gavel_Definition d = Gavel_DefinitionRepo.get(api);
        Assert.isNotNull(d, api + ' must be deployed with the pack');
        d.providerClass = Gavel_TestFactory.MOCK_PROVIDER;
        return d;
    }

    private static EmailMessage inboundFrom(Id personId, String body) {
        // No FromAddress on the message: Salesforce would create a second sender relation from it.
        EmailMessage e = new EmailMessage(Incoming = true, Subject = 'Re: our conversation', TextBody = body, MessageDate = System.now());
        insert e;
        insert new EmailMessageRelation(EmailMessageId = e.Id, RelationId = personId, RelationType = 'FromAddress');
        return e;
    }

    // AS-12.1 Hidden opt-out
    @IsTest
    static void hiddenOptOut() {
        Gavel_TestFactory.ops(true);
        Gavel_Definition d = withMock('Gavel_Opt_Out_Detect');
        Assert.areEqual('Live', d.mode, 'Opt-Out installs Live-Review');
        d.autoApply = true; // the admin has enabled auto-apply
        Contact c = new Contact(LastName = 'Rivera', Email = 'rivera@example.com');
        insert c;
        EmailMessage reply = inboundFrom(c.Id, 'please take me off your list, thanks\n\nOn Mon, someone wrote:\n> our product update');
        // Actions run in user mode: the runtime user needs the pack permission set (edit on HasOptedOutOfEmail).
        User runtimeUser = Gavel_TestFactory.user('System Administrator');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = runtimeUser.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Gavel_Sales_Marketing_Pack'].Id);
        }
        Gavel_Runtime.RunResult r;
        System.runAs(runtimeUser) {
            r = Gavel_Runtime.run(reply.Id, 'Gavel_Opt_Out_Detect');
        }
        Assert.areEqual('AUTO', r.outcome, 'detail: ' + r.reason);
        String diag = 'action=' + [SELECT Action_Taken__c FROM Gavel_Decision_Log__c WHERE Id = :r.ledgerId].Action_Taken__c;
        for (Gavel_Action_Log__c l : [SELECT Status__c, Detail__c, Target__c FROM Gavel_Action_Log__c WHERE Decision_Log__c = :r.ledgerId]) {
            diag += ' | log ' + l.Target__c + ' ' + l.Status__c + ' ' + l.Detail__c;
        }
        for (EmailMessageRelation rel : [SELECT RelationId, RelationType FROM EmailMessageRelation WHERE EmailMessageId = :reply.Id]) {
            diag += ' | rel ' + rel.RelationType + ' ' + rel.RelationId;
        }
        Assert.isTrue([SELECT HasOptedOutOfEmail FROM Contact WHERE Id = :c.Id].HasOptedOutOfEmail, 'HasOptedOutOfEmail becomes true: ' + diag);
        Gavel_Decision_Log__c e = [SELECT Asymmetric_Reason__c, Action_Taken__c FROM Gavel_Decision_Log__c WHERE Id = :r.ledgerId];
        Assert.isTrue(e.Asymmetric_Reason__c.contains('compliance breach'), 'the ledger records the asymmetric reason');
        Assert.isTrue(e.Action_Taken__c.contains('HasOptedOutOfEmail'));
    }

    @IsTest
    static void liveReviewUntilAutoApplyIsEnabled() {
        Gavel_TestFactory.ops(true);
        withMock('Gavel_Opt_Out_Detect'); // shipped: Live, Auto_Apply__c = false
        Lead l = new Lead(LastName = 'Nguyen', Company = 'Acme', Email = 'nguyen@example.com');
        insert l;
        EmailMessage reply = inboundFrom(l.Id, 'Please unsubscribe me from these emails.');
        Gavel_Runtime.RunResult r = Gavel_Runtime.run(reply.Id, 'Gavel_Opt_Out_Detect');
        Assert.areEqual('AUTO', r.outcome);
        Assert.areEqual('auto_apply_disabled', r.actionTaken);
        Assert.isFalse([SELECT HasOptedOutOfEmail FROM Lead WHERE Id = :l.Id].HasOptedOutOfEmail);
        Assert.isNotNull(r.reviewId, 'a REVIEW record is created instead');

        // Provider error: fail closed toward a human check, never toward ignoring.
        Gavel_MockProvider.failWith('Gavel_Opt_Out_Detect', 'timeout', null);
        EmailMessage second = inboundFrom(l.Id, 'Remove me from your list please');
        Gavel_Runtime.RunResult err = Gavel_Runtime.run(second.Id, 'Gavel_Opt_Out_Detect');
        Assert.areEqual('ERROR', err.outcome);
        Assert.isNotNull(err.reviewId);
    }

    // AS-12.2 Opt-out never reversed
    @IsTest
    static void optOutNeverReversed() {
        Gavel_TestFactory.ops(true);
        Gavel_Definition optOut = withMock('Gavel_Opt_Out_Detect');
        optOut.autoApply = true;
        Contact c = new Contact(LastName = 'Okafor', Email = 'okafor@example.com', HasOptedOutOfEmail = true);
        insert c;
        // A reply that is not an opt-out does not touch the flag.
        Gavel_Runtime.run(inboundFrom(c.Id, 'Thanks, see you at the conference.').Id, 'Gavel_Opt_Out_Detect');
        Assert.isTrue([SELECT HasOptedOutOfEmail FROM Contact WHERE Id = :c.Id].HasOptedOutOfEmail);

        // Even a misconfigured Live definition that maps an answer to false cannot reverse it.
        Gavel_Definition bad = Gavel_TestFactory.definition('Bad_Optin', 'Contact');
        bad.mode = Gavel_Definition.MODE_LIVE;
        bad.questions.add(Gavel_TestFactory.noul('wants_email'));
        bad.policies.add(Gavel_TestFactory.noulPolicy('wants_email', 0.85, 0.5, 'true_is_action'));
        bad.stateFields.add(new Gavel_Definition.StateField('LastName', 'name', true));
        bad.actionMaps.add(new Gavel_Definition.ActionMap('wants_email', 'true', 'set_field', 'Contact.HasOptedOutOfEmail', 'false'));
        Gavel_TestFactory.register(bad);
        Gavel_MockProvider.respondWith('Bad_Optin', new Gavel_MockProvider.Body().noul('wants_email', 0.99).json());
        Gavel_Runtime.RunResult r = Gavel_Runtime.run(c.Id, 'Bad_Optin');
        Assert.areEqual('AUTO', r.outcome);
        Assert.isTrue([SELECT HasOptedOutOfEmail FROM Contact WHERE Id = :c.Id].HasOptedOutOfEmail, 'no action sets HasOptedOutOfEmail to false');
        Assert.areEqual('blocked_monotonic_field', [SELECT Status__c FROM Gavel_Action_Log__c WHERE Decision_Log__c = :r.ledgerId].Status__c);
    }

    // AS-12.3 Junk lead in shadow
    @IsTest
    static void junkLeadShadow() {
        Gavel_TestFactory.ops(true);
        withMock('Gavel_Lead_Quality');
        Lead l = new Lead(LastName = 'asdf', Company = 'asdf', Email = 'asdf@mailinator.com', LeadSource = 'Web', Status = 'Open - Not Contacted');
        insert l;
        Lead before = [SELECT Status, OwnerId, Rating, Company, LeadSource FROM Lead WHERE Id = :l.Id];
        Gavel_Runtime.RunResult r = Gavel_Runtime.run(l.Id, 'Gavel_Lead_Quality');
        Assert.isTrue(r.topChoice == 'spam' || r.topChoice == 'test_data', 'ledger shows spam or test_data: ' + r.topChoice);
        Gavel_Decision_Log__c e = [SELECT Top_Choice__c, Mode__c, Action_Suppressed__c FROM Gavel_Decision_Log__c WHERE Id = :r.ledgerId];
        Assert.areEqual(r.topChoice, e.Top_Choice__c);
        Assert.areEqual('Shadow', e.Mode__c);
        Assert.areEqual(before, [SELECT Status, OwnerId, Rating, Company, LeadSource FROM Lead WHERE Id = :l.Id], 'no Lead field changes');
        Assert.isFalse(Gavel_MockProvider.lastRequest.canonicalState().contains('asdf@'), 'only the email domain leaves');
    }

    @IsTest
    static void stageEvidenceSetsHelperFieldWhenLive() {
        Gavel_TestFactory.ops(true);
        Gavel_Definition d = withMock('Gavel_Stage_Evidence');
        Account a = new Account(Name = 'Globex');
        insert a;
        Opportunity good = new Opportunity(Name = 'Expansion', AccountId = a.Id, StageName = 'Qualification', CloseDate = Date.today().addDays(30));
        Opportunity thin = new Opportunity(Name = 'Pilot', AccountId = a.Id, StageName = 'Qualification', CloseDate = Date.today().addDays(30));
        insert new List<Opportunity>{ good, thin };
        insert new List<Task>{
            new Task(WhatId = good.Id, Subject = 'Call', Description = 'Met the CFO. CFO approved budget for Q3, procurement timeline agreed.'),
            new Task(WhatId = thin.Id, Subject = 'Call', Description = 'Intro call, general interest.')
        };
        List<Gavel_StageEvidence.Result> shadow = Gavel_StageEvidence.check(new List<Id>{ good.Id });
        Assert.areEqual('Verified', shadow[0].status);
        Assert.isNull([SELECT Gavel_Stage_Evidence_Status__c FROM Opportunity WHERE Id = :good.Id].Gavel_Stage_Evidence_Status__c, 'Shadow only ledgers');

        d.mode = Gavel_Definition.MODE_LIVE;
        Gavel_StageEvidence.Request rq = new Gavel_StageEvidence.Request();
        rq.opportunityId = thin.Id;
        Gavel_StageEvidence.Result r = Gavel_StageEvidence.invoke(new List<Gavel_StageEvidence.Request>{ rq })[0];
        Assert.areEqual('Needs Review', r.status, 'REVIEW blocks the stage change through the helper field');
        Assert.areEqual('Needs Review', [SELECT Gavel_Stage_Evidence_Status__c FROM Opportunity WHERE Id = :thin.Id].Gavel_Stage_Evidence_Status__c);
    }

    @IsTest
    static void replyIntentAndPersona() {
        Gavel_TestFactory.ops(true);
        withMock('Gavel_Reply_Intent');
        withMock('Gavel_Persona');
        Lead l = new Lead(LastName = 'Kim', Company = 'Initech', Title = 'VP Engineering', Email = 'kim@initech.example.com');
        insert l;
        EmailMessage ooo = inboundFrom(l.Id, 'I no longer work here. Out of office permanently.');
        List<Gavel_Runtime.RunResult> rs = Gavel_Runtime.runAll(new List<Gavel_Runtime.RunRequest>{
            new Gavel_Runtime.RunRequest(ooo.Id, 'Gavel_Reply_Intent'), new Gavel_Runtime.RunRequest(l.Id, 'Gavel_Persona')
        });
        Assert.areEqual('wrong_person', rs[0].topChoice, 'not opt-out');
        Assert.areEqual('executive', rs[1].answerValues.get('persona'));
    }

    @IsTest
    static void shippedDefinitionsInstallSafely() {
        for (String api : DEFINITIONS) {
            Gavel_Definition d = Gavel_DefinitionRepo.get(api);
            Gavel_DefinitionValidator.Result v = Gavel_DefinitionValidator.validate(d);
            Assert.isTrue(v.valid, api + ': ' + v.errors + ' canonical=' + Gavel_DefinitionHasher.canonical(d));
            if (api == 'Gavel_Opt_Out_Detect') {
                Assert.areEqual('Live', d.mode);
                Assert.isFalse(d.autoApply, 'auto-apply only after an admin enables it');
            } else {
                Assert.areEqual('Shadow', d.mode, api + ' installs in Shadow');
            }
        }
    }
}
