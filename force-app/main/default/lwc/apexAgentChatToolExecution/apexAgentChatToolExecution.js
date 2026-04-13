import { LightningElement, api, track } from 'lwc';

export default class ApexAgentChatToolExecution extends LightningElement {

    @api toolLogs = [];

    @track _isExpanded = false;

    @api
    get isExpanded() {
        return this._isExpanded;
    }
    set isExpanded(val) {
        this._isExpanded = val;
    }

    get toolCount() {
        return this.processedLogs.length;
    }

    get chevronIcon() {
        return this._isExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get ariaExpanded() {
        return String(this._isExpanded);
    }

    get processedLogs() {
        if (!this.toolLogs) return [];
        return this.toolLogs.reduce((acc, log, idx) => {
            const execMsg = log.executionMessage || '';
            if (!execMsg) return acc;
            const isInProgress = log.status === 'In Progress';
            acc.push({
                key:         `tool-${idx}`,
                displayText: execMsg,
                isInProgress,
                rowClass:    'tool-row' + (isInProgress ? ' tool-row--in-progress' : '')
            });
            return acc;
        }, []);
    }

    handleToggle() {
        this._isExpanded = !this._isExpanded;
        this.dispatchEvent(new CustomEvent('toggle', {
            detail: { isExpanded: this._isExpanded }
        }));
    }
}
