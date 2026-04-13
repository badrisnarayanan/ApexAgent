import { LightningElement, api, track } from 'lwc';

const THUMBS_UP   = 'Thumbs Up';
const THUMBS_DOWN = 'Thumbs Down';

export default class ApexAgentChatFeedbackDialog extends LightningElement {

    @api messageUUID;

    _isOpen = false;
    @api
    get isOpen() {
        return this._isOpen;
    }
    set isOpen(val) {
        this._isOpen = val;
        if (val) {
            // Move focus into the dialog when it opens so keyboard/SR users land correctly
            Promise.resolve().then(() => {
                const firstBtn = this.template.querySelector('button');
                if (firstBtn) {
                    firstBtn.focus();
                }
            });
        }
    }

    @api
    get existingFeedback() {
        return this._existingFeedback;
    }
    set existingFeedback(val) {
        this._existingFeedback = val;
        this._selectedFeedback = val || null;
    }

    @api
    get existingNotes() {
        return this._existingNotes;
    }
    set existingNotes(val) {
        this._existingNotes = val;
        this._notes = val || '';
    }

    @track _selectedFeedback = null;
    @track _notes = '';

    _existingFeedback = null;
    _existingNotes = '';

    // ── Derived ──

    get notes() {
        return this._notes;
    }

    get isThumbsUp() {
        return String(this._selectedFeedback === THUMBS_UP);
    }

    get isThumbsDown() {
        return String(this._selectedFeedback === THUMBS_DOWN);
    }

    get thumbUpClass() {
        return 'thumb-btn' + (this._selectedFeedback === THUMBS_UP ? ' thumb-btn--active' : '');
    }

    get thumbDownClass() {
        return 'thumb-btn' + (this._selectedFeedback === THUMBS_DOWN ? ' thumb-btn--active' : '');
    }

    get isSubmitDisabled() {
        return !this._selectedFeedback;
    }

    // ── Event handlers ──

    handleThumbsUp() {
        this._selectedFeedback = this._selectedFeedback === THUMBS_UP ? null : THUMBS_UP;
    }

    handleThumbsDown() {
        this._selectedFeedback = this._selectedFeedback === THUMBS_DOWN ? null : THUMBS_DOWN;
    }

    handleNotesChange(event) {
        this._notes = event.detail.value;
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleSubmit() {
        if (!this._selectedFeedback) {
            return;
        }
        this.dispatchEvent(new CustomEvent('submit', {
            detail: {
                messageUUID: this.messageUUID,
                feedback:    this._selectedFeedback,
                notes:       this._notes
            }
        }));
    }

    handleOverlayClick() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    stopPropagation(event) {
        event.stopPropagation();
    }
}
