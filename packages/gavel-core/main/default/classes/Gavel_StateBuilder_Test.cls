@IsTest
private class Gavel_StateBuilder_Test {
    private static Gavel_Definition subjectAndDescription(Boolean descriptionRequired) {
        Gavel_Definition d = Gavel_TestFactory.definition('Test_State', 'Case');
        d.questions.add(Gavel_TestFactory.noul('q'));
        d.stateFields.add(new Gavel_Definition.StateField('Subject', 'subject', false));
        d.stateFields.add(new Gavel_Definition.StateField('Description', 'description', descriptionRequired));
        return d;
    }

    // AS-3.1 Only allowlisted fields leave
    @IsTest
    static void onlyAllowlistedFields() {
        Gavel_TestFactory.ops(true);
        Case c = Gavel_TestFactory.newCase('Login broken', 'Cannot sign in since Monday');
        c.SuppliedEmail = 'customer@example.com';
        c.SuppliedName = 'Pat Customer';
        insert c;
        Gavel_StateBuilder.StateResult r = Gavel_StateBuilder.build(c.Id, subjectAndDescription(true));
        Assert.isNull(r.blockedReason);
        Assert.areEqual(new Set<String>{ 'subject', 'description' }, r.state.keySet());
        Assert.isFalse(r.stateJson.contains('customer@example.com'), 'non-allowlisted SuppliedEmail never leaves');
        Assert.isFalse(r.stateJson.contains('Pat Customer'));
        Assert.areEqual('{"description":"Cannot sign in since Monday","subject":"Login broken"}', r.stateJson, 'canonical JSON: sorted keys, no whitespace');
        Assert.areEqual(Gavel_Json.sha256Hex(r.stateJson), r.stateHash);
    }

    // AS-3.2 Card number redacted
    @IsTest
    static void cardNumberRedacted() {
        Gavel_TestFactory.ops(true);
        Case c = Gavel_TestFactory.newCase('Refund', 'Please refund card 4111 1111 1111 1111 for order 7');
        insert c;
        Gavel_Definition d = subjectAndDescription(true);
        d.stateFields[1].redactionProfile = 'strict';
        Gavel_StateBuilder.StateResult r = Gavel_StateBuilder.build(c.Id, d);
        String descText = (String) r.state.get('description');
        Assert.isTrue(descText.contains('[REDACTED:payment]'), descText);
        Assert.isFalse(r.stateJson.contains('4111'), 'card digits never leave');
        Assert.isTrue(r.redactionsApplied.contains('payment:1'), String.valueOf(r.redactionsApplied));
        Assert.areEqual('payment:1', r.redactionSummary());
    }

    // AS-3.3 FLS respected
    @IsTest
    static void flsRespected() {
        Gavel_TestFactory.ops(true);
        User minimal = Gavel_TestFactory.user('Minimum Access - Salesforce');
        Gavel_TestFactory.grantObject(minimal, 'Case', true);
        Case c = Gavel_TestFactory.newCase('Secret', 'Only admins can read this description');
        insert c;
        c.OwnerId = minimal.Id;
        update c;
        Gavel_StateBuilder.StateResult r;
        System.runAs(minimal) {
            r = Gavel_StateBuilder.build(c.Id, subjectAndDescription(true));
        }
        Assert.isTrue(r.missingRequired.contains('description'), String.valueOf(r.missingRequired));
        Assert.areEqual('insufficient_state', r.blockedReason);
        Assert.isFalse(r.stateJson.contains('Only admins'), 'unreadable field never sent');
    }

    // AS-3.4 Kill switch
    @IsTest
    static void killSwitch() {
        Gavel_TestFactory.ops(false);
        Case c = Gavel_TestFactory.newCase('Anything', 'Anything at all');
        insert c;
        Integer queriesBefore = Limits.getQueries();
        Gavel_StateBuilder.StateResult r = Gavel_StateBuilder.build(c.Id, subjectAndDescription(true));
        Assert.areEqual('egress_disabled', r.blockedReason);
        Assert.isTrue(r.state.isEmpty());
        Assert.areEqual(queriesBefore, Limits.getQueries(), 'nothing is even read when egress is off');

    }

