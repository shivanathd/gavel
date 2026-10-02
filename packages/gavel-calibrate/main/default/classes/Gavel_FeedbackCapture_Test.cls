@IsTest
private class Gavel_FeedbackCapture_Test {
    private static Gavel_Definition liveTriage(String name) {
        Gavel_Definition d = Gavel_TestFactory.triage(name);
        d.mode = Gavel_Definition.MODE_LIVE;
        d.actionMaps.add(new Gavel_Definition.ActionMap('category', 'BILLING', 'set_field', 'Case.Type', 'BILLING'));
        return Gavel_TestFactory.register(d);
    }

    private static void respond(String def, Decimal top) {
        Decimal rest = (1 - top) / 3;
        Gavel_MockProvider.respondWith(def, new Gavel_MockProvider.Body()
            .choice('category', new Map<String, Decimal>{ 'BILLING' => top, 'FRAUD' => rest, 'TECHNICAL' => rest, 'ACCOUNT' => 1 - top - 2 * rest }, 0.9)
            .noul('fraud_concern', 0.02).json());
    }

    @IsTest
    static void reviewResolutionsBecomeFeedback() {
        Gavel_TestFactory.ops(true);
        liveTriage('Fb_Review');
        respond('Fb_Review', 0.6); // REVIEW band -> work item
        Case a = Gavel_TestFactory.newCase('A', 'first');
        Case b = Gavel_TestFactory.newCase('B', 'second');
        insert new List<Case>{ a, b };
        List<Gavel_Runtime.RunResult> rs = Gavel_Runtime.runAll(new List<Gavel_Runtime.RunRequest>{
            new Gavel_Runtime.RunRequest(a.Id, 'Fb_Review'), new Gavel_Runtime.RunRequest(b.Id, 'Fb_Review')
        });
        Gavel_Review__c ra = [SELECT Id FROM Gavel_Review__c WHERE Id = :rs[0].reviewId];
        Gavel_Review__c rb = [SELECT Id FROM Gavel_Review__c WHERE Id = :rs[1].reviewId];
        ra.Status__c = 'Confirmed';
        rb.Status__c = 'Corrected';
        rb.Resolution_Value__c = 'TECHNICAL';
        update new List<Gavel_Review__c>{ ra, rb };
        Map<Id, Gavel_Feedback__c> byLog = new Map<Id, Gavel_Feedback__c>();
        for (Gavel_Feedback__c f : [SELECT Decision_Log__c, Type__c, Human_Value__c, Mapped_Option__c, Correct__c, Calibration_Value__c FROM Gavel_Feedback__c]) {
            byLog.put(f.Decision_Log__c, f);
        }
        Assert.areEqual('confirmed', byLog.get(rs[0].ledgerId).Type__c);
        Assert.isTrue(byLog.get(rs[0].ledgerId).Correct__c);
        Assert.areEqual('corrected', byLog.get(rs[1].ledgerId).Type__c);
        Assert.areEqual('TECHNICAL', byLog.get(rs[1].ledgerId).Mapped_Option__c);
        Assert.isFalse(byLog.get(rs[1].ledgerId).Correct__c);
        Assert.isTrue(byLog.get(rs[0].ledgerId).Calibration_Value__c == 0.6, 'calibration value copied from the ledger');
    }

    @IsTest
    static void integrationUsersAreExcluded() {
        Gavel_Config.Ops ops = Gavel_TestFactory.ops(true);
        liveTriage('Fb_Integration');
        respond('Fb_Integration', 0.95);
        Case c = Gavel_TestFactory.newCase('C', 'third');
        insert c;
        Gavel_Runtime.run(c.Id, 'Fb_Integration');
        ops.integrationUsers.add(UserInfo.getUserName().toLowerCase());
        c.Type = 'Other';
        update c;
        Assert.areEqual(0, [SELECT COUNT() FROM Gavel_Feedback__c], 'integration user edits are not human feedback');
        Assert.isTrue(Gavel_FeedbackCapture.isAutomated());
    }

    @IsTest
    static void unmappedAndOutsideWindow() {
        Gavel_TestFactory.ops(true);
        liveTriage('Fb_Unmapped');
        respond('Fb_Unmapped', 0.95);
        Case c = Gavel_TestFactory.newCase('D', 'fourth');
        insert c;
        Gavel_Runtime.run(c.Id, 'Fb_Unmapped');
        c.Type = 'Something Else';
        update c;
        Gavel_Feedback__c f = [SELECT Unmapped__c, Mapped_Option__c FROM Gavel_Feedback__c];
        Assert.isTrue(f.Unmapped__c, 'stored with unmapped=true, excluded from calibration');
        Assert.isNull(f.Mapped_Option__c);

        // Outside the feedback window nothing is captured.
        Gavel_Config.Ops ops = Gavel_TestFactory.ops(true);
        ops.feedbackWindowHours = -1; // window ends before the entry
        c.Type = 'BILLING';
        update c;
        Assert.areEqual(1, [SELECT COUNT() FROM Gavel_Feedback__c]);
    }

    @IsTest
    static void unrelatedChangesIgnored() {
        Gavel_TestFactory.ops(true);
        liveTriage('Fb_Unrelated');
        Case c = Gavel_TestFactory.newCase('E', 'fifth');
        insert c;
        c.Subject = 'Only the subject changed';
        update c;
        Lead l = new Lead(LastName = 'X', Company = 'Y');
        insert l;
        l.Company = 'Z';
        update l;
        Assert.areEqual(0, [SELECT COUNT() FROM Gavel_Feedback__c]);
    }
}
