trigger Gavel_Feedback_Contact on Contact(after update) {
    Gavel_FeedbackCapture.onRecordUpdate(Trigger.new, Trigger.oldMap);
}
