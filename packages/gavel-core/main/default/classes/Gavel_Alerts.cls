/**
 * Collects Gavel_Alert__e events during a transaction and publishes them at the end, after any callouts.
 */
public without sharing class Gavel_Alerts {
    public static final String INFO = 'info';
    public static final String WARNING = 'warning';
    public static final String CRITICAL = 'critical';

    @TestVisible
    private static List<Gavel_Alert__e> pending = new List<Gavel_Alert__e>();
    @TestVisible
    private static List<Gavel_Alert__e> published = new List<Gavel_Alert__e>();

    public static void raise(String alertType, String severity, String definition, String message) {
        for (Gavel_Alert__e a : pending) {
            if (a.Type__c == alertType && a.Definition__c == definition) {
                return; // one alert per type and definition per transaction
            }
        }
        pending.add(new Gavel_Alert__e(
            Type__c = alertType,
            Severity__c = severity,
            Definition__c = definition,
            Message__c = message == null ? null : message.abbreviate(255)
        ));
    }

    public static void flush() {
        if (pending.isEmpty()) {
            return;
        }
        List<Gavel_Alert__e> toSend = pending;
        pending = new List<Gavel_Alert__e>();
        try {
            EventBus.publish(toSend);
            published.addAll(toSend);
        } catch (Exception e) {
            // Alerts must never break the business transaction.
            published.addAll(new List<Gavel_Alert__e>());
        }
    }

    @TestVisible
    private static Boolean wasRaised(String alertType) {
        for (Gavel_Alert__e a : published) {
            if (a.Type__c == alertType) {
                return true;
            }
        }
        for (Gavel_Alert__e a : pending) {
            if (a.Type__c == alertType) {
                return true;
            }
        }
        return false;
    }
}
