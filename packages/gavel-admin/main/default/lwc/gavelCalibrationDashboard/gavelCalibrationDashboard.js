import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import listDefinitions from '@salesforce/apex/Gavel_AdminController.listDefinitions';
import latestCalibration from '@salesforce/apex/Gavel_AdminController.latestCalibration';
import disagreement from '@salesforce/apex/Gavel_AdminController.disagreement';
import runCalibration from '@salesforce/apex/Gavel_AdminController.runCalibration';

const pct = (v) => (v === null || v === undefined ? '-' : `${(Number(v) * 100).toFixed(1)}%`);

/**
 * Calibration dashboard (F8) and shadow comparison (F7) for one definition.
 * Thresholds are recommendations: an admin applies them through a deploy that bumps the version (ADR-012).
 * Agreement with the baseline is shown as agreement, never as accuracy.
 */
export default class GavelCalibrationDashboard extends LightningElement {
    @api definitionApiName;
    options = [];
    report;
    shadow;
    error;
    loading = false;

    @wire(listDefinitions)
    wiredDefinitions({ data }) {
        if (data) {
            this.options = data.map((d) => ({ label: `${d.apiName} (${d.mode})`, value: d.apiName }));
            if (!this.definitionApiName && this.options.length) {
                this.select(this.options[0].value);
            } else if (this.definitionApiName && !this.report) {
                this.select(this.definitionApiName);
            }
        }
    }

    handleChange(event) {
        this.select(event.detail.value);
    }

    async select(apiName) {
        this.definitionApiName = apiName;
        this.loading = true;
        this.error = undefined;
        try {
            const [rep, dis] = await Promise.all([latestCalibration({ definition: apiName }), disagreement({ definition: apiName })]);
            this.report = rep ? this.toReport(rep) : null;
            this.shadow = dis ? this.toShadow(JSON.parse(dis)) : null;
        } catch (e) {
            this.error = e && e.body && e.body.message ? e.body.message : 'Unable to load calibration.';
        } finally {
            this.loading = false;
        }
    }

    toReport(rep) {
        let bins = [];
        try {
            const doc = JSON.parse(rep.Report_JSON__c || '{}');
            const q = (doc.questions || []).find((x) => x.questionKey === rep.Question_Key__c) || (doc.questions || [])[0];
            bins = q ? q.reliability.map((b) => ({
                key: `${b.lower}`,
                range: `${Number(b.lower).toFixed(1)} - ${Number(b.upper).toFixed(1)}`,
                n: b.n,
                observed: pct(b.observed),
                flag: b.lowSample ? 'low sample' : ''
            })) : [];
        } catch (e) {
            bins = [];
        }
        return {
            status: rep.Recommendation_Status__c,
            recommended: rep.Recommended_Auto_Accept__c,
            precision: pct(rep.Precision_At_Recommended__c),
            coverage: pct(rep.Coverage_At_Recommended__c),
            interval: `${pct(rep.Wilson_Lower__c)} to ${pct(rep.Wilson_Upper__c)}`,
            labeled: rep.Labeled_Count__c,
            question: rep.Question_Key__c,
            generated: rep.Generated_At__c,
            meetsTarget: rep.Recommendation_Status__c === 'recommended',
            bins
        };
    }

    toShadow(doc) {
        const questions = Object.values(doc.questions || {}).map((q) => ({
            key: q.questionKey,
            sample: q.sampleSize,
            agreement: pct(q.agreementRate),
            wouldAuto: `${q.wouldAuto} (${pct(q.wouldAutoShare)})`,
            missing: q.missing,
            unmapped: q.unmapped,
            pairs: (q.topDisagreements || []).map((p) => `${p.gavel} vs ${p.baseline}: ${p.count}`).join('; ')
        }));
        return { questions, hasQuestions: questions.length > 0 };
    }

    get hasReport() {
        return !!this.report;
    }

    async handleRun() {
        try {
            await runCalibration({ definition: this.definitionApiName });
            this.dispatchEvent(new ShowToastEvent({ title: 'Calibration started', message: 'Refresh in a minute to see the new report.', variant: 'success' }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Calibration failed', message: e && e.body ? e.body.message : 'Unexpected error', variant: 'error' }));
        }
    }
}
