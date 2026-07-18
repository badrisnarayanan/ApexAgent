import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getThreadMessages from '@salesforce/apex/ApexAgentThreadViewerController.getThreadMessages';

const REFRESH_INTERVAL_MS = 5000;
const SCROLL_THRESHOLD_PX = 50;

export default class ApexAgentThreadViewer extends NavigationMixin(LightningElement) {

    @api recordId;
    @track _messages = [];
    _intervalId;
    _isAtBottom      = true;
    _hasNewMessages  = false;

    // ── Lifecycle ──

    connectedCallback() {
        this._isAtBottom     = true;
        this._hasNewMessages = false;
        this._load();
        // Skip polling while the tab is hidden — each poll queries the full thread
        // with subqueries, no point paying that cost when nobody can see the result.
        this._intervalId = setInterval(() => {
            if (document.visibilityState === 'visible') {
                this._load();
            }
        }, REFRESH_INTERVAL_MS);
    }

    disconnectedCallback() {
        clearInterval(this._intervalId);
    }

    // ── Data ──

    async _load() {
        if (!this.recordId) return;
        try {
            const prevCount = this._messages.length;
            const result    = await getThreadMessages({ threadId: this.recordId });
            this._messages  = result;
            if (result.length > prevCount) {
                if (this._isAtBottom) {
                    setTimeout(() => this._scrollToBottom(), 0);
                } else {
                    this._hasNewMessages = true;
                }
            }
        } catch {
            // silently swallow — keep showing last known state
        }
    }

    // ── Handlers ──

    handleRefresh() {
        this._load();
    }

    handleOpenRecord(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId:   event.currentTarget.dataset.id,
                actionName: 'view'
            }
        });
    }

    handleScroll(event) {
        const el = event.target;
        this._isAtBottom = el.scrollTop + el.clientHeight >= el.scrollHeight - SCROLL_THRESHOLD_PX;
        if (this._isAtBottom) {
            this._hasNewMessages = false;
        }
    }

    handleScrollToBottom() {
        this._scrollToBottom();
        this._hasNewMessages = false;
    }

    _scrollToBottom() {
        const el = this.template.querySelector('.msg-list');
        if (el) el.scrollTop = el.scrollHeight;
    }

    // ── Agent theme (color + avatar from first message with an agent) ──

    get _agentMeta() {
        return this._messages.find(m => m.agentPrimaryColor || m.agentAvatarUrl) || {};
    }

    get themeStyle() {
        const color = this._agentMeta.agentPrimaryColor || '#0176D3';
        return `--agent-primary: ${color};`;
    }

    get hasAvatarUrl() {
        return !!this._agentMeta.agentAvatarUrl;
    }

    get agentAvatarUrl() {
        return this._agentMeta.agentAvatarUrl || '';
    }

    // ── Stats bar ──

    get totalCostFormatted() {
        const total = this._messages.reduce((sum, m) => sum + (m.cost ? Number(m.cost) : 0), 0);
        return '$' + total.toFixed(3);
    }

    get messageCount() {
        return this._messages.length;
    }

    get totalToolCalls() {
        return this._messages.reduce((sum, m) => sum + (m.toolCallCount || 0), 0);
    }

    // ── Message rows ──

    get isEmpty() {
        return this._messages.length === 0;
    }

    get messageRows() {
        return this._messages.map(m => {
            const hasFeedback = !!(m.feedback);
            const isThumbsUp  = m.feedback === 'Thumbs Up';
            return {
                id:                 m.id,
                userName:           m.userName   || 'User',
                userInput:          m.userInput  || '',
                agentResponse:      m.agentResponse || '',
                agentName:          m.agentName  || 'Agent',
                agentLetter:        (m.agentName || 'A').charAt(0).toUpperCase(),
                hasAgentResponse:   !!(m.agentResponse && m.agentResponse.trim()),
                toolCallCount:      m.toolCallCount || 0,
                hasToolCalls:       (m.toolCallCount || 0) > 0,
                toolLogs:           m.toolLogs || [],
                hasToolExecution:   !!(m.toolLogs && m.toolLogs.some(t => t.executionMessage)),
                errorLogs:          (m.errorLogs || []).map((el, i) => ({
                    key:   `${m.id}-err-${i}`,
                    error: el.error || 'An error occurred'
                })),
                hasErrors:          !!(m.errorLogs && m.errorLogs.length > 0),
                hasCost:            m.cost != null,
                costFormatted:      m.cost != null ? '$' + Number(m.cost).toFixed(3) : '',
                hasDuration:        m.durationMs != null,
                durationFormatted:  m.durationMs != null ? (m.durationMs / 1000).toFixed(1) + 's' : '',
                formattedStartTime: this._formatTime(m.startedAt),
                formattedEndTime:   this._formatTime(m.endedAt),
                hasFeedback,
                feedbackIcon:       isThumbsUp ? 'utility:like' : 'utility:dislike',
                feedbackClass:      'feedback-badge ' + (isThumbsUp ? 'feedback-badge--up' : 'feedback-badge--down'),
                feedbackNotes:      m.feedbackNotes || ''
            };
        });
    }

    // ── Helpers ──

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
