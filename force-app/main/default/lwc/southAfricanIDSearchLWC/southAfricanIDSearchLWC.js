/**
 * SouthAfricanIDSearchLWC
 *
 * Public-facing form that validates a South African ID number, shows the
 * details encoded in it, and lists the national public holidays for the year -
 * highlighting any that fall on the visitor's birthday.
 *
 * Two layers of validation run. This component rejects obvious problems
 * locally (length, non-digits, an impossible month or day, a failed checksum)
 * so a typo never costs a round trip and the Search button stays disabled
 * until the input could plausibly be real. SouthAfricaIdDecoder on the server
 * then re-validates from scratch and is the only authority; the copy here is a
 * convenience, and the two implementations must be changed together.
 *
 * State is plain reactive fields rather than a wire adapter because the search
 * is imperative, has side effects on the server (it records the search) and
 * must not be cached.
 *
 * @see SAIdSearchController.searchBySouthAfricanIdNumber
 * @see SouthAfricaIdDecoder
 */
import { LightningElement } from 'lwc';
import searchById from '@salesforce/apex/SAIdSearchController.searchBySouthAfricanIdNumber';

// Kept identical to the wording SouthAfricaIdDecoder returns, so the message
// does not change when validation moves from the client to the server.
const LENGTH_MSG = 'The ID Number must be exactly 13 digits.';
const NUMERIC_MSG = 'The ID Number must contain digits only.';
const INVALID_MSG = 'Please enter a valid South African ID Number.';

// Decorative confetti pieces. Position, colour and timing all come from
// :nth-child rules in the stylesheet, so each piece only needs a stable key.
const CONFETTI_PIECES = Array.from({ length: 14 }, (unused, i) => ({
    id: `confetti-${i}`
}));

export default class SouthAfricanIDSearchLWC extends LightningElement {
    /** Current input value, whitespace-trimmed. */
    saIdNumber = '';

    /** Validation message from this component. Shown under the form. */
    clientError = '';

    /** Failure message from the server, or a generic one if the call threw. */
    serverError = '';

    /** Info banner about the holiday lookup specifically - empty list,
     *  provider outage, and so on. Independent of serverError. */
    holidayBanner = '';

    isLoading = false;

    /** Gate for the Search button; set only by validateClient(). */
    isClientValid = false;

    /** True once a search has succeeded, which reveals the results section. */
    hasDecoded = false;

    // Decoded values, shown in the "Extracted ID Information" panel.
    formattedDob = '';
    gender = '';
    citizenship = '';
    birthYear;

    /** Year the holiday list belongs to; rendered as the badge on the table.
     *  Comes from the server so it matches the year actually queried. */
    currentYear;

    /** Holidays decorated with birthday-match flags. See decorateHolidays(). */
    holidays = [];

    confettiPieces = CONFETTI_PIECES;

    /** Watches the fixed header's rendered height so .cs-app's padding-top
     *  (the --cs-header-height custom property, read in the CSS) always
     *  matches it exactly — across breakpoints, font loading, and any future
     *  copy change — instead of a hard-coded guess that would drift out of
     *  sync and either leave a gap or let content slide under the header. */
    _headerResizeObserver;

    get isSearchDisabled() {
        return !this.isClientValid || this.isLoading;
    }

    get hasHolidays() {
        return Array.isArray(this.holidays) && this.holidays.length > 0;
    }

    /**
     * Whether the results column shows its "nothing yet" panel.
     *
     * The panel exists to hold the right-hand column open before the first
     * search, so the two-column grid does not sit half empty and then jump
     * when results arrive. It stays visible alongside a serverError, where it
     * reads as reassurance rather than as a second error message.
     */
    get showPlaceholder() {
        return !this.isLoading && !this.hasDecoded;
    }

    /**
     * Starts watching the fixed header once it exists in the DOM. A
     * ResizeObserver (rather than a one-off measurement, or a window
     * `resize` listener) is used because the header's height itself changes
     * at the responsive breakpoints — logo/title stack on mobile, sit in a
     * row from tablet up — and content reflow like that does not always
     * coincide with a viewport resize event (e.g. dev-tools device toolbar,
     * a container resizing inside a Salesforce page layout). Guarded so it
     * is only ever created once, since renderedCallback can fire many times.
     */
    renderedCallback() {
        if (this._headerResizeObserver || typeof ResizeObserver === 'undefined') {
            return;
        }
        const header = this.template.querySelector('.cs-appbar');
        if (!header) {
            return;
        }
        this._headerResizeObserver = new ResizeObserver((entries) => {
            const height = entries[0].contentRect.height;
            this.template.host.style.setProperty('--cs-header-height', `${height}px`);
        });
        this._headerResizeObserver.observe(header);
    }

