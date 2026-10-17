@IsTest
private class Gavel_TypeSafeProvider_Test {
    private class Sequence implements HttpCalloutMock {
        public List<Object> steps;
        public List<HttpRequest> seen = new List<HttpRequest>();

        public Sequence(List<Object> steps) {
            this.steps = steps;
        }

        public HttpResponse respond(HttpRequest req) {
            seen.add(req);
            Object step = steps.size() > 1 ? steps.remove(0) : steps[0];
            if (step instanceof String && ((String) step).startsWith('THROW:')) {
                throw new CalloutException(((String) step).substringAfter('THROW:'));
            }
            HttpResponse res = new HttpResponse();
            if (step instanceof Integer) {
                res.setStatusCode((Integer) step);
                res.setBody('{"error":"x"}');
            } else {
                res.setStatusCode(200);
                res.setBody((String) step);
            }
            return res;
        }
    }

    private static Gavel_JudgmentRequest request() {
        Gavel_Definition d = Gavel_TestFactory.triage('Test_Triage');
        Gavel_JudgmentRequest r = new Gavel_JudgmentRequest();
        r.definitionApiName = d.apiName;
        r.definitionVersion = 1;
        r.model = 'jev-1.13.0';
        r.state = new Map<String, Object>{ 'subject' => 'Charged twice', 'description' => 'I was billed two times this month' };
        r.questions = d.questions;
        r.namedCredential = 'Gavel_TypeSafe';
        r.endpointPath = '/v1/systemone';
        return r;
    }

    private static String billingBody(Decimal billing, Decimal fraud) {
        Decimal rest = 1 - billing - fraud;
        return new Gavel_MockProvider.Body()
            .withModel('jev-1.13.0')
            .choice('category', new Map<String, Decimal>{ 'BILLING' => billing, 'FRAUD' => fraud, 'TECHNICAL' => rest / 2, 'ACCOUNT' => rest / 2 }, 0.7)
            .noul('fraud_concern', 0.05)
            .json();
    }

    private static Gavel_JudgmentResponse run(Gavel_JudgmentRequest req, List<Object> steps) {
        Test.setMock(HttpCalloutMock.class, new Sequence(steps));
        return new Gavel_TypeSafeProvider().judge(req);
    }

    // AS-1.1 Valid Choice response
    @IsTest
    static void validChoiceResponse() {
        Gavel_JudgmentResponse r = run(request(), new List<Object>{ billingBody(0.82, 0.08) });
        Assert.areEqual('ok', r.status);
        Assert.areEqual('BILLING', r.answers.get('category').choice);
        Assert.areEqual(0.7, r.answers.get('category').confidence, 'confidence populated');
        Assert.areEqual(0.82, r.answers.get('category').probabilities.get('BILLING'));
        Assert.areEqual('jev-1.13.0', r.modelVersion, 'versioned model recorded');
        Assert.areEqual(0.05, r.answers.get('fraud_concern').probability);
        Assert.areEqual(200, r.httpStatus);
        Assert.isNotNull(r.latencyMs);
    }

    // AS-1.2 Response with unknown option
    @IsTest
    static void unknownOptionIsContractMismatch() {
        String body = new Gavel_MockProvider.Body()
            .choice('category', new Map<String, Decimal>{ 'BILLING' => 0.5, 'FRAUD' => 0.2, 'TECHNICAL' => 0.1, 'ACCOUNT' => 0.1, 'REFUND' => 0.1 }, 0.6)
            .noul('fraud_concern', 0.1)
            .json();
        Gavel_JudgmentResponse r = run(request(), new List<Object>{ body });
        Assert.areEqual('contract_mismatch', r.status);
        Assert.isNull(r.answers, 'no answer is exposed to the policy engine');
    }

