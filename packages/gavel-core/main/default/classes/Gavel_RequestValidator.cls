/**
 * Validates a request before any callout (F1 "On Invalid Input"). Returns an error code or null.
 */
public with sharing class Gavel_RequestValidator {
    public static final Integer MAX_STATE_CHARS = 150000;

    public static String validate(Gavel_JudgmentRequest req) {
        if (req == null) {
            return 'request_missing';
        }
        if (String.isBlank(req.definitionApiName)) {
            return 'definition_missing';
        }
        if (req.definitionVersion == null || req.definitionVersion < 1) {
            return 'invalid_version';
        }
        if (String.isBlank(req.model)) {
            return 'model_missing';
        }
        if (req.live == true && Gavel_DefinitionValidator.isModelAlias(req.model)) {
            return 'model_alias_not_allowed_live';
        }
        if (req.state == null) {
            return 'state_missing';
        }
        if (req.canonicalState().length() > MAX_STATE_CHARS) {
            return 'state_too_large';
        }
        if (req.hasImages()) {
            for (Gavel_ImageAsset img : req.assets) {
                // Match the digest: JSON may escape the reference's angle brackets.
                if (img == null || img.data == null || img.data.size() == 0 || !req.canonicalState().contains(img.reference.substringBetween(':', '>'))) {
                    return 'image_not_referenced';
                }
                if (!img.hasSupportedSize()) {
                    return 'image_size_unsupported';
                }
            }
        }
        if (req.timeoutMs != null && (req.timeoutMs < 1 || req.timeoutMs > 60000)) {
            return 'timeout_out_of_range';
        }
        if (req.questions == null || req.questions.isEmpty() || req.questions.size() > 64) {
            return 'question_count_out_of_range';
        }
        Set<String> keys = new Set<String>();
        for (Gavel_Question q : req.questions) {
            if (q.key == null || !Gavel_DefinitionValidator.KEY_PATTERN.matcher(q.key).matches()) {
                return 'invalid_question_key';
            }
            if (keys.contains(q.key)) {
                return 'duplicate_question_key';
            }
            keys.add(q.key);
            if (!q.isChoice() && !q.isScore() && !q.isNoul() && !q.isBox()) {
                return 'invalid_question_type';
            }
            if (String.isBlank(q.prompt)) {
                return 'empty_prompt';
            }
            // Runtime options are resolved by now, so check them as static options.
            Gavel_Question resolved = q.cloneWithOptions(q.options);
            resolved.optionSource = null;
            Gavel_DefinitionValidator.Result r = new Gavel_DefinitionValidator.Result();
            Gavel_DefinitionValidator.validateOptions(resolved, r);
            if (!r.valid) {
                return r.firstError();
            }
        }
        return null;
    }
}
