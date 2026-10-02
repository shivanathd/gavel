@IsTest
private class Gavel_Shadow_Test {
    private static final String DEF = 'Shadow_Triage';

    private static void maps() {
        Gavel_BaselineMapRepo.registerForTest(new List<Gavel_BaselineMapRepo.Entry>{
            new Gavel_BaselineMapRepo.Entry(DEF, 'category', 'Case.Type', 'Electrical', 'TECHNICAL'),
            new Gavel_BaselineMapRepo.Entry(DEF, 'category', 'Case.Type', 'Other', 'BILLING')
        });
    }

    private static Gavel_Decision_Log__c entry(Case c, String answer, Decimal calibration, String questionOutcome) {
        Gavel_Decision_Log__c e = Gavel_Ledger.newEntry(null, DEF, c.Id, c.Id + ':' + DEF + ':1');
        e.Version__c = 1;
        e.Mode__c = 'Shadow';
        e.Outcome__c = questionOutcome;
        e.Answers_JSON__c = JSON.serialize(new Map<String, Object>{
            'outcomes' => new Map<String, Object>{
                'category' => new Map<String, Object>{ 'outcome' => questionOutcome, 'answer' => answer, 'calibrationValue' => calibration }
            }
        });
        return e;
    }

    // AS-7.1 Agreement report over 300 shadow entries with baselines captured
    @IsTest
    static void agreementReport() {
        maps();
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 300; i++) {
            Case c = Gavel_TestFactory.newCase('Shadow ' + i, 'text');
            if (i < 150) {
                c.Type = Math.mod(i, 10) == 0 ? 'Other' : 'Electrical';
            } else {
                c.Type = Math.mod(i, 2) == 0 ? 'Electrical' : 'Mechanical';
            }
            cases.add(c);
        }
        insert cases;
        List<Gavel_Decision_Log__c> entries = new List<Gavel_Decision_Log__c>();
        for (Integer i = 0; i < 300; i++) {
            entries.add(i < 150 ? entry(cases[i], 'TECHNICAL', 0.95, 'AUTO') : entry(cases[i], 'TECHNICAL', 0.65, 'REVIEW'));
        }
        Gavel_Ledger.write(entries);
        Assert.areEqual(300, Gavel_BaselineCapture.capture(entries).size());