    @IsTest
    static void nullContractAndTruncation() {
        Gavel_TestFactory.ops(true);
        Case c = Gavel_TestFactory.newCase('   ', 'x'.repeat(30000));
        insert c;
        Gavel_Definition d = subjectAndDescription(false);
        d.stateFields.add(new Gavel_Definition.StateField('Account.Industry', 'industry', false));
        d.stateFields[1].maxChars = 100;
        Gavel_StateBuilder.StateResult r = Gavel_StateBuilder.build(c.Id, d);
        Assert.isFalse(r.state.containsKey('subject'), 'blank text omitted');
        Assert.isFalse(r.state.containsKey('industry'), 'null parent lookup omitted');
        Assert.isTrue(r.truncated);
        Assert.areEqual(100 + Gavel_StateBuilder.TRUNCATED_MARKER.length(), ((String) r.state.get('description')).length());
        Assert.isTrue(((String) r.state.get('description')).endsWith('[truncated]'));
    }

    @IsTest
    static void parentLookupAndNumbers() {
        Gavel_TestFactory.ops(true);
        Account a = new Account(Name = 'Acme', Industry = 'Banking', NumberOfEmployees = 0, AnnualRevenue = 1000);
        insert a;
        Case c = Gavel_TestFactory.newCase('Hi', 'Body');
        c.AccountId = a.Id;
        insert c;
        Gavel_Definition d = Gavel_TestFactory.definition('Test_Parent', 'Case');
        d.questions.add(Gavel_TestFactory.noul('q'));
        d.stateFields.add(new Gavel_Definition.StateField('Account.Industry', 'industry', true));
        d.stateFields.add(new Gavel_Definition.StateField('Account.NumberOfEmployees', 'employees', false));
        Gavel_Definition.StateField zero = new Gavel_Definition.StateField('Account.AnnualRevenue', 'revenue', false);
        d.stateFields.add(zero);
        Gavel_StateBuilder.StateResult r = Gavel_StateBuilder.build(c.Id, d);
        Assert.areEqual('Banking', r.state.get('industry'));
        Assert.isFalse(r.state.containsKey('employees'), '0 omitted unless zero is meaningful');
        Assert.isTrue((Decimal) r.state.get('revenue') == 1000, String.valueOf(r.state));
        d.stateFields[1].zeroIsMeaningful = true;
        Assert.isTrue((Decimal) Gavel_StateBuilder.build(c.Id, d).state.get('employees') == 0);
    }

    @IsTest
    static void badPathAndMissingRecord() {
        Gavel_TestFactory.ops(true);
        Case c = Gavel_TestFactory.newCase('Hi', 'Body');
        insert c;
        Gavel_Definition d = subjectAndDescription(false);
        d.stateFields.add(new Gavel_Definition.StateField('No_Such_Field__c', 'nope', false));
        Gavel_StateBuilder.StateResult bad = Gavel_StateBuilder.build(c.Id, d);
        Assert.areEqual('bad_field_path', bad.blockedReason);
        Assert.isTrue(bad.badPaths.contains('No_Such_Field__c'));
        d.stateFields[2].fieldPath = 'Account.Owner.Name';
        Assert.areEqual('bad_field_path', Gavel_StateBuilder.build(c.Id, d).blockedReason, 'only one parent level');

        Gavel_Definition ok = subjectAndDescription(false);
        delete c;
        Assert.areEqual('record_not_found', Gavel_StateBuilder.build(c.Id, ok).blockedReason);
        Assert.areEqual('record_not_found', Gavel_StateBuilder.build(null, ok).blockedReason);
    }

