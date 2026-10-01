@IsTest
private class Gavel_MockProvider_Test {
    private static Gavel_JudgmentRequest request(String definition, Map<String, Object> state) {
        Gavel_Definition d = Gavel_TestFactory.triage(definition);
        Gavel_JudgmentRequest r = new Gavel_JudgmentRequest();
        r.definitionApiName = definition;
        r.definitionVersion = 1;
        r.model = 'jev-1.13.0';
        r.state = state;
        r.questions = d.questions;
        return r;
    }

    @IsTest
    static void registeredResponseIsValidated() {
        Gavel_MockProvider.respondWith('Mock_A', new Gavel_MockProvider.Body()
            .choice('category', new Map<String, Decimal>{ 'BILLING' => 0.82, 'FRAUD' => 0.08, 'TECHNICAL' => 0.05, 'ACCOUNT' => 0.05 }, 0.75)
            .noul('fraud_concern', 0.02)
            .json());
        Gavel_JudgmentResponse r = new Gavel_MockProvider().judge(request('Mock_A', new Map<String, Object>{ 'description' => 'billing' }));
        Assert.areEqual('ok', r.status);
        Assert.areEqual('BILLING', r.answers.get('category').choice);
        Assert.areEqual(Gavel_MockProvider.MOCK_MODEL, r.modelVersion);
        Assert.areEqual(1, Gavel_MockProvider.callCount);
        Assert.areEqual('Mock_A', Gavel_MockProvider.lastRequest.definitionApiName);
    }

    @IsTest
    static void deterministic() {
        Gavel_JudgmentRequest req = request('Mock_Generic', new Map<String, Object>{ 'description' => 'anything' });
        Gavel_JudgmentResponse a = new Gavel_MockProvider().judge(req);
        Gavel_JudgmentResponse b = new Gavel_MockProvider().judge(req);
        Assert.areEqual('ok', a.status);
        Assert.areEqual(JSON.serialize(a.answers), JSON.serialize(b.answers));
        Assert.areEqual('BILLING', a.answers.get('category').choice, 'generic picks first non-escape option');
        Assert.areEqual(0.1, a.answers.get('fraud_concern').probability);
    }

    @IsTest
    static void genericScoreAndEscapeSkipping() {
        Gavel_JudgmentRequest req = request('Mock_Score', new Map<String, Object>{ 'x' => 'y' });
        Gavel_Question esc = Gavel_TestFactory.choice('route', new List<String>{ 'manual_review', 'QUEUE_A' });
        esc.options[0].isEscape = true;
        req.questions = new List<Gavel_Question>{ Gavel_TestFactory.score('urgency', 0, 4), esc };
        Gavel_JudgmentResponse r = new Gavel_MockProvider().judge(req);
        Assert.areEqual('ok', r.status, 'errorCode=' + r.errorCode);
        Assert.areEqual(0, r.answers.get('urgency').score);
        Assert.areEqual('QUEUE_A', r.answers.get('route').choice);
    }

    @IsTest
    static void simulatedFailures() {
        Gavel_MockProvider.failWith('Mock_Down', 'http_error', 500);
        Gavel_JudgmentResponse r = new Gavel_MockProvider().judge(request('Mock_Down', new Map<String, Object>{ 'a' => 'b' }));
        Assert.areEqual('http_error', r.status);
        Assert.areEqual(500, r.httpStatus);
        Gavel_MockProvider.failWith('Mock_Down', 'timeout', null);
        Assert.areEqual('timeout', new Gavel_MockProvider().judge(request('Mock_Down', new Map<String, Object>{ 'a' => 'b' })).status);
        Gavel_MockProvider.respondWith('Mock_Down', 'not json');
        Assert.areEqual('invalid_response', new Gavel_MockProvider().judge(request('Mock_Down', new Map<String, Object>{ 'a' => 'b' })).status);
        Gavel_MockProvider.reset();
        Assert.areEqual(0, Gavel_MockProvider.callCount);
    }

    @IsTest
    static void contractStillEnforced() {
        Gavel_MockProvider.respondWith('Mock_Bad', new Gavel_MockProvider.Body()
            .choice('category', new Map<String, Decimal>{ 'REFUND' => 1 }, 0.9).noul('fraud_concern', 0.1).json());
        Assert.areEqual('contract_mismatch', new Gavel_MockProvider().judge(request('Mock_Bad', new Map<String, Object>{ 'a' => 'b' })).status);
        Gavel_JudgmentRequest live = request('Mock_Live', new Map<String, Object>{ 'a' => 'b' });
        live.live = true;
        live.model = 'jev-latest';
        Gavel_JudgmentResponse r = new Gavel_MockProvider().judge(live);
        Assert.areEqual('invalid_request', r.status);
        Assert.areEqual('model_alias_not_allowed_live', r.errorCode);
    }

    @IsTest
    static void fixtureRulesFromStaticResources() {
        // Core ships an empty fixture file; packs add theirs. Loading must never throw.
        Gavel_JudgmentResponse r = new Gavel_MockProvider().judge(request('Not_In_Any_Fixture', new Map<String, Object>{ 'a' => 'b' }));
        Assert.areEqual('ok', r.status);
    }

    @IsTest
    static void canonicalJson() {
        Map<String, Object> state = new Map<String, Object>{ 'b' => 1, 'a' => 'x', 'c' => new Map<String, Object>{ 'z' => true, 'y' => null }, 'd' => new List<Object>{ 1.5, 'q' } };
        Assert.areEqual('{"a":"x","b":1,"c":{"y":null,"z":true},"d":[1.5,"q"]}', Gavel_Json.canonical(state));
        Assert.areEqual(64, Gavel_Json.sha256Hex('x').length());
        Assert.areEqual('"s"', Gavel_Json.canonical('s'));
    }
}
