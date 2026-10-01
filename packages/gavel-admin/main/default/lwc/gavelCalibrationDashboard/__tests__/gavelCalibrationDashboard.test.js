import { createElement } from 'lwc';
import GavelCalibrationDashboard from 'c/gavelCalibrationDashboard';
import listDefinitions from '@salesforce/apex/Gavel_AdminController.listDefinitions';
import latestCalibration from '@salesforce/apex/Gavel_AdminController.latestCalibration';
import disagreement from '@salesforce/apex/Gavel_AdminController.disagreement';
import runCalibration from '@salesforce/apex/Gavel_AdminController.runCalibration';

jest.mock(
    '@salesforce/apex/Gavel_AdminController.listDefinitions',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock('@salesforce/apex/Gavel_AdminController.latestCalibration', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/Gavel_AdminController.disagreement', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/Gavel_AdminController.runCalibration', () => ({ default: jest.fn() }), { virtual: true });

const SHOW_TOAST = 'lightning__showtoast';
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

const REPORT = {
    Recommendation_Status__c: 'recommended',
    Recommended_Auto_Accept__c: 0.8,
    Precision_At_Recommended__c: 0.96,
    Coverage_At_Recommended__c: 0.6,
    Wilson_Lower__c: 0.9314,
    Wilson_Upper__c: 0.977,
    Labeled_Count__c: 500,
    Question_Key__c: 'category',
    Report_JSON__c: JSON.stringify({
        questions: [
            {
                questionKey: 'category',
                reliability: [
                    { lower: 0.6, upper: 0.7, n: 150, observed: 0.5, lowSample: false },
                    { lower: 0.8, upper: 0.9, n: 30, observed: 0.96, lowSample: true }
                ]
            }
        ]
    })
};

const SHADOW = JSON.stringify({
    questions: {
        category: { questionKey: 'category', sampleSize: 300, agreementRate: 0.7, wouldAuto: 150, wouldAutoShare: 0.5, missing: 0, unmapped: 75, topDisagreements: [{ gavel: 'TECHNICAL', baseline: 'BILLING', count: 15 }] }
    }
});

describe('c-gavel-calibration-dashboard', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function mount() {
        const el = createElement('c-gavel-calibration-dashboard', { is: GavelCalibrationDashboard });
        document.body.appendChild(el);
        return el;
    }

    it('shows the recommendation, interval, reliability bins and shadow agreement', async () => {
        latestCalibration.mockResolvedValue(REPORT);
        disagreement.mockResolvedValue(SHADOW);
        const el = mount();
        listDefinitions.emit([{ apiName: 'Gavel_Case_Triage', mode: 'Shadow' }]);
        await flush();
        expect(latestCalibration).toHaveBeenCalledWith({ definition: 'Gavel_Case_Triage' });
        expect(el.shadowRoot.querySelector('.gavel-recommended').textContent).toContain('Auto accept at 0.8');
        expect(el.shadowRoot.querySelector('.gavel-recommended').textContent).toContain('93.1% to 97.7%');
        expect(el.shadowRoot.querySelectorAll('.gavel-bins tbody tr')).toHaveLength(2);
        expect(el.shadowRoot.querySelector('.gavel-bins').textContent).toContain('low sample');
        const shadow = el.shadowRoot.querySelector('.gavel-shadow-row').textContent;
        expect(shadow).toContain('agreement 70.0%');
        expect(shadow).toContain('TECHNICAL vs BILLING: 15');
    });

    it('handles no report, errors and running calibration', async () => {
        latestCalibration.mockResolvedValue(null);
        disagreement.mockResolvedValue(JSON.stringify({ questions: {} }));
        runCalibration.mockResolvedValue('707000000000001');
        const el = mount();
        listDefinitions.emit([{ apiName: 'Gavel_Lead_Quality', mode: 'Shadow' }]);
        await flush();
        expect(el.shadowRoot.querySelector('.gavel-noreport')).not.toBeNull();
        const toast = jest.fn();
        el.addEventListener(SHOW_TOAST, toast);
        el.shadowRoot.querySelector('.gavel-run').click();
        await flush();
        expect(runCalibration).toHaveBeenCalledWith({ definition: 'Gavel_Lead_Quality' });
        expect(toast.mock.calls[0][0].detail.variant).toBe('success');

        latestCalibration.mockRejectedValue({ body: { message: 'No access' } });
        el.shadowRoot.querySelector('.gavel-picker').dispatchEvent(new CustomEvent('change', { detail: { value: 'Other' } }));
        await flush();
        expect(el.shadowRoot.querySelector('.gavel-error').textContent).toBe('No access');

        runCalibration.mockRejectedValue({ body: { message: 'The Gavel_Manage permission is required.' } });
        el.shadowRoot.querySelector('.gavel-run').click();
        await flush();
        expect(toast.mock.calls[1][0].detail.variant).toBe('error');
    });
});