    @IsTest
    static void sourcesInputsAndEmails() {
        Gavel_TestFactory.ops(true);
        Case c = Gavel_TestFactory.newCase('Payroll', 'see emails');
        insert c;
        insert new List<EmailMessage>{
            new EmailMessage(ParentId = c.Id, Incoming = true, Subject = 'Re: payroll', TextBody = 'Fourth call, payroll blocked.\nOn Mon, Jan 5, 2026 at 9:00 AM Support wrote:\n> old quoted text', MessageDate = System.now()),
            new EmailMessage(ParentId = c.Id, Incoming = false, Subject = 'outbound', TextBody = 'We are looking', MessageDate = System.now())
        };
        Lead l = new Lead(LastName = 'Doe', Company = 'Acme', Email = 'jane.doe@Acme-Corp.com');
        insert l;

        Gavel_Definition d = Gavel_TestFactory.definition('Test_Sources', 'Case');
        d.questions.add(Gavel_TestFactory.noul('q'));
        Gavel_Definition.StateField emails = new Gavel_Definition.StateField('EmailMessage.TextBody', 'recent_emails', true);
        emails.source = 'Gavel_StateSources.InboundEmails:3';
        d.stateFields.add(emails);
        Gavel_Definition.StateField missingSource = new Gavel_Definition.StateField('Nothing', 'nothing', false);
        missingSource.source = 'No_Such_Class';
        d.stateFields.add(missingSource);
        Gavel_StateBuilder.StateResult r = Gavel_StateBuilder.build(c.Id, d);
        String body = (String) r.state.get('recent_emails');
        Assert.isTrue(body.contains('payroll blocked'), body);
        Assert.isFalse(body.contains('old quoted text'), 'quoted chain stripped');
        Assert.isFalse(body.contains('We are looking'), 'outbound excluded');
        Assert.isFalse(r.state.containsKey('nothing'));

        Gavel_Definition ld = Gavel_TestFactory.definition('Test_Domain', 'Lead');
        ld.questions.add(Gavel_TestFactory.noul('q'));
        Gavel_Definition.StateField domain = new Gavel_Definition.StateField('Email', 'email_domain', true);
        domain.source = 'Gavel_StateSources.EmailDomain';
        ld.stateFields.add(domain);
        Gavel_StateBuilder.StateResult lr = Gavel_StateBuilder.build(l.Id, ld);
        Assert.areEqual('acme-corp.com', lr.state.get('email_domain'));
        Assert.isFalse(lr.stateJson.contains('jane.doe'), 'only the domain leaves');

        Gavel_Definition screen = Gavel_TestFactory.definition('Test_Input', Gavel_Definition.TARGET_NONE);
        screen.questions.add(Gavel_TestFactory.noul('q'));
        Gavel_Definition.StateField text = new Gavel_Definition.StateField('input.text', 'text', true);
        text.source = 'Gavel_StateSources.Input';
        screen.stateFields.add(text);
        Gavel_StateBuilder.StateResult sr = Gavel_StateBuilder.build(null, screen, new Map<String, Object>{ 'text' => 'mail me at a@b.co' });
        Assert.areEqual('mail me at [REDACTED:email]', sr.state.get('text'), 'inputs are redacted too');
        Assert.areEqual('insufficient_state', Gavel_StateBuilder.build(null, screen, new Map<String, Object>()).blockedReason);
    }

    @IsTest
    static void stripQuotedAndHtml() {
        Assert.areEqual('Thanks, fixed now', Gavel_StateSources.stripQuoted('Thanks, fixed now\r\n\r\n-----Original Message-----\r\nFrom: x'));
        Assert.areEqual('Top line', Gavel_StateSources.stripQuoted('Top line\n> quoted\n>> more'));
        Assert.areEqual('Bold text', Gavel_StateSources.bodyText(null, '<p><b>Bold</b> text</p>'));
        Assert.isNull(Gavel_StateSources.stripQuoted(null));
    }

    @IsTest
    static void recentActivity() {
        Gavel_TestFactory.ops(true);
        Account a = new Account(Name = 'Acme');
        insert a;
        Opportunity o = new Opportunity(Name = 'Deal', AccountId = a.Id, StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert o;
        insert new Task(WhatId = o.Id, Subject = 'Call', Description = 'CFO confirmed budget of 50k');
        Gavel_StateContext ctx = new Gavel_StateContext();
        ctx.recordId = o.Id;
        ctx.arg = '10';
        String text = (String) new Gavel_StateSources.RecentActivity().resolve(ctx);
        Assert.isTrue(text.contains('CFO confirmed budget'), text);
        ctx.recordId = null;
        Assert.isNull(new Gavel_StateSources.RecentActivity().resolve(ctx));
        Assert.isNull(new Gavel_StateSources.InboundEmails().resolve(ctx));
        Assert.isNull(new Gavel_StateSources.EmailBody().resolve(ctx));
        Assert.isNull(new Gavel_StateSources.EmailDomain().resolve(ctx));
    }
}
