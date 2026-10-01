/**
 * Deterministic provider for tests, demos and CI (CORE-001.7). Never makes a callout.
 *
 * Resolution order for a request:
 *   1. a response registered with respondWith()/failWith() for the definition (tests);
 *   2. fixtures from static resources named Gavel_Mock_Fixtures* ({definition: {rules: [...], default: {...}}});
 *      a rule matches when the lowercase canonical state contains any of its whenStateContains terms;
 *   3. a generic answer derived from the question shapes.
 * The raw body goes through Gavel_ResponseParser exactly like a real provider response.
 */
public with sharing class Gavel_MockProvider implements Gavel_JudgmentProvider {
    public static final String MOCK_MODEL = 'mock-1.0.0';

    public static Integer callCount = 0;
    public static Gavel_JudgmentRequest lastRequest;
    public static List<Gavel_JudgmentRequest> requests = new List<Gavel_JudgmentRequest>();
    private static Map<String, String> registered = new Map<String, String>();
    private static Map<String, Object> fixtures;

    public static void respondWith(String definitionApiName, String body) {
        registered.put(definitionApiName, body);
    }

    public static void failWith(String definitionApiName, String status, Integer httpStatus) {
        registered.put(definitionApiName, JSON.serialize(new Map<String, Object>{ 'status' => status, 'httpStatus' => httpStatus }));
    }

    public static void reset() {
        registered.clear();
        callCount = 0;
        lastRequest = null;
        requests.clear();
    }

    public Gavel_JudgmentResponse judge(Gavel_JudgmentRequest req) {
        Long started = System.currentTimeMillis();
        callCount++;
        lastRequest = req;
        requests.add(req);
        Gavel_JudgmentResponse resp;
        try {
            String invalid = Gavel_RequestValidator.validate(req);
            if (invalid != null) {
                resp = Gavel_JudgmentResponse.failure(Gavel_JudgmentResponse.INVALID_REQUEST, null, invalid);
            } else {
                resp = respond(req, resolveBody(req));
            }
        } catch (Exception e) {
            resp = Gavel_JudgmentResponse.failure(Gavel_JudgmentResponse.INVALID_RESPONSE, null, 'provider_exception:' + e.getTypeName());
        }
        resp.attempts = 1;
        resp.latencyMs = System.currentTimeMillis() - started;
        return resp;
    }

    private static Gavel_JudgmentResponse respond(Gavel_JudgmentRequest req, String body) {
        Object parsed = null;
        try {
            parsed = JSON.deserializeUntyped(body);
        } catch (Exception e) {
            parsed = null;
        }
        if (parsed instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) parsed;
            Object status = m.get('status');
            if (status instanceof String && (String) status != Gavel_JudgmentResponse.OK && !m.containsKey('answers') && !m.containsKey('results')) {
                Integer http = m.get('httpStatus') instanceof Integer ? (Integer) m.get('httpStatus') : null;
                return Gavel_JudgmentResponse.failure((String) status, http, null);
            }
        }
        Gavel_JudgmentResponse r = Gavel_ResponseParser.parse(req, body);
        r.httpStatus = r.isOk() ? 200 : r.httpStatus;
        return r;
    }

    private static String resolveBody(Gavel_JudgmentRequest req) {
        if (registered.containsKey(req.definitionApiName)) {
            return registered.get(req.definitionApiName);
        }
        Object defFixtures = loadFixtures().get(req.definitionApiName);
        if (defFixtures instanceof Map<String, Object>) {
            Map<String, Object> f = (Map<String, Object>) defFixtures;
            String haystack = req.canonicalState().toLowerCase();
            if (f.get('rules') instanceof List<Object>) {
                for (Object ro : (List<Object>) f.get('rules')) {
                    Map<String, Object> rule = (Map<String, Object>) ro;
                    for (Object term : (List<Object>) rule.get('whenStateContains')) {
                        if (haystack.contains(String.valueOf(term).toLowerCase())) {
                            return JSON.serialize(rule.get('response'));
                        }
                    }
                }
            }
            if (f.containsKey('default')) {
                return JSON.serialize(f.get('default'));
            }
        }
        return generic(req);
    }

    private static Map<String, Object> loadFixtures() {
        if (fixtures != null) {
            return fixtures;
        }
        fixtures = new Map<String, Object>();
        for (StaticResource sr : [SELECT Name, Body FROM StaticResource WHERE Name LIKE 'Gavel_Mock_Fixtures%' ORDER BY Name]) {
            try {
                Object root = JSON.deserializeUntyped(sr.Body.toString());
                if (root instanceof Map<String, Object>) {
                    fixtures.putAll((Map<String, Object>) root);
                }
            } catch (Exception e) {
                continue;
            }
        }
        return fixtures;
    }

    /** Shape-derived answer: first non-escape option at 0.9, score 0, noul 0.1. */
    private static String generic(Gavel_JudgmentRequest req) {
        Body b = new Body();
        for (Gavel_Question q : req.questions) {
            if (q.isChoice()) {
                Map<String, Decimal> probs = new Map<String, Decimal>();
                String winner = null;
                for (Gavel_Option o : q.options) {
                    if (winner == null && o.isEscape != true) {
                        winner = o.key;
                    }
                }
                if (winner == null) {
                    winner = q.options[0].key;
                }
                Integer others = q.options.size() - 1;
                Decimal each = others == 0 ? 0 : (0.1 / others).setScale(6);
                Decimal rest = 1;
                for (Gavel_Option o : q.options) {
                    if (o.key != winner) {
                        probs.put(o.key, each);
                        rest -= each;
                    }
                }
                probs.put(winner, rest);
                b.choice(q.key, probs, 0.8);
            } else if (q.isScore()) {
                b.score(q.key, 0, 0.8);
            } else {
                b.noul(q.key, 0.1);
            }
        }
        return b.json();
    }

    /** Fluent builder for raw provider bodies, used by tests in every package. */
    public class Body {
        private Map<String, Object> answers = new Map<String, Object>();
        private String model = MOCK_MODEL;

        public Body withModel(String modelVersion) {
            this.model = modelVersion;
            return this;
        }

        public Body choice(String key, Map<String, Decimal> probabilities, Decimal confidence) {
            answers.put(key, new Map<String, Object>{ 'type' => 'choice', 'probabilities' => probabilities, 'confidence' => confidence });
            return this;
        }

        public Body score(String key, Decimal score, Decimal confidence) {
            answers.put(key, new Map<String, Object>{ 'type' => 'score', 'score' => score, 'confidence' => confidence });
            return this;
        }

        public Body noul(String key, Decimal probability) {
            answers.put(key, new Map<String, Object>{ 'type' => 'noul', 'probability' => probability });
            return this;
        }

        public Body raw(String key, Map<String, Object> answer) {
            answers.put(key, answer);
            return this;
        }

        public String json() {
            Map<String, Object> root = new Map<String, Object>{ 'answers' => answers };
            if (model != null) {
                root.put('model', model);
            }
            return JSON.serialize(root);
        }
    }
}
