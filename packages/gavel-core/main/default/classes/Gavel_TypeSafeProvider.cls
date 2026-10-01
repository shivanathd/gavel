/**
 * TypeSafe Jev provider (CORE-001.2). POST {Named Credential}/v1/systemone.
 * The API key is injected by External Credential Gavel_TypeSafe_Auth; this class never sees it,
 * never sets an Authorization header and never logs request or response bodies (CORE-001.3).
 * All failures are typed statuses (ADR-005).
 */
public with sharing class Gavel_TypeSafeProvider implements Gavel_JudgmentProvider {
    public static final String DEFAULT_NAMED_CREDENTIAL = 'Gavel_TypeSafe';
    public static final String DEFAULT_PATH = '/v1/systemone';
    private static final Set<Integer> RETRYABLE = new Set<Integer>{ 429, 503 };

    public Gavel_JudgmentResponse judge(Gavel_JudgmentRequest req) {
        Long started = System.currentTimeMillis();
        Gavel_JudgmentResponse resp;
        try {
            String invalid = Gavel_RequestValidator.validate(req);
            if (invalid != null) {
                resp = Gavel_JudgmentResponse.failure(Gavel_JudgmentResponse.INVALID_REQUEST, null, invalid);
            } else {
                resp = send(req);
            }
        } catch (Exception e) {
            // Defensive: never let anything escape into caller code. Only the type name is kept.
            resp = Gavel_JudgmentResponse.failure(Gavel_JudgmentResponse.INVALID_RESPONSE, null, 'provider_exception:' + e.getTypeName());
        }
        resp.latencyMs = System.currentTimeMillis() - started;
        return resp;
    }

    private Gavel_JudgmentResponse send(Gavel_JudgmentRequest req) {
        HttpRequest http = new HttpRequest();
        String nc = String.isBlank(req.namedCredential) ? DEFAULT_NAMED_CREDENTIAL : req.namedCredential;
        String path = String.isBlank(req.endpointPath) ? DEFAULT_PATH : req.endpointPath;
        http.setEndpoint('callout:' + nc + path);
        http.setMethod('POST');
        http.setHeader('Content-Type', 'application/json');
        http.setHeader('Accept', 'application/json');
        http.setTimeout(req.effectiveTimeoutMs());
        http.setBody(body(req));

        Integer maxAttempts = req.allowRetry == true ? 2 : 1;
        Integer attempts = 0;
        HttpResponse res;
        while (attempts < maxAttempts) {
            attempts++;
            try {
                res = new Http().send(http);
            } catch (CalloutException e) {
                String msg = e.getMessage() == null ? '' : e.getMessage().toLowerCase();
                String status = msg.contains('timed out') || msg.contains('timeout') ? Gavel_JudgmentResponse.TIMEOUT : Gavel_JudgmentResponse.HTTP_ERROR;
                String code = msg.contains('uncommitted work') ? 'uncommitted_work_pending' : null;
                Gavel_JudgmentResponse f = Gavel_JudgmentResponse.failure(status, null, code);
                f.attempts = attempts;
                return f;
            }
            if (RETRYABLE.contains(res.getStatusCode()) && attempts < maxAttempts) {
                jitter();
                continue;
            }
            break;
        }
        Integer code = res.getStatusCode();
        if (code < 200 || code > 299) {
            Gavel_JudgmentResponse f = Gavel_JudgmentResponse.failure(Gavel_JudgmentResponse.HTTP_ERROR, code, null);
            f.attempts = attempts;
            return f;
        }
        Gavel_JudgmentResponse parsed = Gavel_ResponseParser.parse(req, res.getBody());
        parsed.httpStatus = code;
        parsed.attempts = attempts;
        return parsed;
    }

    /** Wire body. Question field names are [UNVERIFIED] (OQ-2) and pinned by scripts/live-contract-test.sh. */
    @TestVisible
    private static String body(Gavel_JudgmentRequest req) {
        JSONGenerator g = JSON.createGenerator(false);
        g.writeStartArray();
        for (Gavel_Question q : req.questions) {
            g.writeStartObject();
            g.writeStringField('key', q.key);
            g.writeStringField('type', q.questionType);
            g.writeStringField(q.isNoul() ? 'proposition' : 'question', q.prompt);
            if (String.isNotBlank(q.instructions)) {
                g.writeStringField('instructions', q.instructions);
            }
            if (!q.isNoul()) {
                g.writeFieldName('options');
                g.writeStartArray();
                for (Gavel_Option o : q.options) {
                    g.writeStartObject();
                    g.writeStringField('key', o.key);
                    g.writeStringField('label', o.label == null ? o.key : o.label);
                    if (String.isNotBlank(o.description)) {
                        g.writeStringField('description', o.description);
                    }
                    if (q.isScore() && o.level != null) {
                        g.writeNumberField('level', o.level);
                    }
                    g.writeEndObject();
                }
                g.writeEndArray();
            }
            g.writeEndObject();
        }
        g.writeEndArray();
        return '{"model":' + JSON.serialize(req.model) + ',"state":' + req.canonicalState() + ',"questions":' + g.getAsString() + '}';
    }

    /** Jittered backoff before the single async retry (OPS-001.4). Apex has no sleep, so this spins briefly. */
    private static void jitter() {
        if (Test.isRunningTest()) {
            return;
        }
        Long until = System.currentTimeMillis() + 100 + Math.mod(Math.abs(Crypto.getRandomInteger()), 400);
        while (System.currentTimeMillis() < until) {
            continue;
        }
    }
}
