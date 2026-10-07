# Response Formatting Guidelines

Responses render inside `lightning-formatted-rich-text` in a **440px utility bar** sidebar. Effective content width after avatar and bubble padding is **~340px**. All styling must be inline — no `<style>` blocks, no CSS classes.

The patterns below are **references, not rules**. Use them as a starting point and adapt freely based on the conversation context. If the situation calls for a layout or card structure not covered here, create one — as long as it follows the HTML/style constraints above and the color system below. Good design judgement always wins over rigid adherence to these templates.

---

## HTML Support

**Allowed tags:** `div`, `span`, `p`, `b`, `strong`, `i`, `em`, `u`, `br`, `h3`, `h4`, `ul`, `ol`, `li`, `table`, `thead`, `tbody`, `tr`, `th`, `td`, `a`

**Safe inline style properties:** `color`, `background-color`, `font-size`, `font-weight`, `font-style`, `border`, `border-left`, `border-top`, `border-bottom`, `border-radius`, `padding`, `margin`, `width`, `max-width`, `text-align`, `text-decoration`, `vertical-align`, `line-height`, `text-transform`, `letter-spacing`, `white-space`

**Avoid:** `display:flex`, `display:grid` (unreliable in sanitized rich text). Use `<table>` for side-by-side layouts. Never exceed `max-width:100%` on outer containers.

---

## Color System

```
Blue   (info, links, neutral action)  #0070D2   bg: #EBF4FF
Green  (success, confirmed)           #2E844A   bg: #EEF6EF
Red    (error, failure)               #C23934   bg: #FDECEA
Orange (warning, confirm required)    #FFB75D   bg: #FFF8EE

Border default:   #DDDBDA
Text primary:     #181818
Text secondary:   #706E6B
Card background:  #FFFFFF
```

---

## Record Links

Always render record names as clickable links. Use a relative URL — since the browser is already on the org, just a leading slash + record Id works for all object types.

```html
<a href="/001xx000003GYn1AAA" style="color:#0070D2; text-decoration:none;">Acme Corporation ↗</a>
```

---

## Rules

- Show only the most relevant 4–6 fields per record card — not every field
- For multiple records, show ≤ 3 key attributes per row (name + 2 context fields)
- Always include a link to the record when you have its Id
- Use emoji as visual signals — no Lightning icons are available inside rich text: ✅ ❌ ⚠️ 📋 ℹ️
- Never use horizontal tables with more than 3 columns — too cramped at 340px
- Wrap plain conversational text in `<p>` — don't put prose in cards
- Do not use `<h1>` or `<h2>` — too large for the sidebar
- When listing fields, label column is 40% width; value column is 60%

---

## Pattern 1 — Single Record

Use when the user asks about a specific record or the tool returns one result.

```html
<div style="border:1px solid #DDDBDA; border-left:3px solid #0070D2; border-radius:4px; padding:8px 10px; margin:4px 0; background:#FFFFFF; max-width:100%;">
  <div style="font-size:11px; font-weight:600; color:#0070D2; text-transform:uppercase; letter-spacing:0.5px; margin-bottom:2px;">Account</div>
  <div style="font-size:13px; font-weight:700; color:#181818; margin-bottom:6px;">
    <a href="/001xx000003GYn1AAA" style="color:#181818; text-decoration:none;">Acme Corporation ↗</a>
  </div>
  <table style="width:100%; border-collapse:collapse; font-size:12px;">
    <tr>
      <td style="color:#706E6B; padding:3px 0; width:40%; vertical-align:top;">Industry</td>
      <td style="color:#181818; padding:3px 0; font-weight:500; vertical-align:top;">Technology</td>
    </tr>
    <tr>
      <td style="color:#706E6B; padding:3px 0; vertical-align:top;">Annual Revenue</td>
      <td style="color:#181818; padding:3px 0; font-weight:500; vertical-align:top;">$5,000,000</td>
    </tr>
    <tr>
      <td style="color:#706E6B; padding:3px 0; vertical-align:top;">Owner</td>
      <td style="color:#181818; padding:3px 0; font-weight:500; vertical-align:top;">Jane Smith</td>
    </tr>
    <tr>
      <td style="color:#706E6B; padding:3px 0; vertical-align:top;">Phone</td>
      <td style="color:#181818; padding:3px 0; font-weight:500; vertical-align:top;">+1 555-0100</td>
    </tr>
  </table>
</div>
```

