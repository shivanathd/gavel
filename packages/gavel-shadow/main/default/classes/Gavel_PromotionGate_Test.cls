@IsTest
private class Gavel_PromotionGate_Test {
    private static final String DEF = 'Gate_Triage';

    /** Gavel_Calibration_Report__c ships in gavel-calibrate; create it dynamically when present. */
    private static Boolean reportObjectExists() {
        return Schema.getGlobalDescribe().containsKey('gavel_calibration_report__c');
    }

    private static Id report(Integer labeled, Datetime generated, String status) {
        SObject rep = Schema.getGlobalDescribe().get('gavel_calibration_report__c').newSObject();
        rep.put('Definition__c', DEF);
        rep.put('Definition_Version__c', 1);
        rep.put('Labeled_Count__c', labeled);
        rep.put('Generated_At__c', generated);
        rep.put('Recommendation_Status__c', status);
        insert rep;
        return rep.Id;
    }

    @IsTest
    static void calibratedDefinitionMayPromote() {
        Gavel_TestFactory.register(Gavel_TestFactory.triage(DEF));
        if (!reportObjectExists()) {
            Assert.areEqual('insufficient_calibration_sample', Gavel_PromotionGate.canPromote(DEF).reason);
            return;
        }
        Id rid = report(250, System.now().addDays(-2), 'recommended');
        Gavel_PromotionGate.Result r = Gavel_PromotionGate.canPromote(DEF);
        Assert.isTrue(r.allowed, 'detail: ' + r.reason);
        Assert.areEqual(rid, r.reportId);
        Assert.areEqual(250, r.labeledCount);

        Gavel_ModeChange.Result change = Gavel_ModeChange.requestMode(DEF, 'Live');
        Assert.isTrue(change.accepted, 'detail: ' + change.reason);
        Assert.areEqual(1, Gavel_ModeChange.captured.size(), 'Mode__c deploy enqueued');
    }

    @IsTest
    static void staleSmallOrFailedReportsBlock() {
        Gavel_TestFactory.register(Gavel_TestFactory.triage(DEF));
        if (!reportObjectExists()) {
            return;
        }
        report(250, System.now().addDays(-20), 'recommended');
        Assert.areEqual('calibration_report_stale', Gavel_PromotionGate.canPromote(DEF).reason);
        report(150, System.now().addDays(-1), 'recommended');
        Assert.areEqual('insufficient_calibration_sample', Gavel_PromotionGate.canPromote(DEF).reason);
        report(400, System.now(), 'none_meets_target');
        Assert.areEqual('no_threshold_meets_target', Gavel_PromotionGate.canPromote(DEF).reason);
    }

    @IsTest
    static void modeChangeRefusedWithoutCalibration() {
        Gavel_TestFactory.register(Gavel_TestFactory.triage(DEF));
        Gavel_ModeChange.Result r = Gavel_ModeChange.requestMode(DEF, 'Live');
        Assert.isFalse(r.accepted);
        Assert.areEqual('insufficient_calibration_sample', r.reason);
        Assert.isTrue(Gavel_ModeChange.captured.isEmpty(), 'nothing deployed');

        // Demotion and retirement need no gate.
        Gavel_ModeChange.Result back = Gavel_ModeChange.requestMode(DEF, 'Retired');
        Assert.isTrue(back.accepted);
        Metadata.CustomMetadata md = (Metadata.CustomMetadata) Gavel_ModeChange.captured[0].getMetadata()[0];
        Assert.areEqual('Gavel_Decision.' + DEF, md.fullName);
        Boolean modeSet = false;
        for (Metadata.CustomMetadataValue v : md.values) {
            if (v.field == 'Mode__c') {
                modeSet = (String) v.value == 'Retired';
            }
        }
        Assert.isTrue(modeSet);
        Assert.areEqual('invalid_mode', Gavel_ModeChange.requestMode(DEF, 'Sideways').reason);
        Assert.areEqual('definition_not_found', Gavel_ModeChange.requestMode('Nope', 'Shadow').reason);
    }
}
