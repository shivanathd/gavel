/**
 * Derived state value for a Gavel_State_Field__mdt row whose Source__c names an Apex class
 * ("Class" or "Class:arg"). Implementations MUST read with WITH USER_MODE and return null when
 * the running user cannot see the data. Return a String, Number, Boolean, Gavel_ImageAsset or null.
 * Throw Gavel_SkipException to end the run as SKIP with a reason when a required value cannot be sent.
 */
public interface Gavel_StateSource {
    Object resolve(Gavel_StateContext ctx);
}
