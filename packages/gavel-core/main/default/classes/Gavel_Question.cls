/**
 * One typed ask inside a definition: choice, score or noul.
 * Shared by definitions (CMDT) and provider requests (contracts/provider-contract.md).
 */
public with sharing class Gavel_Question {
    public static final String CHOICE = 'choice';
    public static final String SCORE = 'score';
    public static final String NOUL = 'noul';

    public String key;
    public String questionType;
    public String prompt;
    public String instructions;
    public List<Gavel_Option> options = new List<Gavel_Option>();

    // Definition-only attributes (not sent to the provider)
    public Integer sortOrder;
    public Boolean requiredForAction = true;
    public String stage;
    public String optionSource;
    public String developerName;

    public Gavel_Question() {
    }

    public Gavel_Question(String key, String questionType, String prompt) {
        this.key = key;
        this.questionType = questionType;
        this.prompt = prompt;
    }

    public Boolean isChoice() {
        return questionType == CHOICE;
    }

    public Boolean isScore() {
        return questionType == SCORE;
    }

    public Boolean isNoul() {
        return questionType == NOUL;
    }

    public Gavel_Option findOption(String optionKey) {
        if (options == null || optionKey == null) {
            return null;
        }
        for (Gavel_Option o : options) {
            if (optionKey.equals(o.key)) {
                return o;
            }
        }
        return null;
    }

    public Set<String> optionKeys() {
        Set<String> keys = new Set<String>();
        if (options != null) {
            for (Gavel_Option o : options) {
                keys.add(o.key);
            }
        }
        return keys;
    }

    public Integer maxLevel() {
        Integer m = null;
        if (options != null) {
            for (Gavel_Option o : options) {
                if (o.level != null && (m == null || o.level > m)) {
                    m = o.level;
                }
            }
        }
        return m;
    }

    /** Copy used when runtime options (Option_Source__c) are added for a single run. */
    public Gavel_Question cloneWithOptions(List<Gavel_Option> newOptions) {
        Gavel_Question q = new Gavel_Question(key, questionType, prompt);
        q.instructions = instructions;
        q.options = newOptions;
        q.sortOrder = sortOrder;
        q.requiredForAction = requiredForAction;
        q.stage = stage;
        q.optionSource = optionSource;
        q.developerName = developerName;
        return q;
    }
}