    // AS-1.3 Key never leaks
    @IsTest
    static void keyNeverLeaks() {
        // A server that echoes a token-shaped value in its error body. Built from fragments so source scans stay clean.
        String fakeSecret = 'sk' + '_live_' + 'Zq9' + 'AbCdEfGhIjKlMnOp';
        String echoed = 'Bear' + 'er ' + fakeSecret;
        Sequence mock = new Sequence(new List<Object>{ 'THROW:Unauthorized: ' + echoed });
        Test.setMock(HttpCalloutMock.class, mock);
        Gavel_JudgmentRequest req = request();
        Gavel_JudgmentResponse r = new Gavel_TypeSafeProvider().judge(req);

        HttpRequest sent = mock.seen[0];
        Assert.isNull(sent.getHeader('Authorization'), 'Apex never sets the Authorization header');
        Assert.isTrue(sent.getEndpoint().startsWith('callout:Gavel_TypeSafe/'), 'key is injected by the named credential');
        Assert.isFalse(sent.getBody().containsIgnoreCase('bearer'), 'no auth material in the body');
        String serialized = JSON.serialize(r);
        Assert.isFalse(serialized.contains(fakeSecret), 'exception text is not carried into the response');
        Assert.isFalse(serialized.containsIgnoreCase('bearer'));
        Assert.areEqual('http_error', r.status);

        // Same check when the server returns the token in a non-2xx body.
        Sequence mock2 = new Sequence(new List<Object>{ 401 });
        Test.setMock(HttpCalloutMock.class, mock2);
        Gavel_JudgmentResponse r2 = new Gavel_TypeSafeProvider().judge(req);
        Assert.isFalse(JSON.serialize(r2).contains(fakeSecret));
        Assert.areEqual(401, r2.httpStatus);

        // Through the runtime: nothing token-shaped reaches any ledger field.
        Gavel_TestFactory.ops(true);
        Gavel_Definition d = Gavel_TestFactory.triage('Leak_Check');
        d.providerClass = 'Gavel_TypeSafeProvider';
        d.namedCredential = 'Gavel_TypeSafe';
        d.endpointPath = '/v1/systemone';
        Gavel_TestFactory.register(d);
        Test.setMock(HttpCalloutMock.class, new Sequence(new List<Object>{ 'THROW:Unauthorized: ' + echoed }));
        Case c = Gavel_TestFactory.newCase('Help', 'Login fails');
        insert c;
        Test.startTest(); // callouts cannot follow the test's own uncommitted DML
        Gavel_Runtime.RunResult run = Gavel_Runtime.run(c.Id, 'Leak_Check');
        Test.stopTest();
        Assert.areEqual('ERROR', run.outcome);
        String ledgerText = JSON.serialize([SELECT Name, Outcome__c, Reason__c, Answers_JSON__c, Provider_Status__c, Action_Taken__c,
            Redaction_Summary__c, Model_Version__c, State_JSON__c FROM Gavel_Decision_Log__c WHERE Id = :run.ledgerId]);
        Assert.isFalse(ledgerText.contains(fakeSecret), 'no secret in the ledger');
        Assert.isFalse(ledgerText.containsIgnoreCase('bearer'), 'no auth header value in the ledger');
    }

    // AS-1.4 Alias blocked when Live
    @IsTest
    static void aliasBlockedWhenLive() {
        // Activation path: a Live definition whose provider config model is an alias fails validation.
        Gavel_Definition d = Gavel_TestFactory.triage('Test_Alias');
        d.mode = Gavel_Definition.MODE_LIVE;
        d.model = 'jev-latest';
        Gavel_TestFactory.seal(d);
        Assert.isTrue(Gavel_DefinitionValidator.validate(d).errors.contains('model_alias_not_allowed_live'));

        // Runtime path: the provider refuses before any callout.
        Gavel_JudgmentRequest req = request();
        req.model = 'jev-latest';
        req.live = true;
        Sequence mock = new Sequence(new List<Object>{ billingBody(0.9, 0.05) });
        Test.setMock(HttpCalloutMock.class, mock);
        Gavel_JudgmentResponse r = new Gavel_TypeSafeProvider().judge(req);
        Assert.areEqual('invalid_request', r.status);
        Assert.areEqual('model_alias_not_allowed_live', r.errorCode);
        Assert.areEqual(0, mock.seen.size(), 'no callout');
    }

