# P4-U2b — DEVICE A VERIFICATION: OPERATIONAL HANDOFF

**Prepared 2026-09-04 at `0f3e868` (which contains `c92065e`). Nothing built,
nothing installed, nothing in production mutated.** This is a procedure, not an
implementation unit.

---

## 0. READ THIS FIRST — THE RUN CANNOT SUCCEED TODAY, AND THE BUILD IS NOT WHY

**Measured read-only on production, 2026-09-04, before writing the rest of this
document.** Two independent gates stop the Share-ON step, both unrelated to U2b:

| | measured |
|---|---|
| `enforcement_active()` | **true** — U6b enforcement is live and denying |
| `membership` rows | **1**, `environment = 'Sandbox'` |
| `membership_state()` for it | **`sandbox_only`** |
| **`connected_member()` for it** | **FALSE** |
| Production membership rows | **0** |

**Server gate.** Under D4's settled semantics a Sandbox-only identity evaluates
`bool_or` to FALSE — it does **not** fall through to the grandfather clause — so
`connected_member()` is false and, with enforcement live, **`posts.insert` is
denied (403)**. Step 1 would fail at the server.

**Client gate, and it bites first.** Device A's Sandbox subscription expired
2026-08-30 (`pending_cleanup_at` is set). `AppMode` resolves from **local
StoreKit**, so the app is almost certainly in **Solo**, where
`canShareWithFollowers` is false and the publish block never executes. There
would be no Share toggle to turn on.

**Neither gate is a U2b defect and neither is fixed by rebuilding.** This is
exactly the QA problem D4 anticipated when it deferred the enforcement-path
mechanism to U6b, and U6b closed still carrying it.

### 0.1 THE OPTIONS, FOR YOUR DECISION — I AM NOT CHOOSING ONE

| | what it needs | what it costs |
|---|---|---|
| **A** | Resubscribe Device A on the **`+devicec`** tester (a different tester would mint a second `originalTransactionId`, a second `membership` row, and the U6b re-bind guard would correctly refuse) **and** flip the U6b **kill switch off** for the run, then back on | Uses the mechanism built for this. **Production runs unenforced for the duration** — minutes, but it is a real production state change to `membership_control` (not to membership state) |
| **B** | A genuine **Production** subscription on Device A | Not available: Production ASSN is unset and **C-31** is outstanding |
| **C** | **Defer** device verification until a production subscriber exists | U2b stays verification-pending; everything else about it is already accepted |

**A sandbox resubscribe ALONE is not sufficient** — it restores the client to
Connected but leaves `connected_member()` false, so the server still denies.
That pairing is the part that is easy to get wrong.

**Everything below is correct and ready the moment one of these is settled.**

---

## 1. REQUIRED REPOSITORY STATE

| | |
|---|---|
| Branch | **`feature/solo-connected`** |
| HEAD | **`0f3e868`** (contains `c92065e`) |
| Working tree | **clean** |

```bash
cd "/Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO" && git status --short && git log --oneline -2
```

Expect no output from `status`, and `0f3e868` / `c92065e` as the two commits.
**These commits are local only; `origin` is still at `78e2002`. Do not push to
build — a local build is what this verification wants.**

## 2. RELEASE BUILD — TO A DEDICATED OUTPUT DIRECTORY

**The dedicated `-derivedDataPath` is the provenance mechanism.** No version
number is incremented (per your instruction). A fresh, empty output directory
means the `.app` that lands on Device A **cannot** be the stale 2026-09-02
product — it can only have come from this build.

```bash
cd "/Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO" && rm -rf ~/u2b-verify && xcodebuild -project MOTIVO.xcodeproj -scheme MOTIVO -configuration Release -destination 'generic/platform=iOS' -derivedDataPath ~/u2b-verify -allowProvisioningUpdates build
```

Signing is **Automatic**, team **`K352DG4UJA`**, bundle **`com.sdsongs.etudes`**.
Expect `** BUILD SUCCEEDED **`.

Product path:
`~/u2b-verify/Build/Products/Release-iphoneos/Etudes.app`

### 2.1 Pre-install checks on the built product

```bash
/usr/libexec/PlistBuddy -c "Print :SUPABASE_URL" ~/u2b-verify/Build/Products/Release-iphoneos/Etudes.app/Info.plist; /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" ~/u2b-verify/Build/Products/Release-iphoneos/Etudes.app/Info.plist; ls ~/u2b-verify/Build/Products/Release-iphoneos/Etudes.app | grep -i storekit || echo "no StoreKit config bundled (C-53 holds)"
```

Must print, in order:
- `https://rlwtqxumfobakvdueugm.supabase.co` — **the production project**;
- `com.sdsongs.etudes` — the Release bundle id, the only one that can transact;
- `no StoreKit config bundled (C-53 holds)` — C-53 removed `Etudes.storekit` from
  the app bundle, and a regression would silence real StoreKit.

## 3. INSTALL — ONLY ONCE DEVICE A IS CONNECTED AND AVAILABLE

Device A currently reports **`unavailable`**. Confirm first:

```bash
xcrun devicectl list devices | grep -i "SD beta burner"
```

It must read `available (paired)`. Then:

```bash
xcrun devicectl device install app --device "SD beta burner" ~/u2b-verify/Build/Products/Release-iphoneos/Etudes.app
```

