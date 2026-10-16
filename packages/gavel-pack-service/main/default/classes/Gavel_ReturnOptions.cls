/**
 * Runtime options for Gavel_Return_Triage. The return policy is enforced here, in code; Jev only judges the
 * request within it. Option_Source__c = "Gavel_ReturnOptions:<window days>:<refund limit>" (default 30 and 500).
 *  - bought more than <window> days ago: refund and replace are not offered;
 *  - purchase date unknown: refund and replace can be chosen but always go to review;
 *  - price above the refund limit, or unknown: refund can be chosen but always goes to review;
 *  - the latest Gavel_Return_Photo_Check on the Case found the photo does not match the claim, or shows no
 *    damage: refund and replace can be chosen but always go to review. Run the photo check first.
 * Options are the question's own Gavel_Option__mdt rows. Reads the Case's Asset WITH USER_MODE.
 */
public with sharing class Gavel_ReturnOptions implements Gavel_OptionSource {
    public static final Integer DEFAULT_WINDOW_DAYS = 30;
    public static final Decimal DEFAULT_REFUND_LIMIT = 500;
    public static final String REFUND = 'refund';
    public static final String REPLACE = 'replace';

    public List<Gavel_Option> options(Id recordId, Gavel_Definition def, Gavel_Question question, Map<String, Object> state) {
        List<String> args = question.optionSource.contains(':') ? question.optionSource.substringAfter(':').split(':') : new List<String>();
        Integer windowDays = args.size() > 0 && args[0].trim().isNumeric() ? Integer.valueOf(args[0].trim()) : DEFAULT_WINDOW_DAYS;
        Decimal refundLimit = args.size() > 1 && args[1].trim().isNumeric() ? Decimal.valueOf(args[1].trim()) : DEFAULT_REFUND_LIMIT;

        Date purchased = null;
        Decimal price = null;
        if (recordId != null) {
            List<Case> rows = [SELECT Asset.PurchaseDate, Asset.Price FROM Case WHERE Id = :recordId WITH USER_MODE LIMIT 1];
            if (!rows.isEmpty() && rows[0].Asset != null) {
                purchased = rows[0].Asset.PurchaseDate;
                price = rows[0].Asset.Price;
            }
        }
        Boolean outsideWindow = purchased != null && purchased.daysBetween(Date.today()) > windowDays;
        Boolean photoFlagged = recordId != null && new PhotoCheck().isFlagged(recordId);

        List<Gavel_Option> result = new List<Gavel_Option>();
        for (Gavel_Option o : question.options) {
            Boolean money = o.key == REFUND || o.key == REPLACE;
            if (money && outsideWindow) {
                continue;
            }
            Gavel_Option copy = new Gavel_Option(o.key, o.label);
            copy.description = o.description;
            copy.sortOrder = o.sortOrder;
            copy.isEscape = o.isEscape == true || (money && (purchased == null || photoFlagged)) || (o.key == REFUND && (price == null || price > refundLimit));
            result.add(copy);
        }
        return result;
    }

    /** Ledger rows are private to Gavel, so they are read without sharing, as Gavel_Ledger does. */
    private without sharing class PhotoCheck {
        public Boolean isFlagged(Id caseId) {
            List<Gavel_Decision_Log__c> rows = [
                SELECT Answers_JSON__c FROM Gavel_Decision_Log__c
                WHERE Case__c = :caseId AND Definition__c = 'Gavel_Return_Photo_Check' AND Provider_Status__c = 'ok'
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (rows.isEmpty() || String.isBlank(rows[0].Answers_JSON__c)) {
                return false;
            }
            Object doc = JSON.deserializeUntyped(rows[0].Answers_JSON__c);
            Object outcomes = doc instanceof Map<String, Object> ? ((Map<String, Object>) doc).get('outcomes') : null;
            if (!(outcomes instanceof Map<String, Object>)) {
                return false;
            }
            for (String key : new List<String>{ 'matches_claim', 'damage_visible' }) {
                Object q = ((Map<String, Object>) outcomes).get(key);
                if (q instanceof Map<String, Object> && ((Map<String, Object>) q).get('answer') == 'false') {
                    return true;
                }
            }
            return false;
        }
    }
}