    @IsTest
    static void wireBodyCarriesModelStateAndQuestions() {
        Gavel_JudgmentRequest req = request();
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(Gavel_TypeSafeProvider.body(req));
        Assert.areEqual('jev-1.13.0', body.get('model'));
        Assert.areEqual(2, ((Map<String, Object>) body.get('state')).size());
        Map<String, Object> qs = (Map<String, Object>) body.get('questions');
        Assert.areEqual(2, qs.size());
        Map<String, Object> choice = (Map<String, Object>) qs.get('category');
        Assert.areEqual('choice', choice.get('type'));
        Assert.isNotNull(choice.get('instructions'));
        Assert.areEqual(4, ((Map<String, Object>) choice.get('criteria')).size());
        Map<String, Object> noul = (Map<String, Object>) qs.get('fraud_concern');
        Assert.areEqual('noul', noul.get('type'));
        Assert.isFalse(noul.containsKey('criteria'), 'noul criteria is optional and omitted');
    }

    @IsTest
    static void scoreCriteriaAreOrderedByLevel() {
        Gavel_Question q = new Gavel_Question();
        q.key = 'urgency';
        q.questionType = 'score';
        q.prompt = 'How urgent is this?';
        q.options = new List<Gavel_Option>();
        for (Integer i = 2; i >= 0; i--) {
            Gavel_Option o = new Gavel_Option();
            o.key = 'L' + i;
            o.label = 'Level ' + i;
            o.level = i;
            q.options.add(o);
        }
        Gavel_JudgmentRequest req = request();
        req.questions = new List<Gavel_Question>{ q };
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(Gavel_TypeSafeProvider.body(req));
        Map<String, Object> score = (Map<String, Object>) ((Map<String, Object>) body.get('questions')).get('urgency');
        List<Object> criteria = (List<Object>) score.get('criteria');
        Assert.areEqual(new List<Object>{ 'Level 0', 'Level 1', 'Level 2' }, criteria);
    }

    @IsTest
    static void noulFieldIsRead() {
        String body = '{"model":"jev-1.13.0","answers":{"category":{"type":"choice","choice":"BILLING","probabilities":{"BILLING":0.9,"FRAUD":0.04,"TECHNICAL":0.03,"ACCOUNT":0.03},"confidence":0.8},"fraud_concern":{"type":"noul","noul":0.2}},"usage":{"input_tokens":10,"output_tokens":5}}';
        Gavel_JudgmentResponse r = run(request(), new List<Object>{ body });
        Assert.areEqual('ok', r.status, 'detail: ' + r.errorCode);
    }

    @IsTest
    static void httpErrorsAndTimeoutsAreTyped() {
        Assert.areEqual('http_error', run(request(), new List<Object>{ 500 }).status);
        Assert.areEqual('http_error', run(request(), new List<Object>{ 400 }).status);
        Assert.areEqual('timeout', run(request(), new List<Object>{ 'THROW:Read timed out' }).status);
        Assert.areEqual('invalid_response', run(request(), new List<Object>{ '' }).status, 'HTTP 200 with empty body');
        Assert.areEqual('invalid_response', run(request(), new List<Object>{ '{not json' }).status);
        Assert.areEqual('invalid_response', run(request(), new List<Object>{ '[1,2]' }).status);
        Assert.areEqual('invalid_response', run(request(), new List<Object>{ '{"model":"jev-1.13.0"}' }).status);
    }

