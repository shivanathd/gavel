import { LightningElement, api, wire } from 'lwc';
import entriesForRecord from '@salesforce/apex/Gavel_LedgerController.entriesForRecord';

const COLUMNS = [
    { label: 'Entry', fieldName: 'Name', type: 'text' },
    { label: 'Definition', fieldName: 'Definition__c', type: 'text' },
    { label: 'Version', fieldName: 'Version__c', type: 'number', initialWidth: 90 },
    { label: 'Mode', fieldName: 'Mode__c', type: 'text', initialWidth: 90 },
    { label: 'Outcome', fieldName: 'Outcome__c', type: 'text', initialWidth: 110, cellAttributes: { class: { fieldName: 'outcomeClass' } } },
    { label: 'Reason', fieldName: 'Reason__c', type: 'text' },
    { label: 'Answer', fieldName: 'Top_Choice__c', type: 'text' },
    { label: 'Confidence', fieldName: 'Top_Confidence__c', type: 'percent', typeAttributes: { maximumFractionDigits: 1 } },
    { label: 'Action', fieldName: 'Action_Taken__c', type: 'text' },
    { label: 'Run At', fieldName: 'Run_At__c', type: 'date', typeAttributes: { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' } }
];

const OUTCOME_CLASS = {
    AUTO: 'slds-text-color_success',
    REVIEW: 'slds-text-color_default',
    ESCALATE: 'slds-text-color_error',
    ERROR: 'slds-text-color_error',
    SKIP: 'slds-text-color_weak',
    PENDING: 'slds-text-color_weak'
};

/**
 * Every Gavel decision about this record, newest first (LEDG-001.6). Read-only: the ledger is immutable.
 */
export default class GavelLedgerRelated extends LightningElement {
    @api recordId;
    @api limitSize = 50;
    columns = COLUMNS;
    rows = [];
    error;

    @wire(entriesForRecord, { recordId: '$recordId', limitSize: '$limitSize' })
    wiredEntries({ data, error }) {
        if (data) {
            this.rows = data.map((row) => ({ ...row, outcomeClass: OUTCOME_CLASS[row.Outcome__c] || '' }));
            this.error = undefined;
        } else if (error) {
            this.rows = [];
            this.error = error.body && error.body.message ? error.body.message : 'Unable to load Gavel decisions.';
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get title() {
        return `Gavel decisions (${this.rows.length})`;
    }

    get pendingCount() {
        return this.rows.filter((r) => r.Outcome__c === 'PENDING').length;
    }

    get hasPending() {
        return this.pendingCount > 0;
    }
}