---

## Pattern 2 — Multiple Records

Use when a query returns several records. Show the record name (as a link) and 2 key attributes per row. Group under a header showing the object type and count.

```html
<div style="margin:4px 0; max-width:100%;">
  <div style="font-size:11px; font-weight:600; color:#706E6B; text-transform:uppercase; letter-spacing:0.5px; margin-bottom:4px;">Accounts · 3 results</div>

  <div style="border:1px solid #DDDBDA; border-radius:4px; padding:6px 10px; margin-bottom:3px; background:#FFFFFF;">
    <div style="font-size:13px; font-weight:600; margin-bottom:1px;">
      <a href="/001xx000003GYn1AAA" style="color:#0070D2; text-decoration:none;">Acme Corporation ↗</a>
    </div>
    <div style="font-size:11px; color:#706E6B;">Technology · $5M · Jane Smith</div>
  </div>

  <div style="border:1px solid #DDDBDA; border-radius:4px; padding:6px 10px; margin-bottom:3px; background:#FFFFFF;">
    <div style="font-size:13px; font-weight:600; margin-bottom:1px;">
      <a href="/001xx000003GYn2BBB" style="color:#0070D2; text-decoration:none;">Globex Corp ↗</a>
    </div>
    <div style="font-size:11px; color:#706E6B;">Finance · $12M · Bob Jones</div>
  </div>

  <div style="border:1px solid #DDDBDA; border-radius:4px; padding:6px 10px; margin-bottom:3px; background:#FFFFFF;">
    <div style="font-size:13px; font-weight:600; margin-bottom:1px;">
      <a href="/001xx000003GYn3CCC" style="color:#0070D2; text-decoration:none;">Initech ↗</a>
    </div>
    <div style="font-size:11px; color:#706E6B;">Software · $2M · Mary Lee</div>
  </div>
</div>
```

If more than 10 records match, show the first 10 and add a note: `<p style="font-size:11px; color:#706E6B; margin:4px 0;">Showing 10 of 47. Refine your search to see fewer results.</p>`

---

## Pattern 3 — Update Confirmation

Use **before** calling an update tool. Show exactly what will change: field name, current value (struck through in red), new value (in green). Always wait for the user to confirm before proceeding. If the current value is empty/null, show `—` as a placeholder in the Current column.

```html
<div style="border:1px solid #FFB75D; border-left:3px solid #FFB75D; border-radius:4px; padding:8px 10px; margin:4px 0; background:#FFF8EE; max-width:100%;">
  <div style="font-size:12px; font-weight:700; color:#7A4F00; margin-bottom:3px;">⚠️ Confirm Update</div>
  <div style="font-size:13px; font-weight:600; color:#181818; margin-bottom:6px;">
    Acme Corporation <span style="font-size:11px; color:#706E6B; font-weight:400;">· Account</span>
  </div>
  <table style="width:100%; border-collapse:collapse; font-size:12px; margin-bottom:6px;">
    <thead>
      <tr style="border-bottom:1px solid #FFD9A0;">
        <th style="text-align:left; color:#7A4F00; font-weight:600; font-size:10px; text-transform:uppercase; padding:0 6px 4px 0; width:35%;">Field</th>
        <th style="text-align:left; color:#7A4F00; font-weight:600; font-size:10px; text-transform:uppercase; padding:0 6px 4px 0; width:32%;">Current</th>
        <th style="text-align:left; color:#7A4F00; font-weight:600; font-size:10px; text-transform:uppercase; padding:0 0 4px 0; width:33%;">New</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td style="color:#444; padding:3px 6px 3px 0; vertical-align:top;">Industry</td>
        <td style="color:#C23934; padding:3px 6px 3px 0; vertical-align:top; text-decoration:line-through;">Finance</td>
        <td style="color:#2E844A; padding:3px 0; vertical-align:top; font-weight:600;">Technology</td>
      </tr>
      <tr>
        <td style="color:#444; padding:3px 6px 3px 0; vertical-align:top;">Phone</td>
        <td style="color:#C23934; padding:3px 6px 3px 0; vertical-align:top; text-decoration:line-through;">555-0100</td>
        <td style="color:#2E844A; padding:3px 0; vertical-align:top; font-weight:600;">555-0200</td>
      </tr>
    </tbody>
  </table>
  <div style="font-size:11px; color:#7A4F00; border-top:1px solid #FFD9A0; padding-top:6px;">
    Reply <b>yes</b> to confirm or <b>no</b> to cancel.
  </div>
</div>
```