    @IsTest
    static void retryOnlyInAsync() {
        Gavel_JudgmentRequest syncReq = request();
        Gavel_JudgmentResponse sync = run(syncReq, new List<Object>{ 429, billingBody(0.9, 0.05) });
        Assert.areEqual('http_error', sync.status, 'no retry in sync context');
        Assert.areEqual(1, sync.attempts);

        Gavel_JudgmentRequest asyncReq = request();
        asyncReq.allowRetry = true;
        Gavel_JudgmentResponse async = run(asyncReq, new List<Object>{ 503, billingBody(0.9, 0.05) });
        Assert.areEqual('ok', async.status, 'one retry for 503 in async');
        Assert.areEqual(2, async.attempts);

        Gavel_JudgmentResponse twice = run(asyncReq, new List<Object>{ 429, 429, billingBody(0.9, 0.05) });
        Assert.areEqual('http_error', twice.status, 'at most one retry');
    }

    @IsTest
    static void probabilityTolerance() {
        String low = new Gavel_MockProvider.Body()
            .choice('category', new Map<String, Decimal>{ 'BILLING' => 0.5, 'FRAUD' => 0.28, 'TECHNICAL' => 0.1, 'ACCOUNT' => 0.1 }, 0.5)
            .noul('fraud_concern', 0.1).json();
        Assert.areEqual('contract_mismatch', run(request(), new List<Object>{ low }).status, 'sum 0.98');
        String high = new Gavel_MockProvider.Body()
            .choice('category', new Map<String, Decimal>{ 'BILLING' => 0.504, 'FRAUD' => 0.3, 'TECHNICAL' => 0.1, 'ACCOUNT' => 0.1 }, 0.5)
            .noul('fraud_concern', 0.1).json();
        Assert.areEqual('ok', run(request(), new List<Object>{ high }).status, 'sum 1.004');
    }

    @IsTest
    static void valueRangesAndNulls() {
        String badConf = new Gavel_MockProvider.Body()
            .choice('category', new Map<String, Decimal>{ 'BILLING' => 0.7, 'FRAUD' => 0.1, 'TECHNICAL' => 0.1, 'ACCOUNT' => 0.1 }, 1.2)
            .noul('fraud_concern', 0.1).json();
        Assert.areEqual('contract_mismatch', run(request(), new List<Object>{ badConf }).status);
        String badNoul = new Gavel_MockProvider.Body()
            .choice('category', new Map<String, Decimal>{ 'BILLING' => 0.7, 'FRAUD' => 0.1, 'TECHNICAL' => 0.1, 'ACCOUNT' => 0.1 }, 0.8)
            .noul('fraud_concern', -0.2).json();
        Assert.areEqual('contract_mismatch', run(request(), new List<Object>{ badNoul }).status);
        String missingOption = new Gavel_MockProvider.Body()
            .choice('category', new Map<String, Decimal>{ 'BILLING' => 0.8, 'FRAUD' => 0.2 }, 0.8)
            .noul('fraud_concern', 0.1).json();
        Assert.areEqual('contract_mismatch', run(request(), new List<Object>{ missingOption }).status);

        String nullProb = '{"model":"jev-1.13.0","answers":{"category":{"probabilities":{"BILLING":null,"FRAUD":0.5,"TECHNICAL":0.25,"ACCOUNT":0.25}},"fraud_concern":{"probability":null}}}';
        Gavel_JudgmentResponse r = run(request(), new List<Object>{ nullProb });
        Assert.areEqual('ok', r.status);
        Assert.areEqual('invalid_response', r.answers.get('category').status);
        Assert.areEqual('invalid_response', r.answers.get('fraud_concern').status);

        String nullConfidence = new Gavel_MockProvider.Body()
            .choice('category', new Map<String, Decimal>{ 'BILLING' => 0.9, 'FRAUD' => 0.04, 'TECHNICAL' => 0.03, 'ACCOUNT' => 0.03 }, null)
            .noul('fraud_concern', 0.1).json();
        Gavel_JudgmentResponse nc = run(request(), new List<Object>{ nullConfidence });
        Assert.areEqual('ok', nc.status);
        Assert.isNull(nc.answers.get('category').confidence, 'null confidence is passed through (policy forces REVIEW)');
    }

    @IsTest
    static void missingAndExtraAnswerKeys() {
        String body = '{"model":"jev-1.13.0","results":[{"key":"category","probabilities":{"BILLING":0.9,"FRAUD":0.04,"TECHNICAL":0.03,"ACCOUNT":0.03},"confidence":0.8},{"key":"surprise","probability":0.5}]}';
        Gavel_JudgmentResponse r = run(request(), new List<Object>{ body });
        Assert.areEqual('ok', r.status, 'extra keys are ignored');
        Assert.isTrue(r.warnings.contains('extra_answer:surprise'));
        Assert.areEqual('invalid_response', r.answers.get('fraud_concern').status, 'missing answer marked invalid');
        Assert.areEqual('BILLING', r.answers.get('category').choice);

        String noModel = '{"answers":{"category":{"probabilities":{"BILLING":0.9,"FRAUD":0.04,"TECHNICAL":0.03,"ACCOUNT":0.03}},"fraud_concern":{"probability":0.2}}}';
        Gavel_JudgmentResponse nm = run(request(), new List<Object>{ noModel });
        Assert.isNull(nm.modelVersion);
        Assert.isTrue(nm.warnings.contains('model_version_missing'));
    }

    @IsTest
    static void scoreAnswers() {
        Gavel_Definition d = Gavel_TestFactory.definition('Test_Urgency', 'Case');
        d.questions.add(Gavel_TestFactory.score('urgency', 0, 4));
        Gavel_JudgmentRequest req = request();
        req.questions = d.questions;
        Gavel_JudgmentResponse ok = run(req, new List<Object>{ '{"model":"jev-1.13.0","answers":{"urgency":{"score":3.4,"confidence":0.9,"probabilities":{"0":0.0,"1":0.05,"2":0.1,"3":0.45,"4":0.4}}}}' });
        Assert.areEqual('ok', ok.status);
        Assert.areEqual(3.4, ok.answers.get('urgency').score);
        Assert.areEqual('contract_mismatch', run(req, new List<Object>{ '{"answers":{"urgency":{"score":7,"confidence":0.9}}}' }).status);
        Assert.areEqual('contract_mismatch', run(req, new List<Object>{ '{"answers":{"urgency":{"score":"high"}}}' }).status);

        // Score levels not starting at 0: invalid_request before callout.
        req.questions = new List<Gavel_Question>{ Gavel_TestFactory.score('urgency', 1, 5) };
        Sequence mock = new Sequence(new List<Object>{ 200 });
        Test.setMock(HttpCalloutMock.class, mock);
        Gavel_JudgmentResponse bad = new Gavel_TypeSafeProvider().judge(req);
        Assert.areEqual('invalid_request', bad.status);
        Assert.areEqual('score_levels_must_start_at_zero', bad.errorCode);
        Assert.areEqual(0, mock.seen.size());
    }

    @IsTest
    static void requestValidationBeforeCallout() {
        Gavel_JudgmentRequest req = request();
        req.questions = new List<Gavel_Question>{ Gavel_TestFactory.choice('one', new List<String>{ 'ONLY' }) };
        Assert.areEqual('choice_option_count_out_of_range', Gavel_RequestValidator.validate(req));
        req.questions = new List<Gavel_Question>{ Gavel_TestFactory.noul('a'), Gavel_TestFactory.noul('a') };
        Assert.areEqual('duplicate_question_key', Gavel_RequestValidator.validate(req));
        Gavel_Question empty = Gavel_TestFactory.noul('b');
        empty.prompt = ' ';
        req.questions = new List<Gavel_Question>{ empty };
        Assert.areEqual('empty_prompt', Gavel_RequestValidator.validate(req));
        req.questions = new List<Gavel_Question>();
        Assert.areEqual('question_count_out_of_range', Gavel_RequestValidator.validate(req));
        req = request();
        req.timeoutMs = 70000;
        Assert.areEqual('timeout_out_of_range', Gavel_RequestValidator.validate(req));
        req = request();
        req.state = new Map<String, Object>{ 'big' => 'x'.repeat(150001) };
        Assert.areEqual('state_too_large', Gavel_RequestValidator.validate(req));
        Assert.areEqual('request_missing', Gavel_RequestValidator.validate(null));
        req = request();
        req.model = null;
        Assert.areEqual('model_missing', Gavel_RequestValidator.validate(req));
        req = request();
        req.timeoutMs = 99;
        Assert.areEqual(99, req.effectiveTimeoutMs());
        req.timeoutMs = null;
        Assert.areEqual(10000, req.effectiveTimeoutMs());
    }

