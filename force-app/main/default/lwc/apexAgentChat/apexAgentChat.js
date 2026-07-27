import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { getRecord }            from 'lightning/uiRecordApi';
import { ShowToastEvent }       from 'lightning/platformShowToastEvent';
import userId                   from '@salesforce/user/Id';

const FIRSTNAME_FIELD = 'User.FirstName';

import getAgentConfig      from '@salesforce/apex/ApexAgentChatController.getAgentConfig';
import getThreads          from '@salesforce/apex/ApexAgentChatController.getThreads';
import getMessages         from '@salesforce/apex/ApexAgentChatController.getMessages';
import sendMessage         from '@salesforce/apex/ApexAgentChatController.sendMessage';
import saveFeedback        from '@salesforce/apex/ApexAgentChatController.saveFeedback';
import getExecutionMessages from '@salesforce/apex/ApexAgentChatController.getExecutionMessages';

// Record context field map — keyed by objectApiName
const OBJECT_FIELD_MAP = {
    Case:        ['Case.CaseNumber',        'Case.Subject',        'Case.Status'],
    Lead:        ['Lead.FirstName',         'Lead.LastName',       'Lead.Company'],
    Contact:     ['Contact.FirstName',      'Contact.LastName'],
    Opportunity: ['Opportunity.Name',       'Opportunity.StageName', 'Opportunity.CloseDate'],
    Account:     ['Account.Name',           'Account.Type',        'Account.Industry']
};

const POLL_INTERVAL_MS    = 1500;
const MAX_POLL_MS         = 180000;
const SCROLL_THRESHOLD_PX = 150;
const TYPE_USER    = 'user';
const TYPE_AGENT   = 'agent';
const TYPE_LOADING = 'loading';
const TYPE_ERROR   = 'error';

export default class ApexAgentChat extends LightningElement {

    @api agentName;

    @track agentConfig      = null;
    @track messages         = [];
    @track threads          = [];
    @track isSidebarOpen    = false;
    @track isProcessing     = false;
    @track isThreadLoading  = false;
    @track isFeedbackOpen   = false;
    @track feedbackTarget   = {};
    @track inputText        = '';
    @track hasConfigError   = false;
    @track configErrorMessage = '';

    userFirstName = '';

    _currentThreadUUID  = null;
    _pollingInterval    = null;
    _sendTimeoutId      = null;
    // Identity token for the in-flight send — lets late callbacks (a timeout that
    // fires after the request already resolved, or a resolution that arrives after
    // a timeout already gave up) tell whether they still own the shared processing
    // state before mutating it.
    _activeRequestState = null;
    _inFlightLoadingKey = null;
    _shouldScrollToBottom = false;
    _recordContext      = null;
    _recordId           = null;
    _objectApiName      = null;
    _recordFields       = null;

    // ── Lifecycle ──

    connectedCallback() {
        this._currentThreadUUID = crypto.randomUUID();
        this._loadAgentConfig();
        this._loadThreads();
    }

    disconnectedCallback() {
        this._clearPolling();
        if (this._sendTimeoutId) {
            clearTimeout(this._sendTimeoutId);
            this._sendTimeoutId = null;
        }
    }

    renderedCallback() {
        if (this._shouldScrollToBottom) {
            this._shouldScrollToBottom = false;
            const container = this.template.querySelector('.messages-container');
            if (container) {
                container.scrollTop = container.scrollHeight;
            }
        }
    }

    // ── Wire: load current user's first name ──

    @wire(getRecord, { recordId: userId, fields: [FIRSTNAME_FIELD] })
    wiredUser({ data }) {
        if (data) {
            this.userFirstName = data.fields.FirstName.value || '';
        }
    }

