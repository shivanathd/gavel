import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import listDefinitions from '@salesforce/apex/Gavel_AdminController.listDefinitions';
import opsStatus from '@salesforce/apex/Gavel_AdminController.opsStatus';
import changeMode from '@salesforce/apex/Gavel_AdminController.changeMode';

const REASONS = {
    insufficient_calibration_sample: 'Not enough labeled entries yet. Keep it in Shadow and run calibration.',
    no_calibration_report: 'Run calibration first.',
    calibration_report_stale: 'The calibration report is older than the allowed age. Run calibration again.',
    no_threshold_meets_target: 'No threshold meets the target precision. Keep it in Shadow.',
    model_alias_not_allowed_live: 'Live needs a pinned model version, not an alias.',
    definition_hash_mismatch: 'The definition changed without a version bump.',
    deploy_enqueued: 'Mode change deploy started.'
};

/**
 * Decision Console: every definition with its mode, version, health and promotion controls.
 * Promotion to Live is gated by calibration (SHAD-001.5); the server enforces it, this UI only explains it.
 */
export default class GavelDecisionConsole extends LightningElement {
    definitions = [];
    status;
    error;
    busy = false;
    wiredDefinitions;

    @wire(listDefinitions)
    wiredList(result) {
        this.wiredDefinitions = result;
        if (result.data) {
            this.definitions = result.data.map((d) => ({
                ...d,
                key: d.apiName,
                isLive: d.mode === 'Live',
                isShadow: d.mode === 'Shadow',
                healthLabel: d.valid ? 'Valid' : (d.errors || []).join(', '),
                healthClass: d.valid ? 'slds-text-color_success' : 'slds-text-color_error',
                fields: (d.stateFields || []).join(', '),
                budgetLabel: d.dailyBudgetCalls === null || d.dailyBudgetCalls === undefined ? 'Unlimited (set a budget)' : `${d.dailyBudgetCalls} / day`
            }));
            this.error = undefined;
        } else if (result.error) {
            this.definitions = [];
            this.error = this.message(result.error);
        }
    }

    @wire(opsStatus)
    wiredStatus({ data }) {
        if (data) {
            this.status = data;
        }
    }

    get egressOff() {
        return this.status && this.status.egressEnabled === false;
    }

    get breakerOpen() {
        return this.status && this.status.breakerState && this.status.breakerState !== 'CLOSED';
    }

    get hasDefinitions() {
        return this.definitions.length > 0;
    }

    get hashProblems() {
        return this.definitions.filter((d) => d.hashMismatch).map((d) => d.apiName).join(', ');
    }

    async handleMode(event) {
        const apiName = event.target.dataset.name;
        const mode = event.target.dataset.mode;
        this.busy = true;
        try {
            const result = await changeMode({ definition: apiName, mode });
            const message = REASONS[result.reason] || result.reason;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: result.accepted ? `${apiName}: ${mode} requested` : `${apiName} stays ${this.modeOf(apiName)}`,
                    message,
                    variant: result.accepted ? 'success' : 'warning'
                })
            );
            if (result.accepted) {
                await refreshApex(this.wiredDefinitions);
            }
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Mode change failed', message: this.message(e), variant: 'error' }));
        } finally {
            this.busy = false;
        }
    }

    modeOf(apiName) {
        const d = this.definitions.find((x) => x.apiName === apiName);
        return d ? d.mode : '';
    }

    message(e) {
        return e && e.body && e.body.message ? e.body.message : 'Unexpected error';
    }
}
