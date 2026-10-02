@IsTest
private class Gavel_DisagreementReport_Test {
    private static Gavel_Baseline__c b(Id logId, String status, Boolean agrees, String gavel, String mapped, String raw, Decimal cal, Boolean auto) {
        return new Gavel_Baseline__c(
            Decision_Log__c = logId, Definition__c = 'Report_Def', Definition_Version__c = 1, Question_Key__c = 'q',
            Status__c = status, Agrees__c = agrees, Gavel_Value__c = gavel, Mapped_Option__c = mapped,
            Baseline_Value__c = raw, Calibration_Value__c = cal, Would_Auto__c = auto
        );
    }

    @IsTest
    static void mathFixture() {
        Gavel_Decision_Log__c e = Gavel_Ledger.newEntry(null, 'Report_Def', null, 'rk');
        e.Outcome__c = 'REVIEW';
        Gavel_Ledger.write(new List<Gavel_Decision_Log__c>{ e });
        insert new List<Gavel_Baseline__c>{
            b(e.Id, 'captured', true, 'A', 'A', 'a', 0.91, true),
            b(e.Id, 'captured', true, 'A', 'A', 'a', 0.99, true),
            b(e.Id, 'captured', false, 'A', 'B', 'b', 0.95, true),
            b(e.Id, 'captured', false, 'B', 'A', 'a', 0.42, false),
            b(e.Id, 'captured', false, 'B', 'A', 'a', 0.45, false),
            b(e.Id, 'baseline_unmapped', false, 'B', null, 'zzz', 0.40, false),
            b(e.Id, 'baseline_missing', false, 'A', null, null, 0.80, false),
            b(e.Id, 'circular', false, 'A', 'A', 'a', 1.00, true)
        };
        Gavel_DisagreementReport.QuestionReport q = Gavel_DisagreementReport.build('Report_Def', 1).questions.get('q');
        Assert.areEqual(8, q.sampleSize);
        Assert.areEqual(6, q.compared, 'missing and circular excluded');
        Assert.areEqual(2, q.agreed);
        Assert.isTrue(q.agreementRate == 0.3333, '' + String.valueOf(q.agreementRate));
        Assert.areEqual(1, q.missing);
        Assert.areEqual(1, q.circular);
        Assert.areEqual(1, q.unmapped);
        Assert.areEqual(4, q.wouldAuto);
        Assert.isTrue(q.wouldAutoShare == 0.5, '' + String.valueOf(q.wouldAutoShare));
        Assert.areEqual(3, q.bands[9].n);
        Assert.isTrue(q.bands[9].rate == 0.6667, '' + String.valueOf(q.bands[9].rate));
        Assert.areEqual(3, q.bands[4].n);
        Assert.isTrue(q.bands[4].rate == 0, '' + String.valueOf(q.bands[4].rate));
        Assert.isNull(q.bands[1].rate, 'empty band has no rate');
        Assert.areEqual('B', q.topDisagreements[0].gavel);
        Assert.areEqual('A', q.topDisagreements[0].baseline);
        Assert.areEqual(2, q.topDisagreements[0].count, 'most frequent pair first');
        Assert.areEqual(3, q.topDisagreements.size());
    }

    @IsTest
    static void emptyDefinition() {
        Gavel_DisagreementReport.Report r = Gavel_DisagreementReport.build('Nothing');
        Assert.isTrue(r.questions.isEmpty());
        Assert.isTrue(Gavel_DisagreementReport.reportJson('Nothing').contains('"questions":{}'));
    }
}
