import { LightningElement, api } from 'lwc';

const THUMBS_UP   = 'Thumbs Up';
const THUMBS_DOWN = 'Thumbs Down';

export default class ApexAgentChatMessage extends LightningElement {

    @api message = {};
    @api agentAvatarUrl;
    @api agentName;

    // ── Type checks ──

    get isUser() {
        return this.message && this.message.type === 'user';
    }

    get isAgent() {
        return this.message && (this.message.type === 'agent' || this.message.type === 'loading');
    }

    get isLoading() {
        return this.message && this.message.type === 'loading';
    }

    get isError() {
        return this.message && this.message.type === 'error';
    }

    // ── Avatar ──

    get hasAvatarUrl() {
        return !!this.agentAvatarUrl;
    }

    get avatarLetter() {
        return this.agentName ? this.agentName.charAt(0).toUpperCase() : 'A';
    }

    get agentBubbleClass() {
        return this.isLoading ? 'bubble bubble--agent bubble--agent-loading' : 'bubble bubble--agent';
    }

    // ── Tool logs ──

    get hasToolLogs() {
        return this.message &&
            this.message.toolLogs &&
            this.message.toolLogs.some(t => t.executionMessage);
    }

    // ── Timestamp ──

    get formattedTime() {
        const ts = this.isUser ? this.message.startedAt : this.message.endedAt;
        if (!ts) {
            return '';
        }
        try {
            return new Intl.DateTimeFormat(undefined, {
                month:  'short',
                day:    'numeric',
                year:   'numeric',
                hour:   'numeric',
                minute: '2-digit'
            }).format(new Date(ts));
        } catch (_err) {
            return '';
        }
    }

    // ── Feedback ──

    get showFeedback() {
        return !this.isLoading && this.isAgent && !!this.message.agentMessageUUID;
    }

    get isThumbsUp() {
        return String(this.message && this.message.feedback === THUMBS_UP);
    }

    get isThumbsDown() {
        return String(this.message && this.message.feedback === THUMBS_DOWN);
    }

    get thumbUpClass() {
        return 'feedback-btn' + (this.message && this.message.feedback === THUMBS_UP ? ' feedback-btn--active' : '');
    }

    get thumbDownClass() {
        return 'feedback-btn' + (this.message && this.message.feedback === THUMBS_DOWN ? ' feedback-btn--active' : '');
    }

    get thumbUpIconVariant() {
        return this.message && this.message.feedback === THUMBS_UP ? 'inverse' : '';
    }

    get thumbDownIconVariant() {
        return this.message && this.message.feedback === THUMBS_DOWN ? 'inverse' : '';
    }

    // ── Event handlers ──

    handleThumbsUp() {
        this.dispatchEvent(new CustomEvent('feedbackclick', {
            detail: {
                agentMessageUUID: this.message.agentMessageUUID,
                feedback:         THUMBS_UP,
                feedbackNotes:    this.message.feedbackNotes || ''
            },
            bubbles: true
        }));
    }

    handleThumbsDown() {
        this.dispatchEvent(new CustomEvent('feedbackclick', {
            detail: {
                agentMessageUUID: this.message.agentMessageUUID,
                feedback:         THUMBS_DOWN,
                feedbackNotes:    this.message.feedbackNotes || ''
            },
            bubbles: true
        }));
    }

    handleToolsToggle(event) {
        this.dispatchEvent(new CustomEvent('toolstoggle', {
            detail: {
                key:        this.message.key,
                isExpanded: event.detail.isExpanded
            },
            bubbles: true
        }));
    }
}