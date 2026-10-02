trigger Gavel_Feedback_Review on Gavel_Review__c(after update) {
    Gavel_FeedbackCapture.onReviewUpdate(Trigger.new, Trigger.oldMap);
}