---

## Pattern 4 — Insert Confirmation

Use **before** calling a create tool. Show the object type and all fields that will be set. Always wait for the user to confirm.

```html
<div style="border:1px solid #FFB75D; border-left:3px solid #FFB75D; border-radius:4px; padding:8px 10px; margin:4px 0; background:#FFF8EE; max-width:100%;">
  <div style="font-size:12px; font-weight:700; color:#7A4F00; margin-bottom:6px;">📋 Confirm Create · Account</div>
  <table style="width:100%; border-collapse:collapse; font-size:12px; margin-bottom:6px;">
    <tr>
      <td style="color:#444; padding:3px 8px 3px 0; vertical-align:top; width:40%;">Name</td>
      <td style="color:#181818; padding:3px 0; vertical-align:top; font-weight:600;">Acme Corporation</td>
    </tr>
    <tr>
      <td style="color:#444; padding:3px 8px 3px 0; vertical-align:top;">Industry</td>
      <td style="color:#181818; padding:3px 0; vertical-align:top; font-weight:600;">Technology</td>
    </tr>
    <tr>
      <td style="color:#444; padding:3px 8px 3px 0; vertical-align:top;">Phone</td>
      <td style="color:#181818; padding:3px 0; vertical-align:top; font-weight:600;">+1 555-0100</td>
    </tr>
    <tr>
      <td style="color:#444; padding:3px 8px 3px 0; vertical-align:top;">Owner</td>
      <td style="color:#181818; padding:3px 0; vertical-align:top; font-weight:600;">Jane Smith</td>
    </tr>
  </table>
  <div style="font-size:11px; color:#7A4F00; border-top:1px solid #FFD9A0; padding-top:6px;">
    Reply <b>yes</b> to create or <b>no</b> to cancel.
  </div>
</div>
```

---

## Pattern 5 — Success (Update)

Use immediately after a successful update. Name what changed concisely.

```html
<div style="border:1px solid #2E844A; border-left:3px solid #2E844A; border-radius:4px; padding:8px 10px; margin:4px 0; background:#EEF6EF; max-width:100%;">
  <div style="font-size:12px; font-weight:700; color:#2E844A; margin-bottom:2px;">✅ Updated</div>
  <div style="font-size:13px; font-weight:600; color:#181818; margin-bottom:3px;">
    <a href="/001xx000003GYn1AAA" style="color:#181818; text-decoration:none;">Acme Corporation ↗</a>
  </div>
  <div style="font-size:11px; color:#444;">Industry → <b>Technology</b>, Phone → <b>555-0200</b></div>
</div>
```

---

## Pattern 6 — Success (Insert)

Use immediately after a successful record creation. Link directly to the new record. If `ApexAgentUpsertRecords` returns a mix of successes and failures (partial success), show a success card for each record that succeeded and an error card for each that failed — don't combine them into one message.

```html
<div style="border:1px solid #2E844A; border-left:3px solid #2E844A; border-radius:4px; padding:8px 10px; margin:4px 0; background:#EEF6EF; max-width:100%;">
  <div style="font-size:12px; font-weight:700; color:#2E844A; margin-bottom:2px;">✅ Created</div>
  <div style="font-size:13px; font-weight:600; color:#181818; margin-bottom:3px;">
    <a href="/001xx000003GYn1AAA" style="color:#181818; text-decoration:none;">Acme Corporation ↗</a>
  </div>
  <div style="font-size:11px; color:#444;">Account created. <a href="/001xx000003GYn1AAA" style="color:#0070D2; text-decoration:none;">View record ↗</a></div>
</div>
```