    private static Gavel_JudgmentRequest imageRequest(Gavel_ImageAsset img) {
        Gavel_JudgmentRequest r = new Gavel_JudgmentRequest();
        r.definitionApiName = 'Test_Photo';
        r.definitionVersion = 1;
        r.model = 'jev-1.14.0';
        r.state = new Map<String, Object>{ 'photo' => img.reference, 'claim' => 'Screen cracked on arrival' };
        r.assets = new List<Gavel_ImageAsset>{ img };
        r.questions = new List<Gavel_Question>{ Gavel_TestFactory.noul('damage_visible'), Gavel_TestFactory.box('damage_area') };
        r.namedCredential = 'Gavel_TypeSafe';
        r.endpointPath = '/v1/systemone';
        return r;
    }

    private static String hexOf(String text) {
        return EncodingUtil.convertToHex(Blob.valueOf(text));
    }

    // Jev 1.14: images go as multipart/form-data with the opt-in header; the Box answer is parsed
    @IsTest
    static void imagesSentAsMultipart() {
        Gavel_ImageAsset img = new Gavel_ImageAsset(Gavel_TestFactory.png(), 'image/png');
        String digest = img.reference.substringBetween(':', '>');
        Assert.areEqual(32, digest.length(), 'content-addressed reference: 32 hex digits of SHA-256');
        String reply = new Gavel_MockProvider.Body().withModel('jev-1.14.0')
            .noul('damage_visible', 0.93).box('damage_area', 0.2, 0.6, 0.1, 0.5, 0.9).json();
        Sequence seq = new Sequence(new List<Object>{ reply });
        Test.setMock(HttpCalloutMock.class, seq);
        Gavel_JudgmentResponse r = new Gavel_TypeSafeProvider().judge(imageRequest(img));

        Assert.areEqual('ok', r.status, 'detail: ' + r.errorCode);
        Gavel_Answer box = r.answers.get('damage_area');
        Assert.areEqual(new Map<String, Decimal>{ 'top' => 0.2, 'bottom' => 0.6, 'left' => 0.1, 'right' => 0.5 }, box.box);
        Assert.areEqual(0.9, box.confidence);

        HttpRequest sent = seq.seen[0];
        String contentType = sent.getHeader('Content-Type');
        Assert.isTrue(contentType.startsWith('multipart/form-data; boundary='), contentType);
        Assert.areEqual('true', sent.getHeader('TypeSafe-Danger-Zone-Images'), 'images need the opt-in header');
        String boundary = contentType.substringAfter('boundary=');
        String hex = EncodingUtil.convertToHex(sent.getBodyAsBlob());
        Assert.isTrue(hex.startsWith(hexOf('--' + boundary + '\r\nContent-Disposition: form-data; name="request"\r\nContent-Type: application/json\r\n\r\n{"model":"jev-1.14.0"')), 'request part first');
        Assert.isTrue(hex.contains(hexOf('"type":"box","instructions":"Where is the damage_area?"')), 'box question has no criteria');
        Assert.isTrue(hex.contains(hexOf('"type":"image","part":"asset-0"')), 'assets map names the part');
        Assert.isTrue(hex.contains(hexOf(digest)), 'the reference appears in the request part');
        Assert.isTrue(hex.contains(hexOf('--' + boundary + '\r\nContent-Disposition: form-data; name="asset-0"; filename="asset-0"\r\nContent-Type: image/png\r\n\r\n')
            + EncodingUtil.convertToHex(Gavel_TestFactory.png()) + hexOf('\r\n--' + boundary + '--\r\n')), 'raw image bytes, then the closing boundary');
    }

