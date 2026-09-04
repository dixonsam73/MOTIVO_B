# P4-U2b — DEVICE A VERIFICATION: **NOT PERFORMED. BLOCKED.**

**2026-09-04, at `c92065e`. Nothing was created, altered or deleted in
production.** The pre-test census below is a read-only capture.

**U2b is NOT formally closed.** This file is the record of why, plus the
baseline and the procedure the run will use once unblocked.

---

## 1. THE FIRST PRE-TEST CONDITION FAILS, AND NOT FOR WANT OF CARE

The brief's first check is *"confirm Device A is running the Release build
containing `c92065e`."* **It cannot be true, because that build does not exist.**

| fact | value |
|---|---|
| Newest **device** build product (`Release-iphoneos/Etudes.app`) | **2026-09-02 11:32** |
| First Phase 4 **client** change (`9f1498e`, C-60) | 2026-09-04 11:42 |
| U2b (`c92065e`) | 2026-09-04 16:34 |
| `origin/feature/solo-connected` | **`78e2002`** — all eight Phase 4 commits are **local only** |

**The installed build predates every client change in this phase by two days.**
It contains neither C-60's fix, nor C-61's durable intent, nor U2b's call-site
flips. A run against it would measure the *pre-Phase-4* app and, worse, would
look like a plausible result: under that build Share OFF **demotes** the row and
leaves it, so the census would not return to baseline and the failure would be
easy to misread as a U2b defect.

### 1.1 TWO FURTHER BLOCKERS, EACH SUFFICIENT ON ITS OWN

**Device A is not reachable from this machine.** `xcrun devicectl list devices`
reports **SD beta burner — iPhone 16e — `unavailable`**. (SD iPhone, Device B, is
`available (paired)`.)

**I cannot drive a physical device in any case.** The simulator control available
to this session is simulator-only; it cannot install to, tap on, or read from a
physical iPhone. Steps 1–5 require a person at the device.

### 1.2 AND THE BUILD STILL COULD NOT BE IDENTIFIED AFTERWARDS

`CLAUDE.md` already records the gap: both configurations are hard-coded
`MARKETING_VERSION 1.0` / `CURRENT_PROJECT_VERSION 131` and neither is
incremented, so **every install reports `1.0 (131)` whatever commit it came
from**, and `devicectl` exposes no install date or hash.

**Two ways to close that, and the second needs no source change:**

- bump `CURRENT_PROJECT_VERSION` before building — **a source change, out of
  scope for a verification-only unit**; or
- **build and install immediately before the run**, and rely on the test's own
  **behavioural discriminator**: under any pre-U2b build a Share-OFF save leaves
  a row (demoted, `is_public = false`); under `c92065e` it leaves **none**. Step 5
  therefore identifies the build as a side effect of measuring the behaviour.

**The second is recommended.** It is the same discriminator logic that made U2a's
pre/post run evidence rather than decoration.

---

## 2. PRE-TEST PRODUCTION CENSUS — READ-ONLY, CAPTURED 2026-09-04

**This is the state the post-test census must return to exactly.**

| measure | value |
|---|---|
| `posts` | **101** |
| — `is_public is true` | **101** |
| — `is_public is not true` | **0** |
| distinct owners | **9** |
| post attachment refs | **10** |
| `attachments` bucket objects | **15** |
| — **unreferenced** | **4** |
| `avatars` bucket objects | **3** |
| `connected_attachments` rows / live | **31 / 6** |
| `post_comments` | **5** |
| `post_shares` | **0** |
| `follows` | **9** |

**`unreferenced` is the sharpest of these.** If Share OFF removed the row but
left its Storage object, this goes 4 → 5 while `posts` returns to 101 — a
B-8-class orphan that a posts-only census would miss entirely.

---

## 3. PREDICTED DELTAS

### 3.1 Transient — after step 2 (Share ON), before step 4

| measure | pre | transient |
|---|---|---|
| `posts` / `pub` | 101 / 101 | **102 / 102** |
| `priv` | 0 | **0** |
| owners | 9 | **9 or 10** — 10 iff Device A's identity has never posted. *Not resolvable from this repository, which deliberately records no production UID.* Either is a pass; the **final** value must be 9 |
| attachment refs | 10 | **11** *(only if the optional attachment step is done)* |
| `attachments` objects | 15 | **16** *(same condition)* |
| `unreferenced` | 4 | **4** — the new object is referenced |

### 3.2 Final — after step 4 (Share OFF)

**Exactly the §2 table. Every value.** In particular `posts` **101**,
`unreferenced` **4**, `comments` **5**, `follows` **9**.

### 3.3 What each outcome would mean

| observation | reading |
|---|---|
| final census == §2 | **U2b verified on device** |
| `posts` 102 with `priv` 1 | the build is **pre-U2b** (demote-not-delete) — §1 |
| `posts` 101 but `unreferenced` 5 | row deleted, **object orphaned** — a real defect, stop and report |
| `posts` 102 with `pub` 102 after step 4 | the unshare never reached the server; check for a pending `.unshare` (§4.4) |

---

## 4. THE PROCEDURE, FOR THE PERSON AT THE DEVICE

**Prerequisite: build and install `c92065e` to Device A in the Release
configuration.** Debug carries `com.samueldixon.motivo.dev`, which App Store
Connect does not know, so entitlement-driven Connected mode is unavailable there.

1. **Census before** — re-run §2's query; it must match §2.
2. **Create a minimal new session, Share ON**, and save. Nothing else: no
   attachment unless doing the optional step, no notes worth keeping. It is
   disposable by construction.
3. **Identify the new row.** It is the only post whose `created_at` is inside the
   run window; the post id equals the session id.
   **Record it as `left(md5(id),8)`, never the raw UUID** — the standing rule
   this repository follows for production identifiers (U3's `membership_cutover`,
   U1's four orphan objects).
4. **Verify** the row exists and `is_public = true`.
5. **Toggle the same session to Share OFF and save.**
6. **Verify the row is absent**, and that no object remains under its prefix.
7. **Census after** — must equal §2 exactly.

### 4.1 Optional attachment step — only if the UI makes it easy

Include **one disposable attachment explicitly marked for sharing**; verify the
Storage object appears on Share ON and is gone after Share OFF.

**Do not turn this into an investigation.** `U2c` owns the direct attachment
invariant, and U2b's acceptance already records that the end-to-end upload
control could not be obtained in the test host (`phase-4-u2b-acceptance.md` §4.1).
If the UI path is awkward, **skip it and say so.**

### 4.2 Do not touch any existing post

The disposable session is the only thing created and the only thing removed.

### 4.3 If step 6 fails

**Stop and report.** Do not repair forward, and do not re-toggle to "fix" the
census — a second attempt would destroy the evidence of the first.

### 4.4 Checking for a pending `.unshare`

The queue is `Application Support/MOTIVO/SessionSyncQueue_v1.json` inside the app
container, readable with `devicectl device copy from`. **A convergent run leaves
no item for the disposable id.** Note that `devicectl copy from` strips xattrs —
irrelevant for JSON content, but it is why this route is not used for backup-flag
questions.

---

## 5. STATUS

**U2b's implementation is accepted (`c92065e`); its device verification is
outstanding and this file is its owner.** Nothing in production was touched to
produce this record.

**No implementation change was made.** U2c and U2s have not begun.
