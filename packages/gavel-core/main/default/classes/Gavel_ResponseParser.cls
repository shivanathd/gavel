/**
 * Turns a provider body into a validated Gavel_JudgmentResponse (CORE-001.5). Never throws.
 *
 * Wire shape verified against https://docs.typesafe.ai/api and the live contract test (2026-10-01):
 *   { "model": "jev-1.13.0",
 *     "answers" | "results": { "<key>": {...} }  or  [ { "key": "<key>", ... } ],
 *     "usage": {...} }
 *   choice: { "probabilities"|"distribution": {option: p}, "choice"?: key, "confidence"?: c }
 *   score:  { "score"|"value": n, "confidence"?: c, "probabilities"?: {...} }
 *   noul:   { "noul": p }   (verified against docs.typesafe.ai/api; "probability" also accepted)
 *   box:    { "box": {"top", "bottom", "left", "right"}, "confidence"?: c }   (jev-1.14.0, verified live 2026-10-17)
 */
public with sharing class Gavel_ResponseParser {
    private static final Decimal TOLERANCE = 0.01;

    private class MismatchException extends Exception {
    }

    public static Gavel_JudgmentResponse parse(Gavel_JudgmentRequest req, String body) {
        Gavel_JudgmentResponse resp = new Gavel_JudgmentResponse();
        if (String.isBlank(body)) {
            return Gavel_JudgmentResponse.failure(Gavel_JudgmentResponse.INVALID_RESPONSE, null, 'empty_body');
        }
        Object root;
        try {
            root = JSON.deserializeUntyped(body);
        } catch (Exception e) {
            return Gavel_JudgmentResponse.failure(Gavel_JudgmentResponse.INVALID_RESPONSE, null, 'malformed_json');
        }
        if (!(root instanceof Map<String, Object>)) {
            return Gavel_JudgmentResponse.failure(Gavel_JudgmentResponse.INVALID_RESPONSE, null, 'not_an_object');
        }
        Map<String, Object> m = (Map<String, Object>) root;
        Object model = m.containsKey('model') ? m.get('model') : m.get('model_version');
        if (model instanceof String && String.isNotBlank((String) model)) {
            resp.modelVersion = (String) model;
        } else {
            resp.warnings.add('model_version_missing');
        }
        if (m.get('usage') instanceof Map<String, Object>) {
            resp.usage = (Map<String, Object>) m.get('usage');
        }

        Map<String, Map<String, Object>> byKey;
        try {
            byKey = indexAnswers(m.containsKey('answers') ? m.get('answers') : m.get('results'));
        } catch (MismatchException e) {
            return Gavel_JudgmentResponse.failure(Gavel_JudgmentResponse.INVALID_RESPONSE, null, 'answers_malformed');
        }
        if (byKey == null) {
            return Gavel_JudgmentResponse.failure(Gavel_JudgmentResponse.INVALID_RESPONSE, null, 'answers_missing');
        }

        Map<String, Gavel_Answer> answers = new Map<String, Gavel_Answer>();
        Set<String> asked = new Set<String>();
        try {
            for (Gavel_Question q : req.questions) {
                asked.add(q.key);
                Map<String, Object> raw = byKey.get(q.key);
                if (raw == null) {
                    answers.put(q.key, Gavel_Answer.invalid(q.key, q.questionType));
                    resp.warnings.add('missing_answer:' + q.key);
                    continue;
                }
                Gavel_Answer a;
                if (q.isChoice()) {
                    a = parseChoice(q, raw);
                } else if (q.isScore()) {
                    a = parseScore(q, raw);
                } else if (q.isBox()) {
                    a = parseBox(q, raw);
                } else {
                    a = parseNoul(q, raw);
                }
                answers.put(q.key, a);
            }
        } catch (MismatchException e) {
            Gavel_JudgmentResponse mm = Gavel_JudgmentResponse.failure(Gavel_JudgmentResponse.CONTRACT_MISMATCH, null, e.getMessage());
            mm.modelVersion = resp.modelVersion;
            mm.warnings = resp.warnings;
            return mm;
        }
        for (String k : byKey.keySet()) {
            if (!asked.contains(k)) {
                resp.warnings.add('extra_answer:' + k);
            }
        }
        resp.status = Gavel_JudgmentResponse.OK;
        resp.answers = answers;
        return resp;
    }

    private static Map<String, Map<String, Object>> indexAnswers(Object raw) {
        if (raw == null) {
            return null;
        }
        Map<String, Map<String, Object>> byKey = new Map<String, Map<String, Object>>();
        if (raw instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) raw;
            for (String k : m.keySet()) {
                if (!(m.get(k) instanceof Map<String, Object>)) {
                    throw new MismatchException('answer_not_object');
                }
                byKey.put(k, (Map<String, Object>) m.get(k));
            }
            return byKey;
        }
        if (raw instanceof List<Object>) {
            for (Object o : (List<Object>) raw) {
                if (!(o instanceof Map<String, Object>)) {
                    throw new MismatchException('answer_not_object');
                }
                Map<String, Object> a = (Map<String, Object>) o;
                Object k = a.get('key');
                if (!(k instanceof String)) {
                    throw new MismatchException('answer_key_missing');
                }
                byKey.put((String) k, a);
            }
            return byKey;
        }
        throw new MismatchException('answers_not_collection');
    }

    private static Gavel_Answer parseChoice(Gavel_Question q, Map<String, Object> raw) {
        Gavel_Answer a = new Gavel_Answer();
        a.key = q.key;
        a.answerType = Gavel_Question.CHOICE;
        Object probsRaw = raw.containsKey('probabilities') ? raw.get('probabilities') : raw.get('distribution');
        if (probsRaw == null) {
            return Gavel_Answer.invalid(q.key, q.questionType);
        }
        if (!(probsRaw instanceof Map<String, Object>)) {
            throw new MismatchException('probabilities_not_object');
        }
        Map<String, Object> probs = (Map<String, Object>) probsRaw;
        Set<String> optionKeys = q.optionKeys();
        Map<String, Decimal> clean = new Map<String, Decimal>();
        Boolean hasNull = false;
        Decimal sum = 0;
        for (String k : probs.keySet()) {
            if (!optionKeys.contains(k)) {
                throw new MismatchException('unknown_option');
            }
            Object v = probs.get(k);
            if (v == null) {
                hasNull = true;
                continue;
            }
            Decimal p = unit(v, 'probability_out_of_range');
            clean.put(k, p);
            sum += p;
        }
        if (hasNull) {
            return Gavel_Answer.invalid(q.key, q.questionType);
        }
        for (String k : optionKeys) {
            if (!probs.containsKey(k)) {
                throw new MismatchException('option_missing');
            }
        }
        if (Math.abs(sum - 1) > TOLERANCE) {
            throw new MismatchException('probabilities_do_not_sum_to_one');
        }
        // Winner is the argmax; ties resolve to option order (deterministic).
        String best = null;
        Decimal bestP = -1;
        for (Gavel_Option o : q.options) {
            Decimal p = clean.get(o.key);
            if (p > bestP) {
                bestP = p;
                best = o.key;
            }
        }
        Object reported = raw.containsKey('choice') ? raw.get('choice') : raw.get('answer');
        if (reported != null) {
            if (!(reported instanceof String) || !optionKeys.contains((String) reported)) {
                throw new MismatchException('unknown_option');
            }
            if (clean.get((String) reported) < bestP) {
                a.choice = best;
            } else {
                a.choice = (String) reported;
            }
        } else {
            a.choice = best;
        }
        a.probabilities = clean;
        a.confidence = optionalUnit(raw.get('confidence'));
        return a;
    }

    private static Gavel_Answer parseScore(Gavel_Question q, Map<String, Object> raw) {
        Gavel_Answer a = new Gavel_Answer();
        a.key = q.key;
        a.answerType = Gavel_Question.SCORE;
        Object v = raw.containsKey('score') ? raw.get('score') : raw.get('value');
        if (v == null) {
            return Gavel_Answer.invalid(q.key, q.questionType);
        }
        Decimal s = toDecimal(v);
        Integer maxLevel = q.maxLevel();
        if (s < 0 || (maxLevel != null && s > maxLevel)) {
            throw new MismatchException('score_out_of_range');
        }
        a.score = s;
        a.confidence = optionalUnit(raw.get('confidence'));
        Object probsRaw = raw.get('probabilities');
        if (probsRaw != null) {
            if (!(probsRaw instanceof Map<String, Object>)) {
                throw new MismatchException('probabilities_not_object');
            }
            Set<String> allowed = q.optionKeys();
            for (Gavel_Option o : q.options) {
                if (o.level != null) {
                    allowed.add(String.valueOf(o.level));
                }
            }
            Map<String, Decimal> clean = new Map<String, Decimal>();
            Decimal sum = 0;
            Map<String, Object> probs = (Map<String, Object>) probsRaw;
            for (String k : probs.keySet()) {
                if (!allowed.contains(k)) {
                    throw new MismatchException('unknown_level');
                }
                Decimal p = unit(probs.get(k), 'probability_out_of_range');
                clean.put(k, p);
                sum += p;
            }
            if (Math.abs(sum - 1) > TOLERANCE) {
                throw new MismatchException('probabilities_do_not_sum_to_one');
            }
            a.probabilities = clean;
        }
        return a;
    }

    private static Gavel_Answer parseNoul(Gavel_Question q, Map<String, Object> raw) {
        Gavel_Answer a = new Gavel_Answer();
        a.key = q.key;
        a.answerType = Gavel_Question.NOUL;
        // TypeSafe returns "noul"; "probability" is accepted for older fixtures.
        Object v = raw.containsKey('noul') ? raw.get('noul') : (raw.containsKey('probability') ? raw.get('probability') : raw.get('p'));
        if (v == null) {
            return Gavel_Answer.invalid(q.key, q.questionType);
        }
        a.probability = unit(v, 'probability_out_of_range');
        return a;
    }

    private static Gavel_Answer parseBox(Gavel_Question q, Map<String, Object> raw) {
        Object b = raw.get('box');
        if (b == null) {
            return Gavel_Answer.invalid(q.key, q.questionType);
        }
        if (!(b instanceof Map<String, Object>)) {
            throw new MismatchException('box_not_object');
        }
        Map<String, Object> edges = (Map<String, Object>) b;
        Gavel_Answer a = new Gavel_Answer();
        a.key = q.key;
        a.answerType = Gavel_Question.BOX;
        a.box = new Map<String, Decimal>();
        for (String side : new List<String>{ 'top', 'bottom', 'left', 'right' }) {
            a.box.put(side, unit(edges.get(side), 'box_out_of_range'));
        }
        if (a.box.get('top') > a.box.get('bottom') || a.box.get('left') > a.box.get('right')) {
            throw new MismatchException('box_inverted');
        }
        a.confidence = optionalUnit(raw.get('confidence'));
        return a;
    }

    private static Decimal optionalUnit(Object v) {
        if (v == null) {
            return null;
        }
        return unit(v, 'confidence_out_of_range');
    }

    private static Decimal unit(Object v, String code) {
        if (v == null) {
            throw new MismatchException(code);
        }
        Decimal d = toDecimal(v);
        if (d < 0 || d > 1) {
            throw new MismatchException(code);
        }
        return d;
    }

    private static Decimal toDecimal(Object v) {
        if (v instanceof Decimal) {
            return (Decimal) v;
        }
        if (v instanceof Integer) {
            Decimal fromInt = (Integer) v;
            return fromInt;
        }
        if (v instanceof Long) {
            return Decimal.valueOf((Long) v);
        }
        if (v instanceof Double) {
            return Decimal.valueOf((Double) v);
        }
        throw new MismatchException('not_a_number');
    }
}
