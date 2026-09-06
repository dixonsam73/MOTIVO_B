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

### ENTERED IN APP STORE CONNECT 2026-09-06 — SAVED, **NOT PUBLISHED**

**All nine types below are configured in ASC with, for every one:**
**Purpose = App Functionality ONLY · Linked to the user = Yes · Used for
tracking = No.** Every other ASC data type is left unselected.

**The Purpose is narrowed from what this document previously allowed.** An
earlier revision called Analytics "defensible" for Product Interaction. **App
Functionality only is the entered and settled position** — `shadow_enforcement_stat`
operates access control rather than evaluating behaviour.

**THE REMAINING ASC BLOCKER IS THE PRIVACY POLICY URL**, which is mandatory once
collection is declared and is currently blank. Intended value:
`https://etudes.app/privacy`. **Nothing is published until it is set.**

### Declared

| Apple data type | Linked to user | Used for tracking | Purpose | The Études data that causes the declaration |
|---|---|---|---|---|
| **Contact Info → Name** | Yes | **No** | App Functionality | `account_directory.display_name` and `account_id` |
| **Contact Info → Email Address** | Yes | **No** | App Functionality | `auth.users.email` — present on **all 17** accounts (9 Apple private relay, 8 direct) |
| **User Content → Photos or Videos** | Yes | **No** | App Functionality | image/video attachments **explicitly included** in a shared session; images/videos **sent directly** to another member; **the profile avatar image**; and **generated thumbnail images of score PDFs** in a shared post |
| **User Content → Audio Data** | Yes | **No** | App Functionality | audio attachments explicitly included in a shared session, and audio sent directly to another member |
| **User Content → Other User Content** | Yes | **No** | App Functionality | shared-session `title`, `notes` (only when not marked private), `activity_type`, `activity_detail`, `instrument_label`, `mood`, `effort`; comments and directed replies; profile `location` free text and `instruments`; follow relationships; **PDF documents sent directly to another member** |
| **User Content → Emails or Text Messages** | Yes | **No** | App Functionality | **Private directed communication — see §1c.** Comment `body` text with its author, named recipient and unread state; and the direct-send envelope (sender, recipient(s), attachment name, filename, mime type, byte/page count, delivery and read timestamps). **No subject line and no composed message text exists on the direct-send path** |
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

## 1c. `Emails or Text Messages` — RE-EXAMINED, AND MY EARLIER EXCLUSION WAS WRONG

**Determination: DECLARE IT.** Apple's guidance covers in-app private
messaging, including non-SMS, and Études has two surfaces that qualify.

### THE CORRECTION — I read the UI instead of the policy

An earlier revision of this document excluded the category, reasoning that
comments were *"post commentary with directed replies"* visible to approved
followers. **That was wrong, and the mechanism matters more than the verdict:
I inferred visibility from UI wording ("Reply", "Respond to all commenters")
without reading the policy.** The deployed policy says otherwise:

```
post_comments_select_visible:
  (auth.uid() = author_user_id)
  OR (enforcement_gate('post_comments.select')
      AND (auth.uid() = owner_user_id OR auth.uid() = recipient_user_id))
```

**A comment is visible ONLY to its author, the post owner, and the named
recipient — never to followers at large.** It carries a text `body`, a sender
(`author_user_id`), a named recipient (`recipient_user_id`), and unread tracking
(`has_unread_private_comments`, `get_unread_private_comment_groups`). **That is
private, directed, text-bodied communication between named individuals.**

### The direct-send path qualifies too, on structure rather than on text

`connected_attachments`, examined by interaction rather than terminology:

| Apple's elements | Études |
|---|---|
| sender | `sender_user_id` |
| recipients | `recipient_user_id`, one row per chosen person (individually or via an Ensemble) |
| private to the recipient | RLS `connected_attachments_select_recipient` |
| a received list | `fetchReceived()` — an inbox in function, not in name |
| read state | `viewed_at`, `markViewed`, plus `saved_to_scores_at` |
| contents | the file, plus a sender-influenced `attachment_name` / `filename` |
| **subject line / composed body** | **NONE — `deliver(_ reference:, to recipientUserIDs:)` takes no text, and no field exists to write one** |

**The absence of a typed message body does not exempt it.** Apple's category
enumerates "sender, recipients, and contents", and all three are present and
private. The narrower reading — that this is file transfer rather than
messaging — is arguable, but **under-declaring is the worse error**, and the
comment surface qualifies on its own regardless.

### The narrowest accurate description

**Under this category Études collects:** the text `body` of a comment together
with its author, named recipient, post context and unread state; and, for a
direct send, the sender, each recipient, the attachment name and filename, mime
type, byte and page counts, and delivery/read timestamps.

