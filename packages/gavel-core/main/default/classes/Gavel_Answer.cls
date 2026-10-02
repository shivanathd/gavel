/**
 * One typed answer after contract validation.
 */
public with sharing class Gavel_Answer {
    public static final String OK = 'ok';
    public static final String INVALID = 'invalid_response';

    public String key;
    public String answerType;
    public String status = OK;
    public String choice;
    public Decimal score;
    public Decimal probability;
    public Decimal confidence;
    public Map<String, Decimal> probabilities;

    public Boolean isValid() {
        return status == OK;
    }

    public static Gavel_Answer invalid(String key, String answerType) {
        Gavel_Answer a = new Gavel_Answer();
        a.key = key;
        a.answerType = answerType;
        a.status = INVALID;
        return a;
    }
}