    /** Stops the observer so it does not keep firing against a detached
     *  element after the component is torn down. */
    disconnectedCallback() {
        if (this._headerResizeObserver) {
            this._headerResizeObserver.disconnect();
            this._headerResizeObserver = null;
        }
    }

    /**
     * Every keystroke discards the previous result before revalidating, so
     * stale details can never sit on screen next to a changed number.
     */
    handleIdChange(event) {
        this.saIdNumber = (event.target.value || '').trim();
        this.clearResults();
        this.validateClient();
    }

    /**
     * Revalidates before submitting: the form can also be submitted with Enter,
     * which does not necessarily go through handleIdChange first.
     */
    handleSubmit(event) {
        event.preventDefault();
        this.validateClient();
        if (!this.isClientValid || this.isLoading) {
            return;
        }
        this.runSearch();
    }

    /**
     * Runs the local rules in the same cheapest-first order as the server, so
     * whichever layer rejects the number, the user sees the same message.
     * Sets clientError and isClientValid; has no other side effects.
     */
    validateClient() {
        this.clientError = '';
        this.isClientValid = false;
        if (!this.saIdNumber) {
            this.clientError = 'Please enter a valid South African ID Number.';
            return;
        }
        if (!/^[0-9]+$/.test(this.saIdNumber)) {
            this.clientError = NUMERIC_MSG;
            return;
        }
        if (this.saIdNumber.length !== 13) {
            this.clientError = LENGTH_MSG;
            return;
        }
        if (!this.isLikelyValidSaId(this.saIdNumber)) {
            this.clientError = INVALID_MSG;
            return;
        }
        this.isClientValid = true;
    }

    /**
     * Structural checks that do not need the server: month and day ranges
     * (digits 3-6), the citizenship digit (11), and the checksum.
     *
     * "Likely" is the operative word - the calendar itself is not checked here,
     * so 31 February passes locally and is caught server-side. Deliberate: this
     * is a fast-fail filter, not a second implementation of the decoder.
     */
    isLikelyValidSaId(id) {
        const mm = Number(id.substring(2, 4));
        const dd = Number(id.substring(4, 6));
        if (mm < 1 || mm > 12 || dd < 1 || dd > 31) {
            return false;
        }
        const c = id.substring(10, 11);
        if (c !== '0' && c !== '1') {
            return false;
        }
        return this.luhnSa(id);
    }

    /**
     * The Home Affairs Luhn variant, mirroring
     * SouthAfricaIdDecoder.computeCheckDigit().
     *
     * Note the even-position digits are concatenated into one number and that
     * number is doubled once - not each digit doubled individually as in
     * textbook Luhn. The results differ, so do not swap in a standard
     * implementation.
     */
    luhnSa(id) {
        let oddSum = 0;
        for (let i = 0; i < 12; i += 2) {
            oddSum += Number(id[i]);
        }
        let evenConcat = '';
        for (let i = 1; i < 12; i += 2) {
            evenConcat += id[i];
        }
        const evenDigitSum = String(Number(evenConcat) * 2)
            .split('')
            .reduce((a, d) => a + Number(d), 0);
        const check = (10 - ((oddSum + evenDigitSum) % 10)) % 10;
        return check === Number(id[12]);
    }

