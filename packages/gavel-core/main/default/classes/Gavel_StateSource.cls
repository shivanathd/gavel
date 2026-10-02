/**
 * Derived state value for a Gavel_State_Field__mdt row whose Source__c names an Apex class
 * ("Class" or "Class:arg"). Implementations MUST read with WITH USER_MODE and return null when
 * the running user cannot see the data. Return a String, Number, Boolean or null.
 */
public interface Gavel_StateSource {
    Object resolve(Gavel_StateContext ctx);
}
