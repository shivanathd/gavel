/**
 * Flow action "Gavel: Apply Outcome" (FLOW-001.3). Executes Gavel_Action_Map__mdt actions only for an AUTO
 * outcome of a Live definition whose actions were deferred by "Gavel: Run Decision". Shadow, REVIEW,
 * ESCALATE, SKIP and ERROR never act. Never throws.
 */
public with sharing class Gavel_ApplyOutcome {
    public class ApplyInput {
        @InvocableVariable(label='Ledger Id' required=true)
        public Id ledgerId;
    }

    public class ApplyOutput {
        @InvocableVariable(label='Applied')
        public Boolean applied;
        @InvocableVariable(label='Actions' description='What was applied, or why nothing was')
        public String actions;
    }

    @InvocableMethod(label='Gavel: Apply Outcome' description='Applies the action map for an AUTO outcome on a Live definition.' category='Gavel')
    public static List<ApplyOutput> apply(List<ApplyInput> inputs) {
        List<ApplyOutput> outputs = new List<ApplyOutput>();
        if (inputs == null) {
            return outputs;
        }
        try {
            List<Id> ids = new List<Id>();
            for (ApplyInput i : inputs) {
                ids.add(i == null ? null : i.ledgerId);
            }
            for (Gavel_Runtime.ApplyResult r : Gavel_Runtime.applyOutcome(ids)) {
                ApplyOutput o = new ApplyOutput();
                o.applied = r.applied;
                o.actions = r.actions;
                outputs.add(o);
            }
        } catch (Exception e) {
            outputs.clear();
            for (Integer i = 0; i < inputs.size(); i++) {
                ApplyOutput o = new ApplyOutput();
                o.applied = false;
                o.actions = 'error:' + e.getTypeName();
                outputs.add(o);
            }
        }
        return outputs;
    }
}
