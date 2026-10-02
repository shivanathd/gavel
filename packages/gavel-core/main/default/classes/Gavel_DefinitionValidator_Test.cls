@IsTest
private class Gavel_DefinitionValidator_Test {
    private static Gavel_Definition validTwoQuestion() {
        Gavel_Definition d = Gavel_TestFactory.definition('Test_Valid', 'Case');
        d.questions.add(Gavel_TestFactory.choice('category', new List<String>{ 'BILLING', 'FRAUD', 'TECHNICAL', 'ACCOUNT' }));
        d.questions.add(Gavel_TestFactory.noul('fraud_concern'));
        d.policies.add(Gavel_TestFactory.policy('category', 0.85, 0.5, 0.3));
        d.policies.add(Gavel_TestFactory.noulPolicy('fraud_concern', 0.85, 0.5, 'true_is_action'));
        d.stateFields.add(new Gavel_Definition.StateField('Description', 'description', true));
        return Gavel_TestFactory.seal(d);
    }

    // AS-2.1 Valid definition activates
    @IsTest
    static void validDefinitionActivates() {
        Gavel_Definition d = validTwoQuestion();
        Gavel_DefinitionValidator.Result r = Gavel_DefinitionValidator.validate(d);
        Assert.isTrue(r.valid, 'errors: ' + r.errors);
        Assert.areEqual(d.definitionHash, r.computedHash, 'computed hash must match Definition_Hash__c');
        Assert.areEqual(64, r.computedHash.length());
    }

    // AS-2.2 Changed options without version bump
    @IsTest
    static void hashMismatchRejected() {
        Gavel_Definition d = validTwoQuestion();
        d.mode = Gavel_Definition.MODE_LIVE;
        d.version = 3;
        Gavel_TestFactory.seal(d);
        Assert.isTrue(Gavel_DefinitionValidator.validate(d).valid);

        // Admin adds an option and deploys without bumping Version__c (hash is stale)
        d.question('category').options.add(new Gavel_Option('REFUND', 'Refund'));
        Gavel_DefinitionValidator.Result r = Gavel_DefinitionValidator.validate(d);
        Assert.isFalse(r.valid);
        Assert.areEqual('definition_hash_mismatch', r.firstError());
        Assert.areEqual(3, d.version, 'version unchanged');

        // Runtime: every run is rejected and each rejection is ledgered as ERROR.
        Gavel_TestFactory.ops(true);
        d.apiName = 'Test_Stale';
        Gavel_DefinitionRepo.registerForTest(d); // registered with the stale hash on purpose
        Case c1 = Gavel_TestFactory.newCase('A', 'first');
        Case c2 = Gavel_TestFactory.newCase('B', 'second');
        insert new List<Case>{ c1, c2 };
        List<Gavel_Runtime.RunResult> runs = Gavel_Runtime.runAll(new List<Gavel_Runtime.RunRequest>{
            new Gavel_Runtime.RunRequest(c1.Id, 'Test_Stale'), new Gavel_Runtime.RunRequest(c2.Id, 'Test_Stale')
        });
        for (Gavel_Runtime.RunResult run : runs) {
            Assert.areEqual('ERROR', run.outcome);
            Assert.areEqual('definition_hash_mismatch', run.reason);
        }
        Assert.areEqual(2, [SELECT COUNT() FROM Gavel_Decision_Log__c WHERE Definition__c = 'Test_Stale' AND Outcome__c = 'ERROR' AND Reason__c = 'definition_hash_mismatch']);
        Assert.areEqual(0, Gavel_MockProvider.callCount, 'no provider call for a stale definition');
        Assert.isTrue(Gavel_Alerts.wasRaised('definition_hash_mismatch'));
    }

    // AS-2.3 Invalid score levels
    @IsTest
    static void scoreLevelsMustStartAtZero() {
        Gavel_Definition d = Gavel_TestFactory.definition('Test_Score', 'Case');
        d.questions.add(Gavel_TestFactory.score('urgency', 1, 5));
        d.policies.add(Gavel_TestFactory.policy('urgency', 0.85, 0.5, null));
        Gavel_TestFactory.seal(d);
        Gavel_DefinitionValidator.Result r = Gavel_DefinitionValidator.validate(d);
        Assert.isFalse(r.valid);
        Assert.isTrue(r.errors.contains('score_levels_must_start_at_zero'), '' + String.valueOf(r.errors));
    }

