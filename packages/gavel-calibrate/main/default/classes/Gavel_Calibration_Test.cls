@IsTest
private class Gavel_Calibration_Test {
    private static Gavel_Definition liveTriage(String name) {
        Gavel_Definition d = Gavel_TestFactory.triage(name);
        d.mode = Gavel_Definition.MODE_LIVE;
        for (String k : new List<String>{ 'BILLING', 'FRAUD', 'TECHNICAL', 'ACCOUNT' }) {
            d.actionMaps.add(new Gavel_Definition.ActionMap('category', k, 'set_field', 'Case.Type', k));
        }
        return Gavel_TestFactory.register(d);
    }

    /** n ledger entries for a definition with a given calibration value, plus feedback labels. */
    private static void labeled(String def, Integer n, Decimal value, Integer correct) {
        List<Gavel_Decision_Log__c> entries = new List<Gavel_Decision_Log__c>();
        for (Integer i = 0; i < n; i++) {
            Gavel_Decision_Log__c e = Gavel_Ledger.newEntry(null, def, null, def + value + ':' + i);
            e.Version__c = 1;
            e.Outcome__c = 'REVIEW';
            e.Answers_JSON__c = JSON.serialize(new Map<String, Object>{
                'outcomes' => new Map<String, Object>{
                    'category' => new Map<String, Object>{ 'outcome' => 'REVIEW', 'answer' => 'BILLING', 'calibrationValue' => value }
                }
            });
            entries.add(e);
        }
        Gavel_Ledger.write(entries);
        List<Gavel_Feedback__c> fb = new List<Gavel_Feedback__c>();
        for (Integer i = 0; i < n; i++) {
            Boolean ok = i < correct;
            fb.add(new Gavel_Feedback__c(
                Decision_Log__c = entries[i].Id, Type__c = ok ? 'confirmed' : 'corrected', Definition__c = def,
                Definition_Version__c = 1, Question_Key__c = 'category', Gavel_Value__c = 'BILLING',
                Human_Value__c = ok ? 'BILLING' : 'FRAUD', Mapped_Option__c = ok ? 'BILLING' : 'FRAUD',
                Unmapped__c = false, Correct__c = ok, Calibration_Value__c = value
            ));
        }
        insert fb;
    }

    // AS-8.1 Override captured
    @IsTest
    static void overrideCaptured() {
        Gavel_TestFactory.ops(true);
        liveTriage('Cal_Triage');
        Gavel_MockProvider.respondWith('Cal_Triage', new Gavel_MockProvider.Body()
            .choice('category', new Map<String, Decimal>{ 'BILLING' => 0.95, 'FRAUD' => 0.02, 'TECHNICAL' => 0.02, 'ACCOUNT' => 0.01 }, 0.9)
            .noul('fraud_concern', 0.02).json());
        Case c = Gavel_TestFactory.newCase('Charge', 'I see an unexpected charge');
        insert c;
        Gavel_Runtime.RunResult run = Gavel_Runtime.run(c.Id, 'Cal_Triage');
        Assert.areEqual('AUTO', run.outcome);
        Assert.areEqual('BILLING', [SELECT Type FROM Case WHERE Id = :c.Id].Type, 'Gavel set Case.Type');
        Assert.areEqual(0, [SELECT COUNT() FROM Gavel_Feedback__c], 'Gavel\'s own action is not feedback');

        // An agent corrects it within 72 hours.
        c.Type = 'FRAUD';
        update c;
        Gavel_Feedback__c f = [
            SELECT Type__c, Decision_Log__c, Human_Value__c, Gavel_Value__c, Mapped_Option__c, Correct__c, Unmapped__c, Question_Key__c, Field__c
            FROM Gavel_Feedback__c
        ];
        Assert.areEqual('override', f.Type__c);
        Assert.areEqual(run.ledgerId, f.Decision_Log__c);
        Assert.areEqual('FRAUD', f.Human_Value__c);
        Assert.areEqual('FRAUD', f.Mapped_Option__c);
        Assert.areEqual('BILLING', f.Gavel_Value__c);
        Assert.isFalse(f.Correct__c);
        Assert.isFalse(f.Unmapped__c);
        Assert.areEqual('Case.Type', f.Field__c);
    }

