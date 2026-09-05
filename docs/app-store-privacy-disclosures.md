# APP STORE PRIVACY DISCLOSURES — DERIVED FROM SHIPPED BEHAVIOUR

**P4-U8, 2026-09-05.** Every entry is traced to code or schema, not composed
from memory. **This is engineering input for the account holder to apply in App
Store Connect; it is not legal advice, and nothing here has been entered in ASC.**

**The controlling fact:** in **Solo, nothing leaves the device at all.**
Everything below applies **only** once the member enables Études Connected, and
most of it only to sessions they explicitly share.

---

## 1. FINAL APP STORE CONNECT MAPPING — FIELD BY FIELD

**Taxonomy re-checked against Apple's App Privacy categories, 2026-09-05.**
Every row is caused by a specific Études data flow, named in the last column.
**Nothing here is inferred from a data type merely existing locally.**

**Answer to Apple's first question — *"Do you or your third-party partners
collect data from this app?"* → YES.** Solo collects nothing, but Connected
does. **Apple's optional-disclosure exemption does NOT apply**: it requires
collection to be occasional and not part of the app's primary functionality, and
Connected sharing is neither. The Solo/Connected split belongs in the privacy
policy and the description, not in the labels.

### Declared

| Apple data type | Linked to user | Used for tracking | Purpose | The Études data that causes the declaration |
|---|---|---|---|---|
| **Contact Info → Name** | Yes | **No** | App Functionality | `account_directory.display_name` and `account_id` |
| **Contact Info → Email Address** | Yes | **No** | App Functionality | `auth.users.email` — present on **all 17** accounts (9 Apple private relay, 8 direct) |
| **User Content → Photos or Videos** | Yes | **No** | App Functionality | image/video attachments **explicitly included** in a shared session; images/videos **sent directly** to another member; **the profile avatar image**; and **generated thumbnail images of score PDFs** in a shared post |
| **User Content → Audio Data** | Yes | **No** | App Functionality | audio attachments explicitly included in a shared session, and audio sent directly to another member |
| **User Content → Other User Content** | Yes | **No** | App Functionality | shared-session `title`, `notes` (only when not marked private), `activity_type`, `activity_detail`, `instrument_label`, `mood`, `effort`; comments and directed replies; profile `location` free text and `instruments`; follow relationships; **PDF documents sent directly to another member** |
| **Identifiers → User ID** | Yes | **No** | App Functionality | Supabase `auth.users` id / Apple `sub` |
| **Purchases → Purchase History** | Yes | **No** | App Functionality | `membership` / `membership_binding` — Apple `originalTransactionId`, product id, status, renewal and expiry dates, `appAccountToken` |
| **Usage Data → Product Interaction** | Yes | **No** | App Functionality | `shadow_enforcement_stat` — user id, which surface was consulted, which entitlement clause decided, bucketed by hour. **79 rows live in production**, so it is genuinely collected |

### NOT declared — with the reason each was excluded

| Apple data type | Why not |
|---|---|
| **Location — Precise or Coarse** | **No CoreLocation import anywhere and no location usage description.** `account_directory.location` is a *user-typed profile string* (5 of 17 populated), declared under Other User Content. **See §6 decision 1** |
| **Health & Fitness** | **No HealthKit import.** `mood` and `effort` are practice self-ratings, not health measurements |
| **Financial Info** | Apple handles payment; the app never sees card or payment data. Purchase *history* is declared above — payment info is not collected |
| **Contacts** | no Contacts framework |
| **User Content → Emails or Text Messages** | **Checked and deliberately excluded.** Comments carry `recipient_user_id` and unread tracking, which is messaging-shaped — but the product has **no inbox, no messages and no DM surface**; the UI is "Reply", "Reply to", "Respond to all commenters". It is post commentary with directed replies, so it is **Other User Content**. Declaring this category would overstate what the app does |
| **Browsing History / Search History** | directory search terms are **never persisted** — `search_account_directory` writes nothing |
| **Device ID / Advertising Data** | none |
| **Crash Data / Performance Data** | **no crash, analytics, advertising or attribution SDK exists in the source** — searched, not assumed |
| **Phone Number, Physical Address, Sensitive Info, Gameplay Content, Customer Support, Other Financial Info** | not collected |

### Tracking

**"Used for tracking" is NO for every declared type.** No third-party analytics,
advertising, attribution or crash SDKs; no data-broker sharing; no joining with
third-party data for advertising or measurement.

### Permissions Apple will cross-check

**Camera, Microphone, Photo Library (read and add)** — the only four usage
descriptions declared, each mapping to attachment capture or selection.

---

## 1b. CORRECTIONS MADE BY THE TAXONOMY RE-CHECK

**Four, all narrowing or relocating existing findings. None adds collection.**

1. **The profile avatar moves to `Photos or Videos`** from Other User Content.
   It is a photograph the user uploads, and Apple's category is "the user's
   photos or videos". **This was the imprecision worth catching** — it also
   widens that row's description, because the avatar is uploaded on joining
   Connected, independently of whether any session is ever shared.
2. **Score PDFs included in a shared post are NOT uploaded at all.**
   `prepareAttachmentForRemoteUpload` generates a **thumbnail image**, and the
   PDF is kept local — *"skip the remote attachment rather than uploading the
   PDF as a fallback"*. So this path contributes an **image**, not a document.
3. **PDFs sent DIRECTLY to another member ARE uploaded**
   (`ConnectedAttachmentSharing`, `mimeType: "application/pdf"`). Apple has no
   Documents category, so these are **Other User Content** — stated explicitly
   so the two PDF paths are not confused.
4. **Comments stay `Other User Content`** rather than moving to *Emails or Text
   Messages* — see the exclusion table for the reasoning.

