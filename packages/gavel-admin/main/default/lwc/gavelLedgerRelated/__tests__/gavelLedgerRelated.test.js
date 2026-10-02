import { createElement } from 'lwc';
import GavelLedgerRelated from 'c/gavelLedgerRelated';
import entriesForRecord from '@salesforce/apex/Gavel_LedgerController.entriesForRecord';

jest.mock(
    '@salesforce/apex/Gavel_LedgerController.entriesForRecord',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

const ROWS = [
    { Id: 'a01', Name: 'GDL-0000001', Definition__c: 'Gavel_Case_Triage', Version__c: 1, Mode__c: 'Shadow', Outcome__c: 'AUTO', Reason__c: 'accepted', Top_Choice__c: 'BILLING', Top_Confidence__c: 0.82 },
    { Id: 'a02', Name: 'GDL-0000002', Definition__c: 'Gavel_Case_Urgency', Version__c: 1, Mode__c: 'Shadow', Outcome__c: 'PENDING', Reason__c: 'queued' }
];

const flush = () => Promise.resolve();

describe('c-gavel-ledger-related', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function mount() {
        const el = createElement('c-gavel-ledger-related', { is: GavelLedgerRelated });
        el.recordId = '500000000000001AAA';
        document.body.appendChild(el);
        return el;
    }

    it('renders ledger rows with outcome styling and pending notice', async () => {
        const el = mount();
        entriesForRecord.emit(ROWS);
        await flush();
        const table = el.shadowRoot.querySelector('lightning-datatable');
        expect(table).not.toBeNull();
        expect(table.data).toHaveLength(2);
        expect(table.data[0].outcomeClass).toBe('slds-text-color_success');
        expect(el.shadowRoot.querySelector('.gavel-pending').textContent).toContain('1 decision');
        expect(el.shadowRoot.querySelector('lightning-card').title).toBe('Gavel decisions (2)');
    });

    it('shows an empty state when there are no decisions', async () => {
        const el = mount();
        entriesForRecord.emit([]);
        await flush();
        expect(el.shadowRoot.querySelector('lightning-datatable')).toBeNull();
        expect(el.shadowRoot.querySelector('.gavel-empty')).not.toBeNull();
    });

    it('shows the server error message', async () => {
        const el = mount();
        entriesForRecord.error({ message: 'Ledger access required' });
        await flush();
        expect(el.shadowRoot.querySelector('.gavel-error').textContent).toBe('Ledger access required');
    });
});
