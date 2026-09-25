import { LightningElement, api, track } from 'lwc';
import getThreadMessages from '@salesforce/apex/ApexAgentThreadViewerController.getThreadMessages';

const REFRESH_INTERVAL_MS = 5000;
const SCROLL_THRESHOLD_PX = 50;

export default class ApexAgentThreadViewer extends LightningElement {

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

    get agentAvatarUrl() {
        return this._agentMeta.agentAvatarUrl || '';
    }

    // ── Summary bar ──

    get messageCount() {
        return this._messages.length;
    }

    // Sums across the loaded messages; a figure stays null (shown as "—") only
    // when no message has a value for it.
    get totals() {
        const fields = ['cost', 'durationMs', 'toolCallCount', 'inputTokens',
            'outputTokens', 'cachedInputTokens', 'reasoningTokens'];
        const totals = Object.fromEntries(fields.map(f => [f, null]));
        this._messages.forEach(m => {
            fields.forEach(f => {
                if (m[f] != null) {
                    totals[f] = (totals[f] || 0) + Number(m[f]);
                }
            });
        });
        return totals;
    }

    // ── Message list ──

    get isEmpty() {
        return this._messages.length === 0;
    }
}
