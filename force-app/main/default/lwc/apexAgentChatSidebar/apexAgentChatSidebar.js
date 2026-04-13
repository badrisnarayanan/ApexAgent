import { LightningElement, api } from 'lwc';

const MS_PER_MINUTE = 60000;
const MS_PER_HOUR   = 3600000;
const MS_PER_DAY    = 86400000;

export default class ApexAgentChatSidebar extends LightningElement {

    @api threads = [];
    @api activeThreadUUID;
    @api isProcessing = false;
    @api isOpen = false;

    // ── Derived ──

    get sidebarClass() {
        return 'sidebar' + (this.isOpen ? ' sidebar--open' : '');
    }

    get hasThreads() {
        return this.threads && this.threads.length > 0;
    }

    get groupedThreads() {
        if (!this.threads || this.threads.length === 0) {
            return [];
        }
        const now     = Date.now();
        const todayMs = new Date().setHours(0, 0, 0, 0);

        const groups = { Today: [], Yesterday: [] };
        const olderDates = {};

        this.threads.forEach(t => {
            const ts     = t.lastActivity ? new Date(t.lastActivity).getTime() : 0;
            const dayMs  = new Date(ts).setHours(0, 0, 0, 0);
            const diffMs = todayMs - dayMs;
            const label  = diffMs === 0 ? 'Today' : diffMs === MS_PER_DAY ? 'Yesterday' : null;

            const item = {
                threadUUID:   t.threadUUID,
                firstMessage: t.firstMessage || 'New conversation',
                relativeTime: this._relativeTime(ts, now),
                itemClass:    'thread-item' + (t.threadUUID === this.activeThreadUUID ? ' thread-item--active' : '')
            };

            if (label === 'Today') {
                groups.Today.push(item);
            } else if (label === 'Yesterday') {
                groups.Yesterday.push(item);
            } else {
                const dateLabel = new Intl.DateTimeFormat(undefined, {
                    month: 'short', day: 'numeric'
                }).format(new Date(ts));
                if (!olderDates[dateLabel]) {
                    olderDates[dateLabel] = [];
                }
                olderDates[dateLabel].push(item);
            }
        });

        const result = [];
        if (groups.Today.length > 0)     { result.push({ label: 'Today',     threads: groups.Today }); }
        if (groups.Yesterday.length > 0) { result.push({ label: 'Yesterday', threads: groups.Yesterday }); }
        Object.keys(olderDates).forEach(dateLabel => {
            result.push({ label: dateLabel, threads: olderDates[dateLabel] });
        });
        return result;
    }

    // ── Event handlers ──

    handleNewChat() {
        this.dispatchEvent(new CustomEvent('newchat'));
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleThreadClick(event) {
        const uuid = event.currentTarget.dataset.uuid;
        if (uuid) {
            this.dispatchEvent(new CustomEvent('threadselect', { detail: { threadUUID: uuid } }));
        }
    }

    // ── Private helpers ──

    _relativeTime(ts, now) {
        if (!ts) {
            return '';
        }
        const diffMs = now - ts;
        if (diffMs < MS_PER_MINUTE)    { return 'just now'; }
        if (diffMs < MS_PER_HOUR)      { return `${Math.floor(diffMs / MS_PER_MINUTE)} min ago`; }
        if (diffMs < MS_PER_DAY)       { return `${Math.floor(diffMs / MS_PER_HOUR)} hr ago`; }
        return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(ts));
    }
}