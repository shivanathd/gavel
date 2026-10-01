import { createElement } from 'lwc';
import GavelDecisionConsole from 'c/gavelDecisionConsole';
import listDefinitions from '@salesforce/apex/Gavel_AdminController.listDefinitions';
import opsStatus from '@salesforce/apex/Gavel_AdminController.opsStatus';
import changeMode from '@salesforce/apex/Gavel_AdminController.changeMode';
const SHOW_TOAST = 'lightning__showtoast';

jest.mock(
    '@salesforce/apex/Gavel_AdminController.listDefinitions',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/Gavel_AdminController.opsStatus',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock('@salesforce/apex/Gavel_AdminController.changeMode', () => ({ default: jest.fn() }), { virtual: true });

const DEFINITIONS = [
    { apiName: 'Gavel_Case_Triage', pack: 'service', targetObject: 'Case', version: 1, mode: 'Shadow', model: 'jev-1.13.0', dailyBudgetCalls: 5000, stateFields: ['Subject (strict)'], valid: true, errors: [], hashMismatch: false },
    { apiName: 'Gavel_Opt_Out_Detect', pack: 'sales-marketing', targetObject: 'EmailMessage', version: 2, mode: 'Live', model: 'jev-1.13.0', dailyBudgetCalls: null, stateFields: [], valid: false, errors: ['definition_hash_mismatch'], hashMismatch: true }
];

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('c-gavel-decision-console', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function mount() {
        const el = createElement('c-gavel-decision-console', { is: GavelDecisionConsole });
        document.body.appendChild(el);
        return el;
    }

    it('lists definitions with mode, budget and health', async () => {
        const el = mount();
        listDefinitions.emit(DEFINITIONS);
        opsStatus.emit({ egressEnabled: false, breakerState: 'CLOSED' });
        await flush();
        const rows = el.shadowRoot.querySelectorAll('.gavel-row');
        expect(rows).toHaveLength(2);
        expect(rows[0].querySelector('.gavel-mode').textContent).toBe('Shadow');
        expect(rows[1].textContent).toContain('Unlimited');
        expect(el.shadowRoot.querySelector('.gavel-egress')).not.toBeNull();
        expect(el.shadowRoot.querySelector('.gavel-hash').textContent).toContain('Gavel_Opt_Out_Detect');
        expect(el.shadowRoot.querySelector('.gavel-breaker')).toBeNull();
        expect(el.shadowRoot.querySelector('.gavel-promote')).not.toBeNull();
        expect(el.shadowRoot.querySelector('.gavel-demote')).not.toBeNull();
    });

    it('explains a refused promotion', async () => {
        changeMode.mockResolvedValue({ accepted: false, reason: 'insufficient_calibration_sample' });
        const el = mount();
        listDefinitions.emit(DEFINITIONS);
        opsStatus.emit({ egressEnabled: true, breakerState: 'OPEN' });
        await flush();
        const toast = jest.fn();
        el.addEventListener(SHOW_TOAST, toast);
        el.shadowRoot.querySelector('.gavel-promote').click();
        await flush();
        expect(changeMode).toHaveBeenCalledWith({ definition: 'Gavel_Case_Triage', mode: 'Live' });
        expect(toast).toHaveBeenCalledTimes(1);
        expect(toast.mock.calls[0][0].detail.variant).toBe('warning');
        expect(toast.mock.calls[0][0].detail.message).toContain('Not enough labeled entries');
        expect(el.shadowRoot.querySelector('.gavel-breaker')).not.toBeNull();
    });

    it('reports an accepted change and errors', async () => {
        changeMode.mockResolvedValueOnce({ accepted: true, reason: 'deploy_enqueued' });
        changeMode.mockRejectedValueOnce({ body: { message: 'The Gavel_Manage permission is required.' } });
        const el = mount();
        listDefinitions.emit(DEFINITIONS);
        await flush();
        const toast = jest.fn();
        el.addEventListener(SHOW_TOAST, toast);
        el.shadowRoot.querySelector('.gavel-demote').click();
        await flush();
        expect(toast.mock.calls[0][0].detail.variant).toBe('success');
        el.shadowRoot.querySelector('.gavel-demote').click();
        await flush();
        expect(toast.mock.calls[1][0].detail.variant).toBe('error');
        expect(toast.mock.calls[1][0].detail.message).toContain('Gavel_Manage');
    });

    it('shows load errors and an empty state', async () => {
        const el = mount();
        listDefinitions.error({ message: 'boom' });
        await flush();
        expect(el.shadowRoot.querySelector('.gavel-error').textContent).toBe('boom');
        expect(el.shadowRoot.querySelector('.gavel-empty')).not.toBeNull();
    });
});
