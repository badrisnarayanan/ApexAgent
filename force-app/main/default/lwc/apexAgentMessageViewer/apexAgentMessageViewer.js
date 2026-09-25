import { LightningElement, api } from 'lwc';
import getMessage from '@salesforce/apex/ApexAgentMessageViewerController.getMessage';

export default class ApexAgentMessageViewer extends LightningElement {

    @api recordId;
    _message;
    _loadError = false;

    // ── Lifecycle ──

    // Message logs aren't edited after they're written, so one load is enough.
    connectedCallback() {
        this._load();
    }

    // ── Data ──

    async _load() {
        if (!this.recordId) return;
        try {
            this._message   = await getMessage({ messageId: this.recordId });
            this._loadError = false;
        } catch {
            this._loadError = true;
        }
    }

    // ── State ──

    get message() {
        return this._message;
    }

    get hasMessage() {
        return !!this._message;
    }

    get showNotFound() {
        return !this._message && this._loadError;
    }

    get _hasResponse() {
        return !!(this._message?.agentResponse && this._message.agentResponse.trim());
    }

    get _hasErrors() {
        return (this._message?.errorLogs || []).length > 0;
    }

    get isInProgress() {
        return !!this._message && !this._hasResponse && !this._hasErrors;
    }

    // ── Agent theme ──

    get themeStyle() {
        const color = this._message?.agentPrimaryColor || '#0176D3';
        return `--agent-primary: ${color};`;
    }

    get agentAvatarUrl() {
        return this._message?.agentAvatarUrl || '';
    }

    // ── Summary bar ──

    get statusLabel() {
        if (this.isInProgress) return 'In progress';
        if (this._hasErrors) return this._hasResponse ? 'Completed with errors' : 'Failed';
        return 'Completed';
    }

    get statusClass() {
        let variant = 'status-pill--done';
        if (this.isInProgress) {
            variant = 'status-pill--progress';
        } else if (this._hasErrors) {
            variant = 'status-pill--error';
        }
        return `status-pill ${variant}`;
    }

    get statusIcon() {
        if (this.isInProgress) return 'utility:spinner';
        return this._hasErrors ? 'utility:error' : 'utility:success';
    }

    get modelName() {
        return this._message?.modelName || '';
    }

    get hasFeedback() {
        return !!this._message?.feedback;
    }

    get _isThumbsUp() {
        return this._message?.feedback === 'Thumbs Up';
    }

    get feedbackIcon() {
        return this._isThumbsUp ? 'utility:like' : 'utility:dislike';
    }

    get feedbackClass() {
        return 'summary-feedback ' + (this._isThumbsUp ? 'summary-feedback--up' : 'summary-feedback--down');
    }

    get feedbackLabel() {
        return this._isThumbsUp ? 'Helpful' : 'Not helpful';
    }

    get feedbackNotes() {
        return this._message?.feedbackNotes || '';
    }
}