**Install immediately before the run.** That immediacy, plus the dedicated build
directory, plus the behavioural discriminator in §6, is the approved provenance.

## 4. POST-INSTALL: LAUNCH AND ENVIRONMENT CONFIRMATION

```bash
xcrun devicectl device process launch --device "SD beta burner" com.sdsongs.etudes
```

A successful launch returns the new pid. Then confirm on the device that it is
the production Connected environment:

- the app reaches its normal first screen (no crash-on-launch);
- **Profile → the Connected section reflects the account**, not a signed-out
  state — the app talks to `rlwtqxumfobakvdueugm`, already pinned in §2.1;
- if it shows **Solo**, that is §0's client gate, not a build failure. **Stop and
  tell me** rather than proceeding.

**Tell me when the launch is done and I will run the read-only baseline census.**

## 5. THE MANUAL DEVICE STEPS

**Do not touch any existing session or post. The disposable session is the only
thing created and the only thing removed.**

1. **Create a new session.** Minimal: a title like `u2b verify`, nothing worth
   keeping. **Leave "Share with followers" ON.**
2. **Save it.** → *tell me; I run check **C1***.
3. *(optional, only if the UI makes it easy)* Re-open it, **add one disposable
   attachment and explicitly mark it for sharing**, save. → *tell me; I run
   **C2***. **If this is awkward, skip it and say so — U2c owns the attachment
   invariant and U2b does not need it.**
4. **Re-open the same session, toggle Share OFF, save.** → *tell me; I run
   **C3***.
5. Leave the app **foregrounded for ~30 seconds** so the queue flush runs, then
   *tell me; I run the final census **C4***.

## 6. WHAT I WILL CHECK, AND WHEN

All read-only. **I will not mutate production at any point in this procedure.**

| id | after your step | I verify |
|---|---|---|
| **C0** | launch (§4) | census equals the recorded baseline: posts **101/101/0**, 9 owners, 15 attachment objects, **4 unreferenced**, 3 avatars, 5 comments, 0 shares, 9 follows |
| **C1** | step 2 | `posts` **102**, `pub` **102**, `priv` **0**; the new row identified by `left(md5(id),8)` and its `created_at` inside the window; `unreferenced` still **4** |
| **C2** | step 3 | `attach_refs` **11**, `attachments` objects **16**, `unreferenced` still **4** |
| **C3** | step 4 | **row ABSENT**; any object from C2 absent; `unreferenced` back to **4** |
| **C4** | step 5 | **every value identical to C0** |

**The build identifies itself here.** A pre-U2b build leaves a **demoted row**
(`posts` 102, `priv` 1) at C3; `c92065e` leaves **none**. That is the
discriminator, and it is why no version bump is needed.

**Identifiers:** I will record the disposable post only as `left(md5(id),8)`,
never the raw UUID — the standing rule this repository follows for production
identifiers (U3's cutover, U1's four orphan objects).

## 7. STOP CONDITIONS

**In every case: stop, tell me, and change nothing else. Do not re-toggle, do not
delete by hand, do not "tidy up" — a second attempt destroys the evidence of the
first.**

| symptom | reading | action |
|---|---|---|
| **Share OFF does not remove the row** — C3 shows `posts` 102 | If `priv = 1`: the installed build is **pre-U2b** (demote-not-delete) → §2/§3 provenance failed, rebuild and reinstall. If `priv = 0` and it is still public: the unshare never reached the server → check for a pending `.unshare` (§7.1) before concluding anything | **Stop.** I will read the queue and the row state before any cleanup |
| **An attachment object survives** — C3 shows `unreferenced` **5** | Row deleted, object orphaned: a **B-8-class defect** and a genuine finding. `deletePost` is fail-closed, so this should be impossible — it would mean the object was deleted-then-recreated, or the refs were wrong | **Stop and report.** This outranks completing the run |
| **Census does not return to baseline at C4** | Something other than the disposable fixture changed | **Stop.** I will diff every measure and identify what moved before anything is removed |
| **Any unrelated row or object changed** | Out of scope of this test entirely | **Stop and report** |
| App shows **Solo**, or the save reports a failure | §0's entitlement/enforcement gates | **Stop.** Not a U2b result |

### 7.1 Reading the pending queue, if needed

```bash
xcrun devicectl device copy from --device "SD beta burner" --domain-type appDataContainer --domain-identifier com.sdsongs.etudes --source "Library/Application Support/MOTIVO/SessionSyncQueue_v1.json" --destination ~/u2b-queue.json
```

A convergent run leaves **no item** for the disposable id. An item with
`"op":"unshare"` means the intent is persisted and awaiting a flush — which is
**correct behaviour under a network failure**, not a defect. (`devicectl copy
from` strips xattrs; irrelevant for JSON, and the reason this route is not used
for backup-flag questions.)

### 7.2 If cleanup is ever needed

Only by **explicit id**, never a predicate sweep — B-22's rule. I will propose it
and wait for your approval; I will not run it unprompted.

---

## 8. WHAT I WILL NOT DO

- **Not build, not install, not launch** until Device A is physically connected
  and you explicitly say to proceed.
- **Not mutate production** at any point — every check above is a read-only
  `select`.
- **Not increment `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION`.** The
  dedicated build directory plus immediate install plus the §6 discriminator is
  the approved provenance.
- **Not begin U2c or U2s.**
