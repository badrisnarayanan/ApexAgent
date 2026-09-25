import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

/**
 * One user → agent exchange (user bubble, tool calls, rich-text agent reply, errors).
 * Shared by the thread viewer and the message viewer. Colors come from the
 * --agent-primary custom property set by the parent.
 */
export default class ApexAgentMessageTurn extends NavigationMixin(LightningElement) {

    // Raw ApexAgentConversationLogService.MessageWrapper
    @api message;
    @api avatarUrl;
    // Hides the per-turn meta row + feedback badge and the record links — used when
    // the parent already shows them (message viewer summary bar).
    @api hideMeta = false;

    get _msg() {
        return this.message || {};
    }

    get showMeta() {
        return !this.hideMeta;
    }

    get hasAvatarUrl() {
        return !!this.avatarUrl;
    }

    get userName() {
        return this._msg.userName || 'User';
    }

    get userInput() {
        return this._msg.userInput || '';
    }

    get agentResponse() {
        return this._msg.agentResponse || '';
    }

    get agentName() {
        return this._msg.agentName || 'Agent';
    }

    get agentLetter() {
        return this.agentName.charAt(0).toUpperCase();
    }

    get hasAgentResponse() {
        return !!(this._msg.agentResponse && this._msg.agentResponse.trim());
    }

    get toolLogs() {
        return this._msg.toolLogs || [];
    }

    get toolCallCount() {
        return this._msg.toolCallCount || 0;
    }

    get hasToolCalls() {
        return this.toolCallCount > 0;
    }

    get hasToolExecution() {
        return this.toolLogs.some(t => t.executionMessage);
    }

    get errorLogs() {
        return (this._msg.errorLogs || []).map((el, i) => ({
            key:   `${this._msg.id}-err-${i}`,
            error: el.error || 'An error occurred'
        }));
    }

    get hasErrors() {
        return this.errorLogs.length > 0;
    }

    get isLoading() {
        return !this.hasAgentResponse && !this.hasErrors;
    }

    get hasCost() {
        return this._msg.cost != null;
    }

    get costFormatted() {
        return this.hasCost ? '$' + Number(this._msg.cost).toFixed(3) : '';
    }

    get hasDuration() {
        return this._msg.durationMs != null;
    }

    get durationFormatted() {
        return this.hasDuration ? (this._msg.durationMs / 1000).toFixed(1) + 's' : '';
    }

    get formattedStartTime() {
        return this._formatTime(this._msg.startedAt);
    }

    get formattedEndTime() {
        return this._formatTime(this._msg.endedAt);
    }

    get hasFeedback() {
        return this.showMeta && !!this._msg.feedback;
    }

    get _isThumbsUp() {
        return this._msg.feedback === 'Thumbs Up';
    }

    get feedbackIcon() {
        return this._isThumbsUp ? 'utility:like' : 'utility:dislike';
    }

    get feedbackClass() {
        return 'feedback-badge ' + (this._isThumbsUp ? 'feedback-badge--up' : 'feedback-badge--down');
    }

    get feedbackNotes() {
        return this._msg.feedbackNotes || '';
    }

    handleOpenRecord() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId:   this._msg.id,
                actionName: 'view'
            }
        });
    }

    _formatTime(ts) {
        if (!ts) return '';
        try {
            return new Intl.DateTimeFormat(undefined, {
                month:  'short',
                day:    'numeric',
                year:   'numeric',
                hour:   'numeric',
                minute: '2-digit'
            }).format(new Date(ts));
        } catch {
            return '';
        }
    }
}
