/**
 * One option of a choice or score question. Shared by definitions and provider requests.
 */
public with sharing class Gavel_Option {
    public String key;
    public String label;
    public String description;
    public Integer level;
    public Boolean isEscape = false;
    public Integer sortOrder;

    public Gavel_Option() {
    }

    public Gavel_Option(String key, String label) {
        this.key = key;
        this.label = label;
    }
}