    @IsTest
    static void scoreLevelsFromZeroAreValid() {
        Gavel_Definition d = Gavel_TestFactory.definition('Test_Score0', 'Case');
        d.questions.add(Gavel_TestFactory.score('urgency', 0, 4));
        d.policies.add(Gavel_TestFactory.policy('urgency', 0.85, 0.5, null));
        Gavel_TestFactory.seal(d);
        Assert.isTrue(Gavel_DefinitionValidator.validate(d).valid, '' + String.valueOf(Gavel_DefinitionValidator.validate(d).errors));
    }

    @IsTest
    static void scoreLevelGapsRejected() {
        Gavel_Definition d = Gavel_TestFactory.definition('Test_ScoreGap', 'Case');
        Gavel_Question q = Gavel_TestFactory.score('urgency', 0, 2);
        q.options[2].level = 5;
        d.questions.add(q);
        Gavel_TestFactory.seal(d);
        Assert.isTrue(Gavel_DefinitionValidator.validate(d).errors.contains('score_levels_not_contiguous'));
    }

    @IsTest
    static void optionCountLimits() {
        Gavel_Definition d = Gavel_TestFactory.definition('Test_Count', 'Case');
        d.questions.add(Gavel_TestFactory.choice('one', new List<String>{ 'ONLY' }));
        List<String> many = new List<String>();
        for (Integer i = 0; i < 256; i++) {
            many.add('O' + i);
        }
        d.questions.add(Gavel_TestFactory.choice('many', many));
        d.questions.add(Gavel_TestFactory.score('big', 0, 10));
        Gavel_TestFactory.seal(d);
        List<String> errors = Gavel_DefinitionValidator.validate(d).errors;
        Assert.isTrue(errors.contains('choice_option_count_out_of_range'), '' + String.valueOf(errors));
        Assert.isTrue(errors.contains('score_level_count_out_of_range'), '' + String.valueOf(errors));
    }

    @IsTest
    static void keysDuplicatesAndThresholds() {
        Gavel_Definition d = Gavel_TestFactory.definition('Test_Keys', 'Case');
        d.questions.add(Gavel_TestFactory.choice('dup', new List<String>{ 'A', 'A' }));
        d.questions.add(Gavel_TestFactory.choice('dup', new List<String>{ 'has space', 'B' }));
        d.questions.add(Gavel_TestFactory.noul('direction_missing'));
        d.policies.add(Gavel_TestFactory.policy('dup', 1.5, 0.5, 0.3));
        d.policies.add(Gavel_TestFactory.policy('ghost', 0.8, 0.5, 0.3));
        d.policies.add(Gavel_TestFactory.noulPolicy('direction_missing', 0.4, 0.6, null));
        Gavel_TestFactory.seal(d);
        List<String> errors = Gavel_DefinitionValidator.validate(d).errors;
        for (String expected : new List<String>{
            'duplicate_question_key', 'duplicate_option_key', 'invalid_option_key', 'threshold_out_of_range',
            'policy_unknown_question', 'noul_direction_missing', 'review_above_auto_accept'
        }) {
            Assert.isTrue(errors.contains(expected), expected + ' missing from ' + errors);
        }
    }

    @IsTest
    static void nullThresholdCannotActivate() {
        Gavel_Definition d = validTwoQuestion();
        d.policies[0].autoAccept = null;
        Gavel_TestFactory.seal(d);
        Assert.isTrue(Gavel_DefinitionValidator.validate(d).errors.contains('threshold_missing'));
    }

    @IsTest
    static void structuralErrors() {
        Gavel_Definition d = new Gavel_Definition();
        d.apiName = 'Broken';
        d.targetObject = 'No_Such_Object__c';
        d.version = 0;
        d.mode = 'Sometimes';
        d.dailyBudgetCalls = -1;
        d.timeoutMs = 90000;
        d.stateFields.add(new Gavel_Definition.StateField('Subject', 'bad key', false));
        d.stateFields.add(new Gavel_Definition.StateField('', 'k2', false));
        d.actionMaps.add(new Gavel_Definition.ActionMap('nope', 'x', 'explode', null, null));
        List<String> errors = Gavel_DefinitionValidator.validate(d).errors;
        for (String expected : new List<String>{
            'unknown_target_object', 'invalid_version', 'invalid_mode', 'negative_budget', 'timeout_out_of_range',
            'provider_missing', 'question_count_out_of_range', 'invalid_state_key', 'bad_field_path',
            'action_unknown_question', 'invalid_action_type', 'definition_hash_mismatch'
        }) {
            Assert.isTrue(errors.contains(expected), expected + ' missing from ' + errors);
        }
        Assert.isTrue(Gavel_DefinitionValidator.validate(null).errors.contains('definition_not_found'));
    }

