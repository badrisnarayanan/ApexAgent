import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import regenerateSchema from '@salesforce/apex/ApexAgentToolSchemaController.regenerateSchema';

/**
 * Headless quick action on the Agent Tool record page. Shows a toast the
 * moment it's clicked, then enqueues schema regeneration on the server —
 * generation itself always runs in ApexAgentToolSchemaRegenQueueable,
 * never on this synchronous request.
 */
export default class ApexAgentRegenerateToolSchema extends LightningElement {

    _recordId;

    // Quick actions don't receive recordId through connectedCallback — the
    // framework assigns it through this setter instead.
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
    }

    @api
    invoke() {
        this.dispatchEvent(new ShowToastEvent({
            title:   'Schema regeneration started',
            variant: 'info'
        }));

        regenerateSchema({ toolId: this._recordId })
        .catch((error) => {
            this.dispatchEvent(new ShowToastEvent({
                title:   'Failed to start schema regeneration',
                message: error?.body?.message,
                variant: 'error'
            }));
        });
    }
}