        Gavel_DisagreementReport.Report report = Gavel_DisagreementReport.build(DEF);
        Gavel_DisagreementReport.QuestionReport q = report.questions.get('category');
        Assert.areEqual(300, q.sampleSize);
        Assert.areEqual(300, q.compared);
        Assert.areEqual(210, q.agreed, '135 + 75');
        Assert.isTrue(q.agreementRate == 0.7, '' + String.valueOf(q.agreementRate));
        Assert.areEqual(75, q.unmapped, 'unmapped values count as disagreement');
        Assert.isTrue(q.unmappedValues.contains('Mechanical'));
        Assert.areEqual(150, q.wouldAuto, 'count that would have been AUTO');
        Assert.isTrue(q.wouldAutoShare == 0.5, '' + String.valueOf(q.wouldAutoShare));
        Assert.areEqual(10, q.bands.size(), '0.1 bins');
        Assert.areEqual(150, q.bands[9].n);
        Assert.isTrue(q.bands[9].rate == 0.9, '' + String.valueOf(q.bands[9].rate));
        Assert.areEqual(150, q.bands[6].n);
        Assert.isTrue(q.bands[6].rate == 0.5, '' + String.valueOf(q.bands[6].rate));
        Assert.isTrue(q.bands[0].n == 0, '' + String.valueOf(q.bands[0].n));
        Assert.areEqual('TECHNICAL', q.topDisagreements[0].gavel);
        Assert.areEqual('unmapped:Mechanical', q.topDisagreements[0].baseline);
        Assert.areEqual(75, q.topDisagreements[0].count);
        Assert.areEqual('BILLING', q.topDisagreements[1].baseline);
        Assert.areEqual(15, q.topDisagreements[1].count);
        Assert.isTrue(report.note.contains('not accuracy'));
        Assert.isTrue(Gavel_DisagreementReport.reportJson(DEF).contains('"agreed":210'));
    }

    // AS-7.2 Promotion blocked with 80 labeled entries
    @IsTest
    static void promotionBlocked() {
        Gavel_Definition d = Gavel_TestFactory.triage(DEF);
        Gavel_TestFactory.register(d);
        maps();
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 80; i++) {
            Case c = Gavel_TestFactory.newCase('Labeled ' + i, 'text');
            c.Type = 'Electrical';
            cases.add(c);
        }
        insert cases;
        List<Gavel_Decision_Log__c> entries = new List<Gavel_Decision_Log__c>();
        for (Case c : cases) {
            entries.add(entry(c, 'TECHNICAL', 0.9, 'AUTO'));
        }
        Gavel_Ledger.write(entries);
        Gavel_BaselineCapture.capture(entries);
        Assert.areEqual(80, Gavel_PromotionGate.countLabels(DEF, 1));

        Gavel_PromotionGate.Result r = Gavel_PromotionGate.canPromote(DEF);
        Assert.isFalse(r.allowed);
        Assert.areEqual('insufficient_calibration_sample', r.reason);
        Assert.areEqual(80, r.labeledCount);
    }

    @IsTest
    static void captureStatuses() {
        maps();
        Case missing = Gavel_TestFactory.newCase('m', 'x');
        Case unmapped = Gavel_TestFactory.newCase('u', 'x');
        unmapped.Type = 'Structural';
        Case circular = Gavel_TestFactory.newCase('c', 'x');
        circular.Type = 'Other';
        Case agree = Gavel_TestFactory.newCase('a', 'x');
        agree.Type = 'Other';
        insert new List<Case>{ missing, unmapped, circular, agree };
        List<Gavel_Decision_Log__c> entries = new List<Gavel_Decision_Log__c>{
            entry(missing, 'BILLING', 0.8, 'REVIEW'), entry(unmapped, 'BILLING', 0.8, 'REVIEW'),
            entry(circular, 'BILLING', 0.99, 'AUTO'), entry(agree, 'BILLING', 0.7, 'REVIEW')
        };
        Gavel_Ledger.write(entries);
        // Gavel itself set Case.Type on the circular record (Live split)
        Gavel_Ledger.insertActionLogs(new List<Gavel_Action_Log__c>{
            new Gavel_Action_Log__c(Decision_Log__c = entries[2].Id, Record_Id__c = String.valueOf(circular.Id), Action_Type__c = 'set_field', Target__c = 'Case.Type', Value__c = 'Other', Status__c = 'applied')
        });
        Map<Id, Gavel_Baseline__c> byEntry = new Map<Id, Gavel_Baseline__c>();
        for (Gavel_Baseline__c b : Gavel_BaselineCapture.capture(entries)) {
            byEntry.put(b.Decision_Log__c, b);
        }
        Assert.areEqual('baseline_missing', byEntry.get(entries[0].Id).Status__c);
        Assert.areEqual('baseline_unmapped', byEntry.get(entries[1].Id).Status__c);
        Assert.isFalse(byEntry.get(entries[1].Id).Agrees__c);
        Assert.areEqual('circular', byEntry.get(entries[2].Id).Status__c);
        Assert.areEqual('captured', byEntry.get(entries[3].Id).Status__c);
        Assert.isTrue(byEntry.get(entries[3].Id).Agrees__c);
        Gavel_DisagreementReport.QuestionReport q = Gavel_DisagreementReport.build(DEF, 1).questions.get('category');
        Assert.areEqual(1, q.missing);
        Assert.areEqual(1, q.circular);
        Assert.areEqual(2, q.compared, 'missing and circular are excluded from agreement');
    }

    @IsTest
    static void scheduledCaptureAfterDelay() {
        maps();
        Case c = Gavel_TestFactory.newCase('late', 'x');
        c.Type = 'Electrical';
        insert c;
        Gavel_Decision_Log__c e = entry(c, 'TECHNICAL', 0.9, 'AUTO');
        Gavel_Ledger.write(new List<Gavel_Decision_Log__c>{ e });
        Test.startTest();
        Database.executeBatch(new Gavel_BaselineCapture(0), 200);
        Test.stopTest();
        Assert.areEqual(1, [SELECT COUNT() FROM Gavel_Baseline__c WHERE Decision_Log__c = :e.Id AND Agrees__c = true]);
        // Already captured entries are not picked again.
        Assert.isFalse(new Gavel_BaselineCapture(0).start(null).iterator().hasNext());
        System.schedule('Gavel baseline test', '0 0 2 * * ?', new Gavel_BaselineCapture());
    }

    @IsTest
    static void gateReasons() {
        Assert.areEqual('definition_not_found', Gavel_PromotionGate.canPromote('Nope').reason);
        Gavel_Definition alias = Gavel_TestFactory.triage('Alias_Def');
        alias.model = 'jev-latest';
        Gavel_TestFactory.register(alias);
        Assert.areEqual('model_alias_not_allowed_live', Gavel_PromotionGate.canPromote('Alias_Def').reason);
        Gavel_Definition stale = Gavel_TestFactory.triage('Stale_Def');
        Gavel_TestFactory.register(stale);
        stale.version = 9; // hash no longer matches
        Assert.areEqual('definition_hash_mismatch', Gavel_PromotionGate.canPromote('Stale_Def').reason);
        Gavel_TestFactory.register(Gavel_TestFactory.triage('Empty_Def'));
        Assert.areEqual('insufficient_calibration_sample', Gavel_PromotionGate.canPromote('Empty_Def').reason);
    }
}