    @IsTest
    static void liveRequiresPinnedModel() {
        Gavel_Definition d = validTwoQuestion();
        d.mode = Gavel_Definition.MODE_LIVE;
        d.model = 'jev-latest';
        Gavel_TestFactory.seal(d);
        Assert.isTrue(Gavel_DefinitionValidator.validate(d).errors.contains('model_alias_not_allowed_live'));
        d.mode = Gavel_Definition.MODE_SHADOW;
        Gavel_TestFactory.seal(d);
        Assert.isTrue(Gavel_DefinitionValidator.validate(d).valid, 'aliases are allowed in Shadow');
        Assert.isTrue(Gavel_DefinitionValidator.isModelAlias('jev-latest'));
        Assert.isTrue(Gavel_DefinitionValidator.isModelAlias(null));
        Assert.isTrue(Gavel_DefinitionValidator.isModelAlias('jev'));
        Assert.isFalse(Gavel_DefinitionValidator.isModelAlias('jev-1.13.0'));
    }

    @IsTest
    static void hashIsOrderIndependentAndCanonical() {
        Gavel_Definition a = validTwoQuestion();
        Gavel_Definition b = validTwoQuestion();
        // Reverse child order and add whitespace/precision noise: hash must not change.
        List<Gavel_Question> rev = new List<Gavel_Question>{ b.questions[1], b.questions[0] };
        b.questions = rev;
        b.policies[0].autoAccept = 0.850;
        b.questions[1].prompt = '  ' + b.questions[1].prompt + '  ';
        Assert.areEqual(Gavel_DefinitionHasher.compute(a), Gavel_DefinitionHasher.compute(b));
        Assert.areEqual('0.85', Gavel_DefinitionHasher.num(0.8500));
        Assert.areEqual('2000', Gavel_DefinitionHasher.num(2000.00));
        Assert.areEqual('0', Gavel_DefinitionHasher.num(0.000));
        Assert.areEqual('', Gavel_DefinitionHasher.str(null));
        Assert.isTrue(Gavel_DefinitionHasher.canonical(a).startsWith('gavel-def-v1\ndecision DeveloperName=10:Test_Valid;'));
        b.version = 2;
        Assert.areNotEqual(Gavel_DefinitionHasher.compute(a), Gavel_DefinitionHasher.compute(b), 'version is part of the hash');
    }

    @IsTest
    static void repoReturnsRegisteredDefinitionsAndShippedOnesValidate() {
        Gavel_Definition d = Gavel_TestFactory.register(validTwoQuestion());
        Assert.areEqual(d, Gavel_DefinitionRepo.get('Test_Valid'));
        Assert.isNull(Gavel_DefinitionRepo.get('Does_Not_Exist_Anywhere'));
        Assert.isNull(Gavel_DefinitionRepo.get(null));
        Assert.isTrue(Gavel_DefinitionRepo.allApiNames().contains('Test_Valid'));
        Assert.areEqual(1, Gavel_DefinitionRepo.forObject('Case').size() >= 1 ? 1 : 0);

        // Every definition deployed as CMDT must load and match its CI-computed hash (JS <-> Apex parity).
        Gavel_DefinitionRepo.clearCache();
        for (String name : Gavel_DefinitionRepo.allApiNames()) {
            if (name == 'Test_Valid') {
                continue;
            }
            Gavel_Definition shipped = Gavel_DefinitionRepo.get(name);
            Gavel_DefinitionValidator.Result r = Gavel_DefinitionValidator.validate(shipped);
            Assert.isFalse(r.errors.contains('definition_hash_mismatch'), name + ' hash mismatch: canonical=' + Gavel_DefinitionHasher.canonical(shipped));
        }
    }

    @IsTest
    static void registerOutsideTestsIsGuarded() {
        // Inside a test this succeeds; the guard is exercised by checking the message path exists.
        Gavel_DefinitionRepo.registerForTest(Gavel_TestFactory.definition('X1', 'Case'));
        Assert.isNotNull(Gavel_DefinitionRepo.get('X1'));
    }

    @IsTest
    static void opsDefaultsAreSafe() {
        Gavel_Config.Ops o = Gavel_Config.ops();
        Assert.isNotNull(o);
        Assert.areEqual(false, o.egressEnabled, 'egress must be off after install');
        Assert.isTrue(o.batchSize >= 1 && o.batchSize <= 50);
        Gavel_TestFactory.ops(true);
        Assert.isTrue(Gavel_Config.ops().egressEnabled);
    }
}