    // ── Wire: detect record page navigation ──

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        this._loadRecordContext(pageRef);
    }

    // ── Wire: load record fields reactively when _recordId / _recordFields change ──

    @wire(getRecord, { recordId: '$_recordId', fields: '$_recordFields' })
    wiredRecord({ data, error }) {
        if (data) {
            this._recordContext = this._buildContextString(this._objectApiName, this._recordId, data);
        } else if (error) {
            this._recordContext = null;
        }
    }

    // ── Public getter (sidebar needs it) ──

    get currentThreadUUID() {
        return this._currentThreadUUID;
    }

    // ── Derived ──

    get themeStyle() {
        const primary = this.agentConfig ? (this.agentConfig.primaryColor || '#0176D3') : '#0176D3';
        return `--agent-primary: ${primary};`;
    }

    get hasAvatarUrl() {
        return !!(this.agentConfig && this.agentConfig.avatarUrl);
    }

    get avatarLetter() {
        return this.agentConfig && this.agentConfig.name
            ? this.agentConfig.name.charAt(0).toUpperCase()
            : 'A';
    }

    get isConfigLoading() {
        return !this.agentConfig && !this.hasConfigError;
    }

    get showEmptyState() {
        return !!this.agentConfig && this.messages.length === 0 && !this.isProcessing;
    }

    get inputPlaceholder() {
        const name = this.agentConfig ? this.agentConfig.name : this.agentName;
        return `Message ${name || 'Agent'}...`;
    }

    get isSendDisabled() {
        return this.isProcessing || !this.inputText || !this.inputText.trim() || !this.agentConfig;
    }

    // ── Event handlers: sidebar ──

    handleSidebarOpen() {
        this.isSidebarOpen = true;
    }

    handleSidebarClose() {
        this.isSidebarOpen = false;
    }

    handleNewChat() {
        this.isSidebarOpen      = false;
        this._currentThreadUUID = crypto.randomUUID();
        this.messages           = [];
    }

    handleThreadSelect(event) {
        const uuid = event.detail.threadUUID;
        if (uuid === this._currentThreadUUID) {
            this.isSidebarOpen = false;
            return;
        }
        this._currentThreadUUID = uuid;
        this.messages           = [];
        this.isSidebarOpen      = false;
        this._loadMessages(uuid);
    }

    // ── Event handlers: input ──

    handleInput(event) {
        this.inputText = event.target.value;
        this._autoGrowTextarea(event.target);
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            if (!this.isSendDisabled) {
                this.handleSend();
            }
        }
    }

    handleSend() {
        const text = this.inputText ? this.inputText.trim() : '';
        if (!text || this.isProcessing) {
            return;
        }

        this.inputText    = '';
        this.isProcessing = true;
        this._resetTextareaHeight();

        const messageUUID = crypto.randomUUID();

        // Append user bubble
        const userMsg = this._buildMessage(crypto.randomUUID(), TYPE_USER, text, Date.now(), null);
        // Append loading bubble
        const loadingKey = crypto.randomUUID();
        this._inFlightLoadingKey = loadingKey;
        const loadingMsg = this._buildMessage(loadingKey, TYPE_LOADING, '', null, null);
        loadingMsg.agentMessageUUID = messageUUID;
        loadingMsg.isToolsExpanded  = true;

        this.messages = [...this.messages, userMsg, loadingMsg];
        this._shouldScrollToBottom = true;

        // Tracks whether THIS send has already been finalized (by timeout or by a
        // real resolution), independent of execution-message polling being enabled.
        const requestState = { settled: false };
        this._activeRequestState = requestState;

        // Start polling if agent has execution messages enabled
        if (this.agentConfig && this.agentConfig.showExecutionMessage) {
            this._startPolling(messageUUID, loadingKey, requestState);
        }

        // Client-side timeout now applies to every send, not just when
        // execution-message polling happens to be active.
        this._sendTimeoutId = setTimeout(() => {
            if (requestState.settled) {
                return;
            }
            requestState.settled = true;
            this._replaceLoadingWithError(loadingKey, 'Request timed out. Please try again.');
            if (this._activeRequestState === requestState) {
                this._clearPolling();
                this.isProcessing = false;
                this._inFlightLoadingKey = null;
            }
        }, MAX_POLL_MS);

        sendMessage({
            agentName:   this.agentName,
            userMessage: text,
            threadUUID:  this._currentThreadUUID,
            messageUUID,
            context:     this._recordContext
        })
        .then(response => {
            // Already timed out client-side — don't let a late success silently
            // overwrite the error bubble the user already saw.
            if (requestState.settled) {
                return;
            }
            requestState.settled = true;
            clearTimeout(this._sendTimeoutId);
            this._clearPolling();
            this._resolveLoadingBubble(loadingKey, response);
            this._loadThreads();
        })
        .catch(() => {
            if (requestState.settled) {
                return;
            }
            requestState.settled = true;
            clearTimeout(this._sendTimeoutId);
            this._clearPolling();
            this._replaceLoadingWithError(loadingKey, 'Something went wrong. Please try again.');
            this._loadThreads();
        })
        .finally(() => {
            // Only clear the shared processing state if a newer send hasn't already
            // taken over (e.g. the user sent a follow-up after this one timed out).
            if (this._activeRequestState === requestState) {
                this.isProcessing = false;
                this._inFlightLoadingKey = null;
            }
            this._shouldScrollToBottom = true;
        });
    }

    // ── Event handlers: feedback ──

    handleFeedbackClick(event) {
        const uuid = event.detail.agentMessageUUID;
        const msg  = this.messages.find(m => m.agentMessageUUID === uuid);
        this.feedbackTarget = {
            agentMessageUUID: uuid,
            feedback:         event.detail.feedback,
            feedbackNotes:    msg ? (msg.feedbackNotes || '') : ''
        };
        this.isFeedbackOpen = true;
    }

    handleFeedbackClose() {
        this.isFeedbackOpen = false;
    }

    handleFeedbackSubmit(event) {
        const { messageUUID, feedback, notes } = event.detail;
        saveFeedback({ messageUUID, feedback, feedbackNotes: notes })
        .then(() => {
            // Optimistic update
            this.messages = this.messages.map(m => {
                if (m.agentMessageUUID === messageUUID) {
                    return { ...m, feedback, feedbackNotes: notes };
                }
                return m;
            });
            this.isFeedbackOpen = false;
            this.dispatchEvent(new ShowToastEvent({
                title:   'Feedback submitted',
                variant: 'success'
            }));
        })
        .catch(() => {
            this.dispatchEvent(new ShowToastEvent({
                title:   'Failed to save feedback',
                variant: 'error'
            }));
        });
    }

    handleToolsToggle(event) {
        const { key, isExpanded } = event.detail;
        this.messages = this.messages.map(m => {
            if (m.key === key) {
                return { ...m, isToolsExpanded: isExpanded };
            }
            return m;
        });
    }

    // ── Private: load helpers ──

    _loadAgentConfig() {
        if (!this.agentName) {
            this.hasConfigError     = true;
            this.configErrorMessage = 'No agent configured. Set the Agent Name property in App Builder.';
            return;
        }
        getAgentConfig({ agentName: this.agentName })
        .then(config => {
            if (!config) {
                this.hasConfigError     = true;
                this.configErrorMessage = `Agent "${this.agentName}" not found.`;
            } else {
                this.agentConfig = config;
            }
        })
        .catch(() => {
            this.hasConfigError     = true;
            this.configErrorMessage = 'Failed to load agent configuration.';
        });
    }

    _loadThreads() {
        if (!this.agentName) {
            return;
        }
        getThreads({ agentName: this.agentName })
        .then(result => {
            this.threads = result || [];
        })
        .catch(() => {
            // Non-critical — sidebar just stays empty
        });
    }

    _loadMessages(threadUUID) {
        this.isThreadLoading = true;
        getMessages({ threadUUID })
        .then(result => {
            if (!result) {
                return;
            }
            this.messages = result.flatMap(md => {
                const msg = this._buildMessage(
                    md.messageLogId,
                    TYPE_USER,
                    md.userInput || '',
                    md.startedAt,
                    null
                );

                const agentMsg = this._buildMessage(
                    `${md.messageLogId}-agent`,
                    md.agentResponse ? TYPE_AGENT : TYPE_LOADING,
                    md.agentResponse || '',
                    null,
                    md.endedAt
                );
                agentMsg.messageLogId     = md.messageLogId;
                agentMsg.agentMessageUUID = md.agentMessageUUID;
                agentMsg.feedback         = md.feedback;
                agentMsg.feedbackNotes    = md.feedbackNotes;
                agentMsg.toolLogs         = md.toolLogs  || [];
                agentMsg.errorLogs        = md.errorLogs || [];
                agentMsg.isToolsExpanded  = false;

                // Append error bubbles for historical errors
                const errorMsgs = (md.errorLogs || []).map((el, i) => {
                    return this._buildMessage(
                        `${md.messageLogId}-err-${i}`,
                        TYPE_ERROR,
                        el.error || 'An error occurred',
                        null,
                        null
                    );
                });

                const hasErrors = errorMsgs.length > 0;
                return !md.agentResponse && hasErrors
                    ? [msg, ...errorMsgs]
                    : [msg, agentMsg, ...errorMsgs];
            });
            this._shouldScrollToBottom = true;
        })
        .catch(() => {
            // Fail silently — user can start a fresh conversation
        })
        .finally(() => {
            this.isThreadLoading = false;
        });
    }

    // ── Private: polling ──

    _startPolling(messageUUID, loadingKey, requestState) {
        this._pollingInterval = setInterval(() => {
            if (requestState.settled) {
                this._clearPolling();
                return;
            }
            getExecutionMessages({ messageUUID })
            .then(actions => {
                if (requestState.settled || this._inFlightLoadingKey !== loadingKey) {
                    return;
                }
                if (actions && actions.length > 0) {
                    const nearBottom = this._isNearBottom();
                    this.messages = this.messages.map(m => {
                        if (m.key === loadingKey) {
                            return { ...m, toolLogs: this._mapToolActions(actions) };
                        }
                        return m;
                    });
                    if (nearBottom) {
                        this._shouldScrollToBottom = true;
                    }
                }
            })
            .catch(() => {
                // Poll failure is non-fatal — keep polling
            });
        }, POLL_INTERVAL_MS);
    }

    _clearPolling() {
        if (this._pollingInterval) {
            clearInterval(this._pollingInterval);
            this._pollingInterval = null;
        }
    }

    _isNearBottom() {
        const container = this.template.querySelector('.messages-container');
        if (!container) return true;
        return container.scrollHeight - container.scrollTop - container.clientHeight <= SCROLL_THRESHOLD_PX;
    }

    _mapToolActions(actions) {
        return actions.map(a => ({
            toolName:        a.toolName || a.toolCallId || '',
            executionMessage: a.executionMessage || '',
            status:          a.status || ''
        }));
    }

    // ── Private: resolve loading bubble ──

    _resolveLoadingBubble(loadingKey, response) {
        if (!response) {
            this._replaceLoadingWithError(loadingKey, 'No response received.');
            return;
        }
        if (response.errorMessage) {
            this._replaceLoadingWithError(loadingKey, response.errorMessage);
            return;
        }
        this.messages = this.messages.map(m => {
            if (m.key !== loadingKey) {
                return m;
            }
            return {
                ...m,
                type:            TYPE_AGENT,
                text:            response.llmResponse || '',
                endedAt:         Date.now(),
                isToolsExpanded: false
            };
        });
    }

    _replaceLoadingWithError(loadingKey, errorText) {
        this.messages = this.messages.map(m => {
            if (m.key !== loadingKey) {
                return m;
            }
            return { ...m, type: TYPE_ERROR, text: errorText };
        });
    }

    // ── Private: record context ──

    _loadRecordContext(pageRef) {
        if (!pageRef || pageRef.type !== 'standard__recordPage') {
            this._recordContext   = null;
            this._recordId        = null;
            this._objectApiName   = null;
            this._recordFields    = null;
            return;
        }
        const recordId      = pageRef.attributes.recordId;
        const objectApiName = pageRef.attributes.objectApiName;

        if (!recordId || !objectApiName) {
            this._recordContext = null;
            return;
        }

        this._recordId      = recordId;
        this._objectApiName = objectApiName;

        const mappedFields = OBJECT_FIELD_MAP[objectApiName] || [];
        const baseFields   = [`${objectApiName}.Id`];
        const customFields = objectApiName.endsWith('__c') ? [`${objectApiName}.Name`] : [];
        this._recordFields = [...baseFields, ...customFields, ...mappedFields];
        // Wire wiredRecord will fire automatically once _recordId + _recordFields are set
    }

    _buildContextString(objectApiName, recordId, record) {
        let ctx = 'The user is currently viewing a record page — this may or may not be relevant to their query. Below are the details:\n';
        ctx += `Object: ${objectApiName}\n`;
        ctx += `Id: ${recordId}\n`;
        if (record && record.fields) {
            Object.keys(record.fields).forEach(fieldName => {
                const val = record.fields[fieldName] ? record.fields[fieldName].value : null;
                if (val !== null && val !== undefined && fieldName !== 'Id') {
                    ctx += `${fieldName}: ${val}\n`;
                }
            });
        }
        return ctx;
    }

    // ── Private: message builder ──

    _buildMessage(key, type, text, startedAt, endedAt) {
        return {
            key,
            type,
            text:            text || '',
            startedAt:       startedAt || null,
            endedAt:         endedAt   || null,
            feedback:        null,
            feedbackNotes:   null,
            messageLogId:    null,
            agentMessageUUID: null,
            toolLogs:        [],
            errorLogs:       [],
            isToolsExpanded: false
        };
    }

    // ── Private: textarea helpers ──

    _autoGrowTextarea(el) {
        el.style.height = 'auto';
        const maxHeight = 96; // ~4 lines
        const newHeight = Math.min(el.scrollHeight, maxHeight);
        el.style.height = `${newHeight}px`;
        el.style.overflowY = el.scrollHeight > maxHeight ? 'auto' : 'hidden';
    }

    _resetTextareaHeight() {
        // Native <textarea> has no HTML value attribute (only a DOM property), so the
        // declarative value={inputText} template binding doesn't reliably clear it once
        // the user has typed — the DOM value must also be cleared imperatively here.
        const ta = this.template.querySelector('.message-input');
        if (ta) {
            ta.value = '';
            ta.style.height = 'auto';
        }
    }
}