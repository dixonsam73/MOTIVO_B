# APP STORE PRIVACY DISCLOSURES — DERIVED FROM SHIPPED BEHAVIOUR

**P4-U8, 2026-09-05.** Every entry is traced to code or schema, not composed
from memory. **This is engineering input for the account holder to apply in App
Store Connect; it is not legal advice, and nothing here has been entered in ASC.**

**The controlling fact:** in **Solo, nothing leaves the device at all.**
Everything below applies **only** once the member enables Études Connected, and
most of it only to sessions they explicitly share.

---

## 1. WHAT LEAVES THE DEVICE

| Apple category | What | Where it comes from |
|---|---|---|
| **Identifiers — User ID** | Supabase `auth.users` id; Apple `sub` via Sign in with Apple | required to have a Connected account |
| **Contact Info — Name** | `account_directory.display_name`, `account_id` | the member's chosen profile name |
| **Contact Info — Email** | `auth.users.email` (Apple's private relay if the member chose it) | Sign in with Apple |
| **User Content — Other** | For **shared** sessions only: `session_timestamp`, `title`, `duration_seconds`, `activity_type`, `activity_detail`, `instrument_label`, `mood`, `effort`, and `notes` **only when notes are not marked private** | `posts` columns; `patchPostMetadata` |
| **User Content — Photos/Video, Audio** | Only attachments the member **explicitly includes** in a shared session, plus direct sends | `attachments` bucket; `connected_attachments` |
| **User Content — Other** | Comments the member writes; profile avatar image; location and instruments if entered | `post_comments`; `avatars` bucket; `account_directory` |
| **User Content — Other** | Follow relationships (who follows whom) | `follows` |
| **Purchases — Purchase History** | Apple `originalTransactionId`, product id, status, renewal/expiry dates, `appAccountToken` | `membership`, `membership_binding` |
| **Usage Data — Product Interaction** | `shadow_enforcement_stat`: user id, which surface was consulted, which entitlement clause decided, bucketed by hour | U6a/U6b enforcement telemetry |

**Linked to the member's identity:** yes — everything above is keyed to the
account. **Used for tracking (as Apple defines it): NO.** There are **no
third-party analytics, advertising, attribution or crash-reporting SDKs** — the
source was searched for the usual ones and contains none. No data is shared with
data brokers or joined with third-party data.

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

## 5. OUTSTANDING — NOT DONE BY THIS UNIT

**Applying these labels in App Store Connect is an account-holder action.** U8
produced the content and the mapping; **nothing has been entered.** This remains
a Phase 4 exit obligation.

The customer-facing wording of the App Store description and the in-app
About/Explore copy is **C-32, jointly owned with RC**. U8 has made the in-app
copy *accurate*; final polish is RC's.