---

## 2. WHAT NEVER LEAVES THE DEVICE

**Stated as strongly as the architecture allows, because invariant 2 is
structural rather than a policy: *if nobody else can see it, it does not belong
on Supabase*.**

- **Everything, in Solo mode.** No account, no upload.
- **Unshared sessions — entirely.** No server row is created, so no title, no
  notes, no attachments, nothing. Enforced in the client (`op` derived from
  `isPublic`, so the contradictory state does not compile) **and** in the
  database (`posts_insert_owner` requires `is_public = true`).
- **Notes marked private**, even on a shared session — written as `NULL`, and an
  existing server value is actively cleared.
- **Attachments not explicitly included.** Attachments are private by default.
- **Threads, Tasks, the Score library, Journal tint settings and app
  preferences.**
- **Local media** beyond the attachments explicitly included.

---

## 3. THE SHARING DEFAULT — DISCLOSE IT PLAINLY

**A session defaults to being shared with the member's followers.** Measured:
`isPublic = isThoughtMode ? false : !fetchDefaultPostingIsPrivate()`, with
`defaultPrivacy` defaulting to `false`.

**Do not describe Connected as "private by default".** Études *itself* is
private by default; Connected sharing is **on by default and can be turned off**
per session, or reversed globally via **Profile → Default to Private Posts**.

**Thoughts start private** — and are still shareable by choice, because the
Share toggle is available in Thought mode. **Do not write "Thoughts are never
shared".**

---

## 4. DELETION AND RETENTION — what the disclosure must support

- **Account deletion is available in-app** and removes the member's Connected
  content, including comments they wrote and attachments they sent. It **never**
  requires an active subscription.
- **Unsharing deletes** the server post and any storage objects no longer
  needed.
- **Local data is never deleted by any membership event.**
- **On expiry**, Connected presence becomes invisible and a 60-day quarantine
  begins before cleanup; the directory row and display name are retained so
  existing attribution does not break.

---

## 5. THE PUBLIC PRIVACY POLICY — MINIMUM REQUIRED CONTENT

**Destination: `etudes.app/privacy`. Not drafted, not published.** This is the
minimum content the verified architecture requires; the wording is a later step.

| § | must state | determined by |
|---|---|---|
| 1 | **Solo uses no account and sends nothing.** Everything below applies only to Études Connected | shipped behaviour |
| 2 | **What is collected** — the eight categories in §1, in plain language | §1 |
| 3 | **What is never sent** — unshared sessions in full, notes marked private, attachments not explicitly included, score PDFs in posts, Threads, Tasks, the Score library, settings | §2 |
| 4 | **Sharing default** — sessions are shared with followers **by default**; per-session control; Profile → Default to Private Posts; **Thoughts start private but can be shared** | §3 |
| 5 | **Who can see what** — approved followers only; a lapsed member becomes undiscoverable while retained attribution still resolves | U6b / U7 |
| 6 | **Attachments** — private by default, included individually; PDFs sent directly transfer in full; recipients may adopt a copy that later deletion cannot reach | §1b, retention matrix |
| 7 | **Subscription data** — Apple identifiers and status; **we never see payment details** | §1 |
| 8 | **No tracking** — no third-party analytics, advertising, attribution or crash SDKs; no data brokers; no cross-app tracking | §1 |
| 9 | **Retention and quarantine** — access ends at expiry, presence becomes invisible, **60-day quarantine**, then cleanup; resubscribing during quarantine restores everything | CLAUDE.md lifecycle |
| 10 | **Account deletion** — available in-app, **never requires an active subscription**, removes the member's own Connected content including comments and sent attachments; **local data is never deleted by any membership event** | C-35, retention matrix |
| 11 | **Processor and hosting** — Supabase as processor; Apple for sign-in and purchases | **decision — see §6** |
| 12 | **Contact route** for privacy enquiries | **decision — see §6** |
| 13 | **Children / age**, governing law, change notification | **decision — see §6** |

---

## 6. REQUIRES A PRODUCT OR LEGAL DECISION — NOT DETERMINABLE FROM THE CODE

**Six. Each is a genuine choice, not a gap in the investigation.**

1. **Is the profile `location` free-text field declared as Coarse Location?**
   Engineering fact: it is **user-typed text**, never derived from location
   services, and no location permission is requested. **Recommendation: declare
   under Other User Content, not Location** — Apple's Location categories
   describe location-services data. A stricter reading treats any location
   *about the user* as Location. **This is a legal call, and it is the single
   most consequential label decision here.**
2. **`Product Interaction` purpose — App Functionality or Analytics?**
   `shadow_enforcement_stat` exists to operate and verify access control, not to
   study behaviour. **Recommendation: App Functionality.** Adding Analytics is
   defensible and is the more conservative option.
3. **Retention periods.** The 60-day quarantine is architectural, but nothing
   defines how long `membership`, `membership_binding` or
   `shadow_enforcement_stat` are kept. **The policy will have to state
   something.**
4. **Naming Supabase as processor, and the hosting region.** Required by most
   privacy regimes; the region is an account fact I have not read and should not
   guess.
5. **Contact route** for privacy enquiries — an address or form on `etudes.app`.
6. **Age policy, governing law and change-notification wording.**

**None of these blocks entering the labels in §1**, except decision 1, which
changes one selection.

---

## 7. OUTSTANDING — NOT DONE BY THIS UNIT

**Applying these labels in App Store Connect is an account-holder action.**
**Nothing has been entered, and no policy has been drafted or published.** Both
remain Phase 4 exit obligations (condition 6).

The customer-facing wording of the App Store description and the in-app
About/Explore copy is **C-32, jointly owned with RC**. U8 has made the in-app
copy *accurate*; final polish is RC's.
