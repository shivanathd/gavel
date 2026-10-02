/**
 * Runtime options for a choice question whose Gavel_Question__mdt.Option_Source__c names this class
 * (for example Knowledge article candidates). Must read WITH USER_MODE. Called before the callout.
 */
public interface Gavel_OptionSource {
    List<Gavel_Option> options(Id recordId, Gavel_Definition def, Gavel_Question question, Map<String, Object> state);
}