    /**
     * Calls the Apex controller and maps its envelope onto component state.
     *
     * The controller returns a result object rather than throwing for expected
     * failures, so there are three outcomes to handle: a rejected number
     * (success === false), a valid number whose holiday lookup failed
     * (isHolidaysAvailable === false, details still shown), and full success.
     * The catch block is only for genuine transport or Aura-level errors.
     *
     * Previous results are cleared up front (not just on keystroke) so a
     * resubmission of the same, unchanged ID that then fails never leaves a
     * stale success panel on screen next to the new error.
     */
    async runSearch() {
        this.isLoading = true;
        this.clearResults();
        try {
            const result = await searchById({ saIdNumber: this.saIdNumber });
            if (!result || result.success === false) {
                this.serverError =
                    result && result.userMessage
                        ? result.userMessage
                        : 'Something went wrong while processing your request. Please try again.';
                return;
            }
            this.hasDecoded = true;
            this.formattedDob = this.formatDate(result.dateOfBirth);
            this.gender = result.gender;
            this.citizenship = result.citizenship;
            this.birthYear = result.dobYear;
            this.currentYear = result.currentYear;

            // Only populate the table when the holiday lookup actually
            // succeeded; otherwise leave it empty so the "could not retrieve"
            // banner below is not shown side-by-side with stale/partial rows.
            this.holidays = result.isHolidaysAvailable
                ? this.decorateHolidays(result.publicHolidayInfoList || [], result.dateOfBirth)
                : [];

            this.holidayBanner = result.holidayMessage || '';
            // The ID did validate, so a holiday failure must be explained
            // rather than leaving the table silently absent.
            if (!result.isHolidaysAvailable && !this.holidayBanner) {
                this.holidayBanner =
                    'We were able to validate your ID Number, but we could not retrieve the public holiday information at this time. Please try again later.';
            }

            // Accessibility: results appear below the form, so screen reader and
            // keyboard users are moved to the new heading. Deferred a frame
            // because lwc:ref only resolves once the section has rendered.
            requestAnimationFrame(() => {
                const heading = this.refs && this.refs.resultsHeading;
                if (heading) {
                    heading.focus();
                }
            });
        } catch (e) {
            // Never surface the raw Aura error - it can carry internal detail.
            this.serverError =
                'Something went wrong while processing your request. Please try again.';
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Flags holidays that fall on the same day and month as the date of birth.
     * The year is deliberately ignored so the birthday matches regardless of it.
     *
     * Returns new objects rather than mutating: the Apex response is frozen in
     * LWC, so assigning onto its members would throw. rowClass is precomputed
     * here because the template cannot evaluate expressions.
     */
    decorateHolidays(list, dateOfBirth) {
        const dobKey = this.monthDayKey(dateOfBirth);
        return list.map((h) => {
            const isBirthdayMatch =
                !!dobKey && this.monthDayKey(h.holidayDate) === dobKey;
            return {
                ...h,
                isBirthdayMatch,
                rowClass: isBirthdayMatch ? 'cs-row cs-row_match' : 'cs-row'
            };
        });
    }

    /**
     * Normalises a date value to an 'MM-DD' key, or '' when unusable.
     *
     * An ISO string is sliced directly rather than parsed, because Date would
     * read 'yyyy-MM-dd' as UTC midnight and could shift the day by one in a
     * negative-offset timezone - turning a real birthday match into a miss.
     * The Date branch is only a fallback for non-ISO input.
     */
    monthDayKey(value) {
        if (!value) {
            return '';
        }
        if (typeof value === 'string' && value.length >= 10) {
            return value.substring(5, 10);
        }
        const d = new Date(value);
        if (Number.isNaN(d.getTime())) {
            return '';
        }
        const mm = String(d.getUTCMonth() + 1).padStart(2, '0');
        const dd = String(d.getUTCDate()).padStart(2, '0');
        return `${mm}-${dd}`;
    }

    /**
     * Formats the date of birth for display in South African convention
     * (16 June 1990). Falls back to the raw value if it will not parse, so a
     * formatting problem never blanks the field.
     */
    formatDate(iso) {
        if (!iso) {
            return '';
        }
        const d = new Date(iso);
        if (Number.isNaN(d.getTime())) {
            return iso;
        }
        return new Intl.DateTimeFormat('en-ZA', {
            day: '2-digit',
            month: 'long',
            year: 'numeric'
        }).format(d);
    }

    /**
     * Clears everything from the previous search. Called on each keystroke,
     * and now also at the start of runSearch(), so results never outlive the
     * number that produced them and a failed resubmission never leaves a
     * stale success panel on screen.
     */
    clearResults() {
        this.serverError = '';
        this.holidayBanner = '';
        this.hasDecoded = false;
        this.holidays = [];
    }
}