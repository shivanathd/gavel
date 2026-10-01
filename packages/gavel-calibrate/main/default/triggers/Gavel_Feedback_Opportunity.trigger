trigger Gavel_Feedback_Opportunity on Opportunity(after update) {
    Gavel_FeedbackCapture.onRecordUpdate(Trigger.new, Trigger.oldMap);
}