**Études does NOT collect any subject line, and collects no composed message
text on the direct-send path, because the feature provides no way to write
one.** The transferred file's own bytes remain declared under Photos or Videos,
Audio Data, or Other User Content — this category covers the private-delivery
envelope and the comment text, not a second copy of the media.

**Ordinary session content, profile fields and follow relationships stay under
Other User Content** — they are not directed communication.

---

## 1d. MEASURED RETENTION, AND THE HOSTING REGION

**Measured, not read from prose.**

| table | deletion path found | retention |
|---|---|---|
| `membership` | **none** — no `pg_cron`, no deployed function DELETEs it, and the U7 cleanup worker does not touch it | **indefinite** |
| `membership_binding` | **none**, same three checks | **indefinite** |
| `shadow_enforcement_stat` | **none**, same three checks | **indefinite** |

**The only removal path for all three is the `auth.users` FK cascade** —
`confdeltype = 'c'` on each — i.e. **explicit account deletion**. Ordinary
expiry retains them, exactly as the retention matrix specifies for the first
two.

**`shadow_enforcement_stat` is the finding worth flagging:** it is
**user-linked telemetry with no retention limit and no mention in the retention
matrix**, which was written before it existed. 79 rows today. **A policy
claiming any bounded retention for it would be false as things stand.**

**Hosting region — authoritative, from `supabase projects list`:**
**`eu-central-1`** (AWS Frankfurt, EU), project created 2025-12-30,
PostgreSQL 17.6.

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

## 5b. FACTS ESTABLISHED FOR THE POLICY — AND FOUR THAT ARE NOT

**Searched the repository, Info.plist, build settings and Supabase project
configuration, 2026-09-06.**

| point | finding |
|---|---|
| **Controller identity** | **NOT established by project records.** The only trace of "SD Songs" anywhere is the bundle identifier `com.sdsongs.etudes`. **No company name, number, registered address or copyright string exists** in the repo or in production configuration. **A bundle id is not evidence of a legal entity.** The intended controller is **SD Songs Ltd**, confirmed by the account holder; **company number and registered office remain to be supplied** |
| **Privacy contact route** | **NONE EXISTS.** No `mailto:`, no support address, and **no reference to `etudes.app` anywhere in the app**. Intended: `privacy@etudes.app` — **requires setup and verification before publication** |
| **Age gate** | **NONE.** No age gate and no date-of-birth collection anywhere |
| **Self-serve data export** | **NONE.** Profile editing and in-app account deletion exist; there is no export feature, so access and portability requests must be handled manually |
| **Hosting region** | **`eu-central-1`** (AWS Frankfurt, EU) — authoritative, from `supabase projects list` |
| **Processors established** | **Supabase** (hosting/processing) and **Apple** (Sign in with Apple, subscription purchases and status) |

---

## 6. REQUIRES A PRODUCT OR LEGAL DECISION — NOT DETERMINABLE FROM THE CODE

**Six. Each is a genuine choice, not a gap in the investigation.**

1. ~~Profile `location` as Coarse Location?~~ **DECIDED 2026-09-05 — stays
   Other User Content.** It is manually entered profile content; Études does not
   obtain or derive device location. **Do not declare Precise or Coarse
   Location.**
2. ~~`Product Interaction` purpose?~~ **DECIDED 2026-09-05 — App Functionality
   ONLY, not Analytics.** Its purpose is entitlement and enforcement operation,
   not evaluation of user behaviour.
3. **Retention periods — now MEASURED as indefinite** (§1d). The 60-day
   quarantine governs Domain 3 content; `membership`, `membership_binding` and
   `shadow_enforcement_stat` are kept until account deletion. **The policy must
   either state that honestly or a limit must be introduced** — the second is a
   product change, not a copy change.
4. ~~Hosting region unknown.~~ **MEASURED: `eu-central-1` (AWS Frankfurt, EU).**
   What remains is the *decision* to name Supabase as processor and to state the
   region publicly.
5. **Contact route** for privacy enquiries — an address or form on `etudes.app`.
6. **Age policy, governing law and change-notification wording.**

**None of these blocks entering the labels in §1**, except decision 1, which
changes one selection.

---

## 7. OUTSTANDING — NOT DONE BY THIS UNIT

**The nine data-label selections are ENTERED AND SAVED in App Store Connect as
of 2026-09-06, and are NOT PUBLISHED.**

**Condition 6 now has exactly ONE remaining item: the Privacy Policy URL.** It is
mandatory in ASC once collection is declared, it is currently blank, and the
intended value is `https://etudes.app/privacy`. The policy text is drafted and
under review; **it is not published, and `etudes.app` has not been modified.**

**Condition 6 must NOT be marked complete until that URL resolves to a published
policy and the ASC configuration is published.**

The customer-facing wording of the App Store description and the in-app
About/Explore copy is **C-32, jointly owned with RC**. U8 has made the in-app
copy *accurate*; final polish is RC's.
