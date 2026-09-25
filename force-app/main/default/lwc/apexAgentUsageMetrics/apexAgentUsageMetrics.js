import { LightningElement, api } from 'lwc';

const EMPTY_VALUE = '—';

/**
 * Cost / duration / tool-call figures plus a token breakdown, shown in the summary
 * header of the thread and message viewers. Pass raw numbers; formatting happens here.
 * Leave messageCount unset to hide the Messages figure.
 */
export default class ApexAgentUsageMetrics extends LightningElement {

    @api messageCount;
    @api cost;
    @api durationMs;
    @api toolCallCount;
    @api inputTokens;
    @api outputTokens;
    @api cachedInputTokens;
    @api reasoningTokens;

    get runMetrics() {
        const metrics = [];
        if (this.messageCount != null) {
            metrics.push({ key: 'messages', label: 'Messages', value: this._formatCount(this.messageCount) });
        }
        metrics.push(
            { key: 'cost',     label: 'Cost',       value: this.cost != null ? '$' + Number(this.cost).toFixed(4) : EMPTY_VALUE },
            { key: 'duration', label: 'Duration',   value: this._formatDuration(this.durationMs) },
            { key: 'tools',    label: 'Tool calls', value: this._formatCount(this.toolCallCount || 0) }
        );
        return metrics;
    }

    get tokenMetrics() {
        return [
            { key: 'input',     label: 'Input',     value: this._formatCount(this.inputTokens) },
            { key: 'output',    label: 'Output',    value: this._formatCount(this.outputTokens) },
            { key: 'cached',    label: 'Cached',    value: this._formatCount(this.cachedInputTokens) },
            { key: 'reasoning', label: 'Reasoning', value: this._formatCount(this.reasoningTokens) }
        ];
    }

    _formatCount(n) {
        return n != null ? new Intl.NumberFormat().format(n) : EMPTY_VALUE;
    }

    _formatDuration(ms) {
        if (ms == null) return EMPTY_VALUE;
        const seconds = ms / 1000;
        if (seconds < 60) return seconds.toFixed(1) + 's';
        const minutes = Math.floor(seconds / 60);
        return `${minutes}m ${Math.round(seconds % 60)}s`;
    }
}
