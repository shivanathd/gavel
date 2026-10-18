@IsTest
private class Gavel_PolicyEngine_Test {
    private static Gavel_Definition oneChoice(Decimal autoAccept, Decimal reviewAt, Decimal minMargin, List<String> options) {
        Gavel_Definition d = Gavel_TestFactory.definition('Policy_Test', 'Case');
        d.mode = Gavel_Definition.MODE_LIVE;
        d.questions.add(Gavel_TestFactory.choice('category', options));
        d.policies.add(Gavel_TestFactory.policy('category', autoAccept, reviewAt, minMargin));
        return d;
    }

    private static Gavel_JudgmentResponse choiceResp(Map<String, Decimal> probs, String winner, Decimal confidence) {
        Gavel_JudgmentResponse r = new Gavel_JudgmentResponse();
        r.status = 'ok';
        Gavel_Answer a = new Gavel_Answer();
        a.key = 'category';
        a.answerType = 'choice';
        a.choice = winner;
        a.probabilities = probs;
        a.confidence = confidence;
        r.answers = new Map<String, Gavel_Answer>{ 'category' => a };
        return r;
    }

    private static Gavel_Answer noulAnswer(String key, Decimal p) {
        Gavel_Answer a = new Gavel_Answer();
        a.key = key;
        a.answerType = 'noul';
        a.probability = p;
        return a;
    }

    private static Gavel_Answer scoreAnswer(String key, Decimal s, Decimal c) {
        Gavel_Answer a = new Gavel_Answer();
        a.key = key;
        a.answerType = 'score';
        a.score = s;
        a.confidence = c;
        return a;
    }

    private static Gavel_JudgmentResponse ok(Map<String, Gavel_Answer> answers) {
        Gavel_JudgmentResponse r = new Gavel_JudgmentResponse();
        r.status = 'ok';
        r.answers = answers;
        return r;
    }

    private static final List<String> FOUR = new List<String>{ 'BILLING', 'FRAUD', 'TECHNICAL', 'ACCOUNT' };

    // AS-5.1 Margin blocks auto
    @IsTest
    static void marginBlocksAuto() {
        Gavel_Outcome o = Gavel_PolicyEngine.evaluate(oneChoice(0.5, 0.5, 0.3, FOUR),
            choiceResp(new Map<String, Decimal>{ 'BILLING' => 0.52, 'FRAUD' => 0.46, 'TECHNICAL' => 0.01, 'ACCOUNT' => 0.01 }, 'BILLING', 0.6));
        Assert.areEqual('REVIEW', o.outcome);
        Assert.areEqual('margin_below_min', o.reason);
    }

    // AS-5.2 Escape option
    @IsTest
    static void escapeOption() {
        List<String> opts = new List<String>{ 'BILLING', 'FRAUD', 'manual_review' };
        Gavel_Definition d = oneChoice(0.85, 0.5, 0.3, opts);
        d.question('category').findOption('manual_review').isEscape = true;
        Gavel_Outcome o = Gavel_PolicyEngine.evaluate(d,
            choiceResp(new Map<String, Decimal>{ 'BILLING' => 0.05, 'FRAUD' => 0.05, 'manual_review' => 0.9 }, 'manual_review', 0.9));
        Assert.areEqual('REVIEW', o.outcome);
        Assert.areEqual('escape_selected', o.reason);
    }