    @IsTest
    static void textOnlyStaysJson() {
        Sequence seq = new Sequence(new List<Object>{ billingBody(0.82, 0.08) });
        Test.setMock(HttpCalloutMock.class, seq);
        new Gavel_TypeSafeProvider().judge(request());
        Assert.areEqual('application/json', seq.seen[0].getHeader('Content-Type'));
        Assert.isNull(seq.seen[0].getHeader('TypeSafe-Danger-Zone-Images'), 'no opt-in header without images');
    }

    @IsTest
    static void unreferencedImageRejectedBeforeCallout() {
        Gavel_ImageAsset img = new Gavel_ImageAsset(Gavel_TestFactory.png(), 'image/png');
        Gavel_JudgmentRequest req = imageRequest(img);
        req.state = new Map<String, Object>{ 'claim' => 'No photo reference here' };
        Sequence seq = new Sequence(new List<Object>{ '{}' });
        Test.setMock(HttpCalloutMock.class, seq);
        Gavel_JudgmentResponse r = new Gavel_TypeSafeProvider().judge(req);
        Assert.areEqual('invalid_request', r.status);
        Assert.areEqual('image_not_referenced', r.errorCode);
        Assert.areEqual(0, seq.seen.size(), 'no callout');
    }

    @IsTest
    static void malformedBoxesAreContractMismatches() {
        Gavel_ImageAsset img = new Gavel_ImageAsset(Gavel_TestFactory.png(), 'image/png');
        Map<String, Object> outOfRange = new Map<String, Object>{ 'type' => 'box', 'box' => new Map<String, Object>{ 'top' => 0.1, 'bottom' => 1.4, 'left' => 0, 'right' => 1 } };
        Map<String, Object> inverted = new Map<String, Object>{ 'type' => 'box', 'box' => new Map<String, Object>{ 'top' => 0.8, 'bottom' => 0.2, 'left' => 0, 'right' => 1 } };
        for (Map<String, Object> bad : new List<Map<String, Object>>{ outOfRange, inverted }) {
            String body = new Gavel_MockProvider.Body().withModel('jev-1.14.0').noul('damage_visible', 0.5).raw('damage_area', bad).json();
            Gavel_JudgmentResponse r = run(imageRequest(img), new List<Object>{ body });
            Assert.areEqual('contract_mismatch', r.status);
            Assert.isTrue(r.errorCode == 'box_out_of_range' || r.errorCode == 'box_inverted', r.errorCode);
        }
        String missing = new Gavel_MockProvider.Body().withModel('jev-1.14.0').noul('damage_visible', 0.5)
            .raw('damage_area', new Map<String, Object>{ 'type' => 'box' }).json();
        Gavel_JudgmentResponse r = run(imageRequest(img), new List<Object>{ missing });
        Assert.areEqual('ok', r.status);
        Assert.isFalse(r.answers.get('damage_area').isValid(), 'a box answer without coordinates is invalid, not guessed');
    }

    // An image TypeSafe would reject with HTTP 400 is refused before the callout, so it never counts toward the breaker
    @IsTest
    static void unsupportedImageSizeRefusedBeforeCallout() {
        Gavel_ImageAsset tiny = new Gavel_ImageAsset(EncodingUtil.base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='), 'image/png');
        Sequence seq = new Sequence(new List<Object>{ '{}' });
        Test.setMock(HttpCalloutMock.class, seq);
        Gavel_JudgmentResponse r = new Gavel_TypeSafeProvider().judge(imageRequest(tiny));
        Assert.areEqual('invalid_request', r.status);
        Assert.areEqual('image_size_unsupported', r.errorCode);
        Assert.areEqual(0, seq.seen.size(), 'no callout');
        Assert.isFalse(Gavel_JudgmentResponse.PROVIDER_FAILURES.contains(r.status), 'not a provider failure: the breaker is unaffected');
    }
}