    // AS-8.2 Recommendation meets target
    @IsTest
    static void recommendationMeetsTarget() {
        Gavel_TestFactory.ops(true);
        Gavel_TestFactory.register(Gavel_TestFactory.triage('Cal_Fixture'));
        labeled('Cal_Fixture', 300, 0.85, 288); // 0.96 precision at >= 0.80
        labeled('Cal_Fixture', 50, 0.75, 25);
        labeled('Cal_Fixture', 150, 0.65, 75);
        Id rid = new Gavel_CalibrationJob('Cal_Fixture').runNow();
        Gavel_Calibration_Report__c r = [
            SELECT Labeled_Count__c, Recommendation_Status__c, Recommended_Auto_Accept__c, Precision_At_Recommended__c,
                Coverage_At_Recommended__c, Wilson_Lower__c, Wilson_Upper__c, Question_Key__c, Report_JSON__c
            FROM Gavel_Calibration_Report__c WHERE Id = :rid
        ];
        Assert.areEqual(500, r.Labeled_Count__c);
        Assert.areEqual('recommended', r.Recommendation_Status__c);
        Assert.isTrue(r.Recommended_Auto_Accept__c == 0.80, '' + String.valueOf(r.Recommended_Auto_Accept__c));
        Assert.isTrue(r.Precision_At_Recommended__c == 0.96, '' + String.valueOf(r.Precision_At_Recommended__c));
        Assert.isTrue(r.Coverage_At_Recommended__c == 0.6, 'coverage shown');
        Assert.isTrue(r.Wilson_Lower__c == 0.9314, 'Wilson lower ' + r.Wilson_Lower__c);
        Assert.isTrue(r.Wilson_Upper__c == 0.9770, 'Wilson upper ' + r.Wilson_Upper__c);
        Assert.areEqual('category', r.Question_Key__c);
        Assert.isTrue(r.Report_JSON__c.contains('"reliability"'));
    }

    // AS-8.3 No auto-change
    @IsTest
    static void noAutoChange() {
        Gavel_TestFactory.ops(true);
        Gavel_TestFactory.register(Gavel_TestFactory.triage('Cal_Fixed'));
        Decimal before = Gavel_DefinitionRepo.get('Cal_Fixed').policy('category').autoAccept;
        List<Gavel_Policy__mdt> shippedBefore = [SELECT DeveloperName, Auto_Accept__c FROM Gavel_Policy__mdt ORDER BY DeveloperName];
        labeled('Cal_Fixed', 100, 0.75, 98);
        labeled('Cal_Fixed', 100, 0.70, 50);
        Test.startTest();
        Database.executeBatch(new Gavel_CalibrationJob('Cal_Fixed', 1), 2000);
        Test.stopTest();
        Gavel_Calibration_Report__c r = [SELECT Recommended_Auto_Accept__c FROM Gavel_Calibration_Report__c WHERE Definition__c = 'Cal_Fixed'];
        Assert.isTrue(r.Recommended_Auto_Accept__c == 0.75, '' + String.valueOf(r.Recommended_Auto_Accept__c));
        Assert.areEqual(before, Gavel_DefinitionRepo.get('Cal_Fixed').policy('category').autoAccept, 'threshold unchanged');
        Assert.areEqual(JSON.serialize(shippedBefore), JSON.serialize([SELECT DeveloperName, Auto_Accept__c FROM Gavel_Policy__mdt ORDER BY DeveloperName]), 'no CMDT changed');
    }

    @IsTest
    static void noneMeetsTargetAndEmpty() {
        Gavel_TestFactory.ops(true);
        Gavel_TestFactory.register(Gavel_TestFactory.triage('Cal_Weak'));
        labeled('Cal_Weak', 60, 0.9, 30);
        new Gavel_CalibrationJob('Cal_Weak').runNow();
        Assert.areEqual('none_meets_target', [SELECT Recommendation_Status__c FROM Gavel_Calibration_Report__c WHERE Definition__c = 'Cal_Weak'].Recommendation_Status__c);
        Gavel_TestFactory.register(Gavel_TestFactory.triage('Cal_Empty'));
        new Gavel_CalibrationJob('Cal_Empty').runNow();
        Assert.areEqual('insufficient_data', [SELECT Recommendation_Status__c FROM Gavel_Calibration_Report__c WHERE Definition__c = 'Cal_Empty'].Recommendation_Status__c);
    }

    @IsTest
    static void mathFixtures() {
        Gavel_CalibrationMath.Interval iv = Gavel_CalibrationMath.wilson(90, 100);
        Assert.isTrue(iv.lower == 0.8256, '' + String.valueOf(iv.lower));
        Assert.isTrue(iv.upper == 0.9448, '' + String.valueOf(iv.upper));
        Assert.isNull(Gavel_CalibrationMath.wilson(0, 0).lower);
        List<Gavel_CalibrationMath.Point> pts = new List<Gavel_CalibrationMath.Point>();
        for (Integer i = 0; i < 10; i++) {
            pts.add(new Gavel_CalibrationMath.Point(0.55, i < 9));
        }
        Gavel_CalibrationMath.QuestionCalibration qc = Gavel_CalibrationMath.calibrate('q', pts, 0.9);
        Assert.areEqual(10, qc.reliability[5].n);
        Assert.isTrue(qc.reliability[5].lowSample, 'fewer than 50 labels in a bin is marked low sample');
        Assert.isTrue(qc.recommended == 0.50);
        Assert.areEqual(10, qc.candidates.size(), '0.50 to 0.95 step 0.05');
        Assert.isTrue(qc.candidates[9].threshold == 0.95);
        Assert.isNull(qc.candidates[2].precision, 'nothing covered at 0.60');
    }
}