    // AS-5.3 Shadow never acts
    @IsTest
    static void shadowNeverActs() {
        Gavel_Definition d = oneChoice(0.85, 0.5, 0.3, FOUR);
        d.mode = Gavel_Definition.MODE_SHADOW;
        Gavel_Outcome o = Gavel_PolicyEngine.evaluate(d,
            choiceResp(new Map<String, Decimal>{ 'BILLING' => 0.94, 'FRAUD' => 0.02, 'TECHNICAL' => 0.02, 'ACCOUNT' => 0.02 }, 'BILLING', 0.9));
        Assert.areEqual('AUTO', o.outcome, 'outcome is still computed in shadow');
        Assert.isTrue(o.actionSuppressed);
        Assert.areEqual('action_suppressed_shadow', o.suppressReason);

        // End to end: Apply Outcome on a Shadow AUTO entry changes nothing.
        Gavel_TestFactory.ops(true);
        Gavel_Definition live = Gavel_TestFactory.triage('Shadow_Acts');
        live.actionMaps.add(new Gavel_Definition.ActionMap('category', 'BILLING', 'set_field', 'Case.Subject', 'ROUTED TO BILLING'));
        Gavel_TestFactory.register(live); // factory default mode is Shadow
        Gavel_MockProvider.respondWith('Shadow_Acts', new Gavel_MockProvider.Body()
            .choice('category', new Map<String, Decimal>{ 'BILLING' => 0.95, 'FRAUD' => 0.02, 'TECHNICAL' => 0.02, 'ACCOUNT' => 0.01 }, 0.9)
            .noul('fraud_concern', 0.02).json());
        Case c = Gavel_TestFactory.newCase('Original subject', 'Charged twice for my plan');
        insert c;
        Gavel_Runtime.RunRequest req = new Gavel_Runtime.RunRequest(c.Id, 'Shadow_Acts');
        req.applyActions = false;
        Gavel_Runtime.RunResult run = Gavel_Runtime.run(req);
        Assert.areEqual('AUTO', run.outcome);
        List<Gavel_Runtime.ApplyResult> applied = Gavel_Runtime.applyOutcome(new List<Id>{ run.ledgerId });
        Assert.isFalse(applied[0].applied);
        Assert.areEqual('action_suppressed_shadow', applied[0].actions);
        Assert.areEqual('Original subject', [SELECT Subject FROM Case WHERE Id = :c.Id].Subject, 'zero field updates');
        Gavel_Decision_Log__c e = [SELECT Action_Taken__c, Action_Suppressed__c FROM Gavel_Decision_Log__c WHERE Id = :run.ledgerId];
        Assert.areEqual('action_suppressed_shadow', e.Action_Taken__c);
        Assert.isTrue(e.Action_Suppressed__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Gavel_Review__c], 'shadow creates no work items');
    }

    // AS-5.4 Conservative combination
    @IsTest
    static void conservativeCombination() {
        Gavel_Definition d = Gavel_TestFactory.definition('Combo', 'Case');
        d.questions.add(Gavel_TestFactory.noul('q1'));
        d.questions.add(Gavel_TestFactory.noul('q2'));
        d.policies.add(Gavel_TestFactory.noulPolicy('q1', 0.85, 0.5, 'true_is_action'));
        d.policies.add(Gavel_TestFactory.noulPolicy('q2', 0.85, 0.5, 'true_is_action'));
        Gavel_Outcome o = Gavel_PolicyEngine.evaluate(d, ok(new Map<String, Gavel_Answer>{
            'q1' => noulAnswer('q1', 0.95), // AUTO
            'q2' => noulAnswer('q2', 0.3)   // ESCALATE: below review, not confidently false
        }));
        Assert.areEqual('AUTO:accepted', o.perQuestion.get('q1'));
        Assert.areEqual('ESCALATE:confidence_below_review', o.perQuestion.get('q2'));
        Assert.areEqual('ESCALATE', o.outcome);
        Assert.areEqual('q2', o.decidingQuestion);
    }

    @IsTest
    static void choiceTruthTable() {
        Gavel_Definition d = oneChoice(0.85, 0.5, 0.3, FOUR);
        // AUTO when top >= auto and margin >= min
        Gavel_Outcome auto = Gavel_PolicyEngine.evaluate(d, choiceResp(new Map<String, Decimal>{ 'BILLING' => 0.85, 'FRAUD' => 0.05, 'TECHNICAL' => 0.05, 'ACCOUNT' => 0.05 }, 'BILLING', 0.8));
        Assert.areEqual('AUTO', auto.outcome, 'probability exactly equal to auto_accept is AUTO');
        Assert.areEqual('accepted', auto.reason);
        Assert.areEqual('BILLING', auto.questions.get('category').answerValue);
        Assert.isFalse(auto.actionSuppressed, 'Live acts');
        // REVIEW band
        Gavel_Outcome band = Gavel_PolicyEngine.evaluate(d, choiceResp(new Map<String, Decimal>{ 'BILLING' => 0.7, 'FRAUD' => 0.1, 'TECHNICAL' => 0.1, 'ACCOUNT' => 0.1 }, 'BILLING', 0.8));
        Assert.areEqual('REVIEW', band.outcome);
        Assert.areEqual('confidence_below_auto_accept', band.reason);
        // ESCALATE below review_at
        Gavel_Outcome low = Gavel_PolicyEngine.evaluate(d, choiceResp(new Map<String, Decimal>{ 'BILLING' => 0.4, 'FRAUD' => 0.2, 'TECHNICAL' => 0.2, 'ACCOUNT' => 0.2 }, 'BILLING', 0.3));
        Assert.areEqual('ESCALATE', low.outcome);
        Assert.areEqual('confidence_below_review', low.reason);
        // Null confidence never AUTO
        Gavel_Outcome nullConf = Gavel_PolicyEngine.evaluate(d, choiceResp(new Map<String, Decimal>{ 'BILLING' => 0.97, 'FRAUD' => 0.01, 'TECHNICAL' => 0.01, 'ACCOUNT' => 0.01 }, 'BILLING', null));
        Assert.areEqual('REVIEW', nullConf.outcome);
        Assert.areEqual('unknown_confidence', nullConf.reason);
        // Winner missing from distribution
        Gavel_Outcome broken = Gavel_PolicyEngine.evaluate(d, choiceResp(new Map<String, Decimal>{ 'FRAUD' => 1 }, 'BILLING', 0.9));
        Assert.areEqual('ERROR', broken.outcome);
    }

    @IsTest
    static void twoOptionTieNeverAuto() {
        Gavel_Definition high = oneChoice(0.5, 0.6, 0, new List<String>{ 'YES', 'NO' });
        Gavel_Outcome esc = Gavel_PolicyEngine.evaluate(high, choiceResp(new Map<String, Decimal>{ 'YES' => 0.5, 'NO' => 0.5 }, 'YES', 0.1));
        Assert.areEqual('ESCALATE', esc.outcome, 'review_at > 0.5');
        Gavel_Definition lowReview = oneChoice(0.5, 0.5, 0, new List<String>{ 'YES', 'NO' });
        Gavel_Outcome rev = Gavel_PolicyEngine.evaluate(lowReview, choiceResp(new Map<String, Decimal>{ 'YES' => 0.5, 'NO' => 0.5 }, 'YES', 0.1));
        Assert.areEqual('REVIEW', rev.outcome, 'tie with review_at <= 0.5 is REVIEW, never AUTO');
        Assert.areEqual('margin_below_min', rev.reason);
    }

    @IsTest
    static void scoreTruthTable() {
        Gavel_Definition d = Gavel_TestFactory.definition('Score', 'Case');
        d.questions.add(Gavel_TestFactory.score('urgency', 0, 4));
        d.policies.add(Gavel_TestFactory.policy('urgency', 0.8, 0.5, null));
        Gavel_Outcome auto = Gavel_PolicyEngine.evaluate(d, ok(new Map<String, Gavel_Answer>{ 'urgency' => scoreAnswer('urgency', 3.40, 0.9) }));
        Assert.areEqual('AUTO', auto.outcome);
        Assert.areEqual('3.4', auto.questions.get('urgency').answerValue, 'score passes through unchanged');
        Assert.areEqual('REVIEW', Gavel_PolicyEngine.evaluate(d, ok(new Map<String, Gavel_Answer>{ 'urgency' => scoreAnswer('urgency', 1, 0.6) })).outcome);
        Assert.areEqual('ESCALATE', Gavel_PolicyEngine.evaluate(d, ok(new Map<String, Gavel_Answer>{ 'urgency' => scoreAnswer('urgency', 1, 0.2) })).outcome);
        Gavel_Outcome nullConf = Gavel_PolicyEngine.evaluate(d, ok(new Map<String, Gavel_Answer>{ 'urgency' => scoreAnswer('urgency', 4, null) }));
        Assert.areEqual('REVIEW', nullConf.outcome);
        Assert.areEqual('unknown_confidence', nullConf.reason);
    }

    @IsTest
    static void noulTruthTable() {
        Gavel_Definition d = Gavel_TestFactory.definition('Noul', 'Case');
        d.questions.add(Gavel_TestFactory.noul('instructions'));
        // Input Screen shape: block at 0.75, review at 0.25
        d.policies.add(Gavel_TestFactory.noulPolicy('instructions', 0.75, 0.25, 'true_is_action'));
        Gavel_Outcome block = Gavel_PolicyEngine.evaluate(d, ok(new Map<String, Gavel_Answer>{ 'instructions' => noulAnswer('instructions', 0.9) }));
        Assert.areEqual('AUTO', block.outcome);
        Assert.areEqual('true', block.questions.get('instructions').answerValue);
        Gavel_Outcome review = Gavel_PolicyEngine.evaluate(d, ok(new Map<String, Gavel_Answer>{ 'instructions' => noulAnswer('instructions', 0.5) }));
        Assert.areEqual('REVIEW', review.outcome);
        Gavel_Outcome pass = Gavel_PolicyEngine.evaluate(d, ok(new Map<String, Gavel_Answer>{ 'instructions' => noulAnswer('instructions', 0.1) }));
        Assert.areEqual('AUTO', pass.outcome);
        Assert.areEqual('accepted_no_action', pass.reason);
        Assert.areEqual('false', pass.questions.get('instructions').answerValue);

        // false_is_action flips the action side
        d.policies[0].noulDirection = 'false_is_action';
        Gavel_Outcome act = Gavel_PolicyEngine.evaluate(d, ok(new Map<String, Gavel_Answer>{ 'instructions' => noulAnswer('instructions', 0.1) }));
        Assert.areEqual('AUTO', act.outcome);
        Assert.areEqual('accepted', act.reason);
        Assert.areEqual('false', act.questions.get('instructions').answerValue);
        Assert.areEqual(0.9, act.questions.get('instructions').calibrationValue);
    }

    @IsTest
    static void asymmetricOptOutPolicy() {
        Gavel_Definition d = Gavel_TestFactory.definition('OptOut', 'EmailMessage');
        d.mode = Gavel_Definition.MODE_LIVE;
        d.questions.add(Gavel_TestFactory.noul('asks_not_to_be_contacted'));
        Gavel_Definition.Policy p = Gavel_TestFactory.noulPolicy('asks_not_to_be_contacted', 0.6, 0.15, 'true_is_action');
        p.asymmetricReason = 'False positive costs one email; false negative is a compliance breach.';
        d.policies.add(p);
        Gavel_Outcome apply = Gavel_PolicyEngine.evaluate(d, ok(new Map<String, Gavel_Answer>{ 'asks_not_to_be_contacted' => noulAnswer('asks_not_to_be_contacted', 0.62) }));
        Assert.areEqual('AUTO', apply.outcome);
        Assert.isTrue(apply.asymmetricReason.contains('compliance breach'));
        Gavel_Outcome unsure = Gavel_PolicyEngine.evaluate(d, ok(new Map<String, Gavel_Answer>{ 'asks_not_to_be_contacted' => noulAnswer('asks_not_to_be_contacted', 0.3) }));
        Assert.areEqual('REVIEW', unsure.outcome, 'uncertain opt-out goes to a human, never ignored');
        Gavel_Outcome clear = Gavel_PolicyEngine.evaluate(d, ok(new Map<String, Gavel_Answer>{ 'asks_not_to_be_contacted' => noulAnswer('asks_not_to_be_contacted', 0.05) }));
        Assert.areEqual('accepted_no_action', clear.reason);
        // Live with auto-apply off (Live-Review)
        d.autoApply = false;
        Gavel_Outcome lr = Gavel_PolicyEngine.evaluate(d, ok(new Map<String, Gavel_Answer>{ 'asks_not_to_be_contacted' => noulAnswer('asks_not_to_be_contacted', 0.9) }));
        Assert.isTrue(lr.actionSuppressed);
        Assert.areEqual('auto_apply_disabled', lr.suppressReason);
    }

    @IsTest
    static void failClosed() {
        Gavel_Definition d = oneChoice(0.85, 0.5, 0.3, FOUR);
        for (String status : new List<String>{ 'timeout', 'http_error', 'invalid_response', 'contract_mismatch', 'circuit_open', 'budget_exceeded', 'invalid_request' }) {
            Gavel_Outcome o = Gavel_PolicyEngine.evaluate(d, Gavel_JudgmentResponse.failure(status, 500, null));
            Assert.areEqual('ERROR', o.outcome, '' + status);
            Assert.areEqual(status, o.reason);
        }
        Assert.areEqual('ERROR', Gavel_PolicyEngine.evaluate(d, null).outcome);
        // Invalid single answer
        Gavel_JudgmentResponse inv = ok(new Map<String, Gavel_Answer>{ 'category' => Gavel_Answer.invalid('category', 'choice') });
        Assert.areEqual('invalid_response', Gavel_PolicyEngine.evaluate(d, inv).reason);
        // Missing policy for a required question
        d.policies.clear();
        Gavel_Outcome missing = Gavel_PolicyEngine.evaluate(d, choiceResp(new Map<String, Decimal>{ 'BILLING' => 0.97, 'FRAUD' => 0.01, 'TECHNICAL' => 0.01, 'ACCOUNT' => 0.01 }, 'BILLING', 0.9));
        Assert.areEqual('ERROR', missing.outcome);
        Assert.areEqual('policy_missing', missing.reason);
        // Spec signature with explicit policies
        Gavel_Outcome viaList = Gavel_PolicyEngine.evaluate(d,
            choiceResp(new Map<String, Decimal>{ 'BILLING' => 0.97, 'FRAUD' => 0.01, 'TECHNICAL' => 0.01, 'ACCOUNT' => 0.01 }, 'BILLING', 0.9),
            new List<Gavel_Definition.Policy>{ Gavel_TestFactory.policy('category', 0.85, 0.5, 0.3) });
        Assert.areEqual('AUTO', viaList.outcome);
        Gavel_Definition empty = Gavel_TestFactory.definition('Empty', 'Case');
        Assert.areEqual('no_questions', Gavel_PolicyEngine.evaluate(empty, ok(new Map<String, Gavel_Answer>())).reason);
    }

    @IsTest
    static void requiredQuestionsOnlyAndModes() {
        Gavel_Definition d = Gavel_TestFactory.definition('Req', 'Case');
        d.questions.add(Gavel_TestFactory.noul('decides'));
        Gavel_Question info = Gavel_TestFactory.noul('informational');
        info.requiredForAction = false;
        d.questions.add(info);
        d.policies.add(Gavel_TestFactory.noulPolicy('decides', 0.85, 0.5, 'true_is_action'));
        // 'informational' has no policy: ERROR for that question only, not the definition.
        Gavel_JudgmentResponse r = ok(new Map<String, Gavel_Answer>{ 'decides' => noulAnswer('decides', 0.95), 'informational' => noulAnswer('informational', 0.5) });
        Gavel_Outcome o = Gavel_PolicyEngine.evaluate(d, r);
        Assert.areEqual('AUTO', o.outcome);
        Assert.areEqual('ERROR:policy_missing', o.perQuestion.get('informational'));
        Assert.isTrue(o.actionSuppressed, 'factory default mode is Shadow');
        d.mode = Gavel_Definition.MODE_DRAFT;
        Assert.areEqual('action_suppressed_draft', Gavel_PolicyEngine.evaluate(d, r).suppressReason);
        d.mode = Gavel_Definition.MODE_LIVE;
        Assert.isFalse(Gavel_PolicyEngine.evaluate(d, r).actionSuppressed);
        Assert.areEqual('ERROR', Gavel_Outcome.moreConservative('AUTO', 'ERROR'));
        Assert.areEqual('SKIP', Gavel_Outcome.moreConservative('SKIP', 'REVIEW'));
        Assert.areEqual('REVIEW', Gavel_Outcome.moreConservative(null, 'REVIEW'));
        Assert.areEqual('REVIEW', Gavel_Outcome.moreConservative('REVIEW', null));
        Assert.isTrue(Gavel_Outcome.create('ESCALATE', 'x').needsReview());
    }

    /** Property-style: for random distributions AUTO only ever happens when every rule allows it. */
    @IsTest
    static void randomDistributionsRespectRules() {
        Gavel_Definition d = oneChoice(0.8, 0.4, 0.25, FOUR);
        Long seed = 42;
        for (Integer i = 0; i < 300; i++) {
            List<Decimal> w = new List<Decimal>();
            Decimal total = 0;
            for (Integer j = 0; j < 4; j++) {
                seed = Math.mod(seed * 1103515245L + 12345L, 2147483648L);
                Decimal x = Decimal.valueOf(Math.mod(seed, 1000L) + 1);
                w.add(x);
                total += x;
            }
            Map<String, Decimal> probs = new Map<String, Decimal>();
            String best = null;
            Decimal bestP = -1;
            for (Integer j = 0; j < 4; j++) {
                Decimal p = (w[j] / total).setScale(6);
                probs.put(FOUR[j], p);
                if (p > bestP) {
                    bestP = p;
                    best = FOUR[j];
                }
            }
            Decimal conf = Math.mod(seed, 3L) == 0 ? null : 0.5;
            Gavel_Outcome o = Gavel_PolicyEngine.evaluate(d, choiceResp(probs, best, conf));
            Gavel_Outcome.QuestionResult qr = o.questions.get('category');
            if (o.outcome == 'AUTO') {
                Assert.isTrue(bestP >= 0.8 && qr.margin >= 0.25 && conf != null, 'AUTO broke a rule at i=' + i);
            }
            if (bestP < 0.4 && conf != null) {
                Assert.areEqual('ESCALATE', o.outcome);
            }
            if (conf == null) {
                Assert.areNotEqual('AUTO', o.outcome, 'null confidence is never AUTO');
            }
            Assert.areEqual(best, qr.answerValue, 'never picks the runner-up');
        }
    }

    // Box (Jev 1.14): banded on confidence, answer recorded as top,bottom,left,right
    @IsTest
    static void boxBandsOnConfidence() {
        Gavel_Question q = Gavel_TestFactory.box('damage_area');
        Gavel_Definition.Policy p = Gavel_TestFactory.policy('damage_area', 0.8, 0.5, null);
        Map<Decimal, String> expected = new Map<Decimal, String>{ 0.9 => 'AUTO', 0.6 => 'REVIEW', 0.3 => 'ESCALATE' };
        for (Decimal c : expected.keySet()) {
            Gavel_Answer a = new Gavel_Answer();
            a.key = 'damage_area';
            a.answerType = 'box';
            a.box = new Map<String, Decimal>{ 'top' => 0.10, 'bottom' => 0.5, 'left' => 0, 'right' => 1.0 };
            a.confidence = c;
            Gavel_JudgmentResponse r = new Gavel_JudgmentResponse();
            r.status = 'ok';
            r.answers = new Map<String, Gavel_Answer>{ 'damage_area' => a };
            Gavel_Outcome.QuestionResult qr = Gavel_PolicyEngine.evaluateQuestion(q, r, p);
            Assert.areEqual(expected.get(c), qr.outcome, 'confidence ' + c);
            if (qr.outcome == 'ESCALATE') {
                Assert.isNull(qr.answerValue, 'a box is always a box: below Review_At no location is recorded');
                Assert.areEqual('box_not_found', qr.reason);
            } else {
                Assert.areEqual('0.1,0.5,0,1', qr.answerValue);
            }
            Assert.areEqual(c, qr.policyValue);
        }
        Gavel_Answer unknown = new Gavel_Answer();
        unknown.key = 'damage_area';
        unknown.answerType = 'box';
        unknown.box = new Map<String, Decimal>{ 'top' => 0, 'bottom' => 1, 'left' => 0, 'right' => 1 };
        Gavel_JudgmentResponse r = new Gavel_JudgmentResponse();
        r.status = 'ok';
        r.answers = new Map<String, Gavel_Answer>{ 'damage_area' => unknown };
        Assert.areEqual('REVIEW', Gavel_PolicyEngine.evaluateQuestion(q, r, p).outcome, 'no confidence: review');
    }

    // Box with Box_Gate__c: the gate Noul decides whether a location is kept, not box confidence (ADR 0019)
    @IsTest
    static void boxGateDecidesLocation() {
        Gavel_Question q = Gavel_TestFactory.box('damage_area');
        q.boxGate = 'damage_visible';
        Gavel_Definition.Policy p = Gavel_TestFactory.policy('damage_area', 0.8, 0.5, null);
        Gavel_Answer box = new Gavel_Answer();
        box.key = 'damage_area';
        box.answerType = 'box';
        box.box = new Map<String, Decimal>{ 'top' => 0.10, 'bottom' => 0.5, 'left' => 0, 'right' => 1.0 };

        // Present, but a low box confidence: kept for the reviewer (the real cracked phones scored 0.31 to 0.49)
        box.confidence = 0.31;
        Gavel_Outcome.QuestionResult low = Gavel_PolicyEngine.evaluateQuestion(q,
            ok(new Map<String, Gavel_Answer>{ 'damage_area' => box, 'damage_visible' => noulAnswer('damage_visible', 0.98) }), p);
        Assert.areEqual('REVIEW', low.outcome);
        Assert.areEqual('box_low_confidence', low.reason);
        Assert.areEqual('0.1,0.5,0,1', low.answerValue);

        // Present and confident: banded like Score
        box.confidence = 0.9;
        Gavel_Outcome.QuestionResult high = Gavel_PolicyEngine.evaluateQuestion(q,
            ok(new Map<String, Gavel_Answer>{ 'damage_area' => box, 'damage_visible' => noulAnswer('damage_visible', 0.98) }), p);
        Assert.areEqual('AUTO', high.outcome);
        Assert.areEqual('0.1,0.5,0,1', high.answerValue);

        // Absent: no location even for a confident box (the torn receipt's box sat on a line item at 0.44)
        Gavel_Outcome.QuestionResult absent = Gavel_PolicyEngine.evaluateQuestion(q,
            ok(new Map<String, Gavel_Answer>{ 'damage_area' => box, 'damage_visible' => noulAnswer('damage_visible', 0.03) }), p);
        Assert.areEqual('ESCALATE', absent.outcome);
        Assert.areEqual('box_not_found', absent.reason);
        Assert.isNull(absent.answerValue);

        // No valid gate answer: fail closed
        Gavel_Answer invalidGate = Gavel_Answer.invalid('damage_visible', 'noul');
        for (Map<String, Gavel_Answer> answers : new List<Map<String, Gavel_Answer>>{
            new Map<String, Gavel_Answer>{ 'damage_area' => box },
            new Map<String, Gavel_Answer>{ 'damage_area' => box, 'damage_visible' => invalidGate }
        }) {
            Gavel_Outcome.QuestionResult none = Gavel_PolicyEngine.evaluateQuestion(q, ok(answers), p);
            Assert.areEqual('box_not_found', none.reason);
            Assert.isNull(none.answerValue);
        }
    }
}