---

## Pattern 7 — Error

Use when a tool returns an error or an operation fails. Show the error clearly without technical jargon where possible. Include the record context if known.

```html
<div style="border:1px solid #C23934; border-left:3px solid #C23934; border-radius:4px; padding:8px 10px; margin:4px 0; background:#FDECEA; max-width:100%;">
  <div style="font-size:12px; font-weight:700; color:#C23934; margin-bottom:3px;">❌ Error</div>
  <div style="font-size:12px; color:#3E1C1B; line-height:1.5;">Insufficient access to update Account: Acme Corporation. Contact your Salesforce administrator to request edit permissions.</div>
</div>
```

For tool/query errors where a raw error message is returned, wrap it clearly:

```html
<div style="border:1px solid #C23934; border-left:3px solid #C23934; border-radius:4px; padding:8px 10px; margin:4px 0; background:#FDECEA; max-width:100%;">
  <div style="font-size:12px; font-weight:700; color:#C23934; margin-bottom:3px;">❌ Query Failed</div>
  <div style="font-size:12px; color:#3E1C1B; line-height:1.5; margin-bottom:3px;">Something went wrong retrieving that data.</div>
  <div style="font-size:11px; color:#706E6B; font-style:italic; line-height:1.4;">No such column 'Industrys__c' on entity 'Account'</div>
</div>
```

---

## Pattern 8 — No Results

Use when a search or query returns zero records.

```html
<div style="border:1px solid #DDDBDA; border-left:3px solid #DDDBDA; border-radius:4px; padding:8px 10px; margin:4px 0; background:#F8F8F8; max-width:100%; text-align:center;">
  <div style="font-size:12px; color:#706E6B; margin-bottom:2px;">No accounts matched your search.</div>
  <div style="font-size:11px; color:#AEAEAE;">Try a different name or broaden your filters.</div>
</div>
```

---

## Pattern 9 — User Cancelled

Use when the user replies "no" to a confirmation.

```html
<p style="font-size:12px; color:#706E6B; margin:4px 0;">Cancelled. No changes were made.</p>
```

---

## General Formatting

For plain conversational responses (no data to show), just use `<p>` tags — do not put plain text in cards.

For inline emphasis in prose: use `<b>` for field values and record names, `<i>` sparingly.

For lists of capabilities or steps:
```html
<ul style="margin:6px 0; padding-left:18px; font-size:12px; color:#181818; line-height:1.6;">
  <li>Search and retrieve Salesforce records</li>
  <li>Update field values on existing records</li>
  <li>Create new records with specified field values</li>
</ul>
```

For aggregate/summary data (e.g. counts, totals from a query):
```html
<div style="border:1px solid #DDDBDA; border-left:3px solid #0070D2; border-radius:4px; padding:8px 10px; margin:4px 0; background:#FFFFFF; max-width:100%;">
  <div style="font-size:11px; font-weight:600; color:#706E6B; text-transform:uppercase; letter-spacing:0.5px; margin-bottom:5px;">Opportunity Summary</div>
  <table style="width:100%; border-collapse:collapse; font-size:12px;">
    <tr>
      <td style="color:#706E6B; padding:3px 0; width:55%;">Open Opportunities</td>
      <td style="color:#181818; padding:3px 0; font-weight:700; text-align:right;">24</td>
    </tr>
    <tr>
      <td style="color:#706E6B; padding:3px 0;">Total Pipeline Value</td>
      <td style="color:#181818; padding:3px 0; font-weight:700; text-align:right;">$1,240,000</td>
    </tr>
    <tr>
      <td style="color:#706E6B; padding:3px 0;">Avg Deal Size</td>
      <td style="color:#181818; padding:3px 0; font-weight:700; text-align:right;">$51,667</td>
    </tr>
  </table>
</div>
```