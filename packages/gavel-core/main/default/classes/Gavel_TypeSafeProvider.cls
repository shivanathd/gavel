/**
 * TypeSafe Jev provider (CORE-001.2). POST {Named Credential}/v1/systemone.
 * The API key is injected by External Credential Gavel_TypeSafe_Auth; this class never sees it,
 * never sets an Authorization header and never logs request or response bodies (CORE-001.3).
 * All failures are typed statuses (ADR-005).
 */
public with sharing class Gavel_TypeSafeProvider implements Gavel_JudgmentProvider {
    public static final String DEFAULT_NAMED_CREDENTIAL = 'Gavel_TypeSafe';
    public static final String DEFAULT_PATH = '/v1/systemone';
    private static final Set<Integer> RETRYABLE = new Set<Integer>{ 429, 503, 529 };

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

    /**
     * Wire body, verified against https://docs.typesafe.ai/api (2026-10-01) and the live contract test:
     * {"model": ..., "state": ..., "questions": {"<key>": {"type", "instructions", "criteria"}}}
     *   noul:   criteria optional (omitted)
     *   choice: criteria = {"<option key>": "<description or label>"}
     *   score:  criteria = ["level 0 description", "level 1 description", ...] in level order
     * instructions = the prompt, or {"question": prompt, "rules": instructions} when rules are set.
     */
    @TestVisible
    private static String body(Gavel_JudgmentRequest req) {
        JSONGenerator g = JSON.createGenerator(false);
        g.writeStartObject();
        for (Gavel_Question q : req.questions) {
            g.writeFieldName(q.key);
            g.writeStartObject();
            g.writeStringField('type', q.questionType);
            if (String.isNotBlank(q.instructions)) {
                g.writeFieldName('instructions');
                g.writeStartObject();
                g.writeStringField('question', q.prompt);
                g.writeStringField('rules', q.instructions);
                g.writeEndObject();
            } else {
                g.writeStringField('instructions', q.prompt);
            }
            if (q.isChoice()) {
                g.writeFieldName('criteria');
                g.writeStartObject();
                for (Gavel_Option o : q.options) {
                    String text = String.isNotBlank(o.description) ? o.description : (String.isNotBlank(o.label) ? o.label : null);
                    if (text == null) {
                        g.writeNullField(o.key);
                    } else {
                        g.writeStringField(o.key, text);
                    }
                }
                g.writeEndObject();
            } else if (q.isScore()) {
                List<Gavel_Option> levels = new List<Gavel_Option>(q.options);
                levels.sort(new ByLevel());
                g.writeFieldName('criteria');
                g.writeStartArray();
                for (Gavel_Option o : levels) {
                    String label = String.isNotBlank(o.label) ? o.label : o.key;
                    g.writeString(String.isNotBlank(o.description) ? label + ': ' + o.description : label);
                }
                g.writeEndArray();
            }
            g.writeEndObject();
        }
        g.writeEndObject();
        return '{"model":' + JSON.serialize(req.model) + ',"state":' + req.canonicalState() + ',"questions":' + g.getAsString() + '}';
    }

    private class ByLevel implements System.Comparator<Gavel_Option> {
        public Integer compare(Gavel_Option a, Gavel_Option b) {
            Integer x = a.level == null ? 0 : a.level;
            Integer y = b.level == null ? 0 : b.level;
            return x == y ? 0 : (x < y ? -1 : 1);
        }
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
