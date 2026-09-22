# Founding 500 — F1 diagnostic preparation, for Codex review

> **HISTORICAL AND CLOSED, 21 September 2026 evening.** The probe existed to gather
> admission evidence for the **retired custom-grant route**. It **was never run on a
> device**, and it has been **removed as a verified pure deletion** — `git diff`
> against the recorded base blob `ec67523d9181dd665ee14860e36e302c43fbc5f4` was empty.
> No identifier was ever extracted, so §6's transfer mechanism was never built.
>
> **Nothing here is scheduled or requested.** The durable lesson worth keeping is
> §6.2's: an Études reinstall deletes the local-first container, and calling that
> "destructive of nothing" was the most serious error in this workstream.

**21 September 2026. PREPARED, NOT RUN. NOTHING HAS TOUCHED A DEVICE.**

Prepared under Samuel's instruction to proceed with diagnostic preparation, with
independent Codex review before any device execution. **No device install, uninstall,
reset, account switch or live Apple request has been made. No purchase. No TestFlight
upload. No deployment, commit or push. No F2 or feature work.** Two local builds were
run, which is the whole of what was executed.

---

## 1. What exists now

| Item | State |
|---|---|
| `MOTIVO/F1AppTransactionProbe.swift` | **New, untracked.** 1 file |
| `MOTIVO/MOTIVOApp.swift` | **+5 lines**, one call site, inside the existing `.onAppear` |
| Release build, `generic/platform=iOS Simulator` | **BUILD SUCCEEDED** |
| Debug build | **BUILD SUCCEEDED** |
| New warnings | **None.** The eight warnings present are pre-existing, in `VideoRecorderView`, `AttachmentStore`, `AttachmentViewerView` and `BackendSessionDetailView`. Neither changed file emits one |
| Unrelated working-tree changes | **Untouched** — `AGENTS.md` and the two invitation documents are exactly as they were |
| `git diff --stat MOTIVO/` | `1 file changed, 5 insertions(+)` |

**Reversal is TARGETED, not a working-tree discard — corrected after review.** My
first version said `git checkout MOTIVO/MOTIVOApp.swift`, which **discards every
change in that file**, including any unrelated edit that arrives before cleanup. That
would destroy someone else's work to remove mine.

The recorded base blob for `MOTIVO/MOTIVOApp.swift` at preparation time is
**`ec67523d9181dd665ee14860e36e302c43fbc5f4`**. Cleanup removes **only the five
inserted lines** and the probe file, then verifies:

```bash
# 1. Delete the probe file.
rm MOTIVO/F1AppTransactionProbe.swift

# 2. Remove ONLY the five inserted lines (the F1 comment block and the call),
#    by hand or by a targeted patch. Do NOT check out the whole file.

# 3. Verify the targeted reversal against the recorded base.
git diff ec67523d9181dd665ee14860e36e302c43fbc5f4 -- MOTIVO/MOTIVOApp.swift
#    Empty  -> the file is byte-identical to its pre-probe state AND carried no
#              other edits. Non-empty -> inspect: any remaining hunk must be
#              somebody else's intended change, never a probe remnant.
```

**A `git checkout` of the whole file is not the cleanup and must not be used.**

### 1.1 Removal condition, recorded before the probe runs rather than after

**This file and its call site are deleted the moment F1 is scored**, and the removal is
**verified as a pure deletion** — `git diff` against the pre-probe tree empty, both
configurations compiling clean — in the same family as `ActivationTrace`,
`MembershipTrace`, `JWSFreshnessProbe` and `C42StorefrontProbe`. The condition is
written here, in the probe's own header, and in the call-site comment, so it is
discoverable from any of the three.

**It must not ship.** `fileSystemSynchronizedGroups` auto-includes everything in
`MOTIVO/` in the app target — that is exactly how `Etudes.storekit` came to ship inside
a Release binary (C-53) — so this file **is** in the app target by construction. The
protection is the removal condition and the inertness below, not the file's location.

---

## 2. What the probe does, and what makes it safe

### 2.1 Inert unless explicitly invoked

`runIfRequested` returns immediately unless the launch argument **`-F1Probe`** is
present. An ordinary launch — TestFlight, Xcode, anything — executes nothing. There is
one `hasRun` guard so a re-entrant `onAppear` cannot read twice.

**A launch argument, not `#if DEBUG`, and that is forced rather than chosen.** Debug
carries `com.samueldixon.motivo.dev`, which App Store Connect does not know; an app
transaction read there would concern a different app or be absent. The probe must run
in **Release**, so it cannot hide behind `DEBUG` — C-44's lesson that the only build
able to execute these paths is the one without `#if DEBUG` diagnostics.

### 2.2 What it cannot do

It performs **no purchase, no authentication, no backend write, no activation, no
product load, no entitlement read and no AppMode change**. It makes no network request
of our own. It reads `AppTransaction.shared` once and logs the outcome. That is the
entire behaviour, and the file imports only `Foundation`, `StoreKit` and `os`.

### 2.3 Public output — presence only

Emitted via `os.Logger` with `privacy: .public` on every interpolation (required for
Release readability — the C-44 lesson where `NSLog` with `%@` arrived as `<private>`
and the first failure could not be diagnosed at all):

- whether the read **threw**, with an **allowlisted error category** — a fixed case
  name, plus a numeric `URLError` code where one exists. **Truncation was not
  sanitisation and is gone**: an identifier, credential fragment or URL is easily
  shorter than 200 characters, and the claim that the clip excluded token-sized data
  was false. No `NSError` userInfo, no URL, no nested payload, no
  `localizedDescription`. An unrecognised error yields its Swift **type name** only —
  a compile-time identifier that cannot carry instance data (replaceable with a bare
  `"unrecognised"` if review prefers zero detail);
- **elapsed milliseconds**;
- **verified or unverified** — recorded rather than unwrapped blindly, since
  `.unverified` still carries a payload;
- **`environment`** and **`bundleID`**;
- **`appTransactionID_present`** — a **boolean**.

**Never emitted, in any form: the `appTransactionID` itself, any digest of it, the
JWS, or any credential.** The JWS is not read at all. The identifier is a globally
unique per-Apple-Account value stable across devices, redownloads, refunds and
storefront changes, so it is a durable pseudonymous identifier for a person — and, as
Codex established, **a digest of a stable identifier is still a stable correlator**,
not anonymisation. Presence only.

---

## 3. Signing and install route — concrete

| | |
|---|---|
| Device | **Device A — "SD beta burner", iPhone 16e**, as Samuel proposed |
| Bundle | `com.sdsongs.etudes` — the **established Release bundle already installed there** |
| Configuration | **Release.** Enforced by `SchemeConfigurationGuardTests`, which fails the suite if the Run action stops building Release or pins a StoreKit configuration |
| StoreKit configuration | **None.** Must not be pinned — a pinned configuration silences real StoreKit even in Release |
| Signing | `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = K352DG4UJA` (measured in `project.pbxproj`) |
| Route | **Xcode → Run**, with `-F1Probe` added to the scheme's *Arguments Passed On Launch* |

### 3.1 Data preservation — the mechanism, not an assurance

Xcode Run over an existing install of the **same bundle identifier** is an **in-place
update**. It does not uninstall and does not delete the data container: the journal,
Scores, media and `AttachmentPrivacy.json` survive. **It does rotate the container
UUID**, which this project established from the Phase 2 restore work as routine on any
ordinary update rather than a restore artefact — which is why `AttachmentPathResolver`
exists and why stale absolute paths are a normal condition.

**Nothing in this plan deletes, resets or uninstalls anything.** Samuel offered to
clear Device A's app data; **that is not needed and is not requested.**

**Pre-flight checks, to be recorded before and after the install** so preservation is
measured rather than asserted:

| Check | Before | After |
|---|---|---|
| Journal session count, visible in the app | record | must match |
| Scores library item count | record | must match |
| Connected identity still signed in | record | must match |
| Local profile name present | record | must match |

If any differs, **stop and report** — do not proceed to S4.

### 3.2 Scheme hygiene

`-F1Probe` is added to the scheme's Run arguments for this session and **removed
afterwards**. The shared scheme has been silently reverted twice before (C-52, and its
second recurrence at `3d49c4c`), so the argument's removal is checked explicitly rather
than assumed, and `SchemeConfigurationGuardTests` is run afterwards.

---

## 4. What this test can and cannot establish

**Four distinct provenances, and they are not interchangeable.** Codex's warning is
adopted as the plan's own framing:

| # | Provenance | What this run produces |
|---|---|---|
| 1 | **Xcode development install** — what this test uses | The observation |
| 2 | **TestFlight** | Not exercised |
| 3 | **Public App Store** — the only one the design admits | **Not exercised, and cannot be inferred** |
| 4 | **StoreKit-testing configuration** | Already measured: self-signed certificate, inadmissible |

**This run cannot prove production admission works.** It also cannot close the
**fresh-install** gate, because S0 installs over an existing Études installation
(F1 §6.2a). What it can establish is the *shape* of the artefact on a development
install and whether `AppTransaction.shared` succeeds, throws, or prompts.

### 4.1 Predictions, committed before the run — NARROWED after review

Written before the run so the result is binary. **Each is a statement about THIS
invocation on THIS provenance, not a general law** — the first version generalised and
is corrected.

| | Outcome | What it means, and what it does NOT |
|---|---|---|
| **P1** | `AppTransaction.shared` **throws** | **This invocation failed**, with an allowlisted category. It does **not** establish that development installs generally lack an app transaction — one throw is one observation, and transient causes (network, StoreKit state) are inside the category set. A repeat is needed before any general claim |
| **P2a** | Returns **`.verified`** | StoreKit's own validation passed. **This is not our server's verdict:** `verifyChain` against the pinned Apple Root CA G3 is a different check, and only that one governs admission |
| **P2b** | Returns **`.unverified`** | A payload exists and StoreKit rejected it. The fields are still recorded, with the verification category — distinguishing this from P2a is the point, since treating them alike is the mistake the attestation path exists to avoid |
| **P3** | `environment` reports `xcode` or `sandbox` | Records the environment **string only**. Neither value measures acceptance by our chain verifier, and neither is public-distribution evidence |
| **P4** | `environment` reports **`production`** | **Record it and do not celebrate it.** On a development install this would be unexpected; it still says nothing about public App Store admission, and must not be promoted into it |
| **P5** | A system prompt appears | `AppTransaction.shared` is not silently cheap on this provenance, and the claim flow's UX must account for it. A human observation, not a log line |

**None of P1–P5 is a failure**, and none is closable by a single run.

## 4.2 What an ordinary launch already does — scoped, not bypassed

**The probe adds nothing to the network. The app's normal startup still runs beside
it, and my earlier "nothing is purchased, deleted, reset or uploaded" overclaimed
about the SESSION rather than about the probe.** Corrected, and scoped from source
rather than suppressed — a large lifecycle bypass would be a bigger change than the
diagnostic it serves.

Reading `MOTIVOApp.swift`'s launch `.onAppear`, a Device A launch also runs:

| Runs | Effect |
|---|---|
| `SharingHandoffRecovery.run` | Local only — Core Data and the queue file |
| `connectedMembershipStore.start()` | **Contacts Apple** — loads products and refreshes entitlement. Ordinary StoreKit traffic |
| `appModeManager.applyActivation` | Local mode resolution |
| `syncPendingLocalAvatarToConnectedIfNeeded` | **May write to the backend** if a pending avatar exists |
| `ensureValidSession` | **Guarded by `canViewFeed`.** Device A is unentitled → Solo → expected to be skipped |
| `StagingStore.bootstrap()` | Local |
| `AppleCredentialStateMonitor.check` | **Checks Apple credential state**, and can sign the user out if the credential was revoked |
| Attestation at launch | Invariant needs **locally entitled**; Device A's Sandbox subscription is expired → expected to be skipped |

**So the honest statement is: the probe introduces no purchase, no authentication, no
backend write and no activation — and the app does what it always does on launch.**
The two rows marked "expected to be skipped" are expectations from source, not
guarantees; if Device A turns out to be entitled, more runs and that should be noted
rather than suppressed.

**Nothing here is a reason to bypass startup.** Suppressing normal launch behaviour
for a diagnostic would be a far larger and riskier change than the diagnostic.

---

## 5. The steps

**S0–S3 and S6 are prepared. S4–S5 need the §6 transfer mechanism reviewed first.**

| Step | Action |
|---|---|
| **S0** | Record the §3.1 pre-flight values. Add `-F1Probe` to the scheme's Run arguments. Build and Run to Device A, Release, StoreKit configuration None |
| **S1** | Confirm the §3.1 after-values match. **Stop and report if any differ** |
| **S2** | Read the Xcode console for `[F1]` lines. Record threw/ms/verification/environment/bundleID/`appTransactionID_present`, **and whether any system prompt appeared** — a human observation, not a log line |
| **S3** | **Inertness control.** Quit and cold-launch from the **Home screen**. Expect **zero `[F1]` lines**, because a Home-screen launch does **not** inherit Xcode's Run arguments — this is a positive check that the probe is inert in ordinary use, not a second measurement |
| **S3b** | **Second measurement: Run again from Xcode**, argument still set. Record the same fields. **This is still not a cache-versus-network measurement** |
| **S4** | *Gated on §6* — read-only `GET /inApps/v1/subscriptions/{id}` against the environment named by the stored source |
| **S5** | *Gated on §6* — record response shape only |
| **S6** | Remove `-F1Probe` from the scheme. Apply the §1 **targeted** cleanup and verify against the recorded base blob. Re-run `SchemeConfigurationGuardTests` |

**S3 was wrong in the first version and is the correction worth noting.** It told the
operator to cold-launch from the Home screen and record `[F1]` lines — which would
have produced **none**, because launch arguments set in an Xcode scheme apply only to
launches Xcode starts. The operator would have seen silence and reasonably read it as
a probe failure. Split into S3 (inertness control, expects silence) and S3b (the
actual repeat, from Xcode).

---

## 6. The identifier transfer for S4 — a concrete minimal mechanism

**Not built, and specified rather than avoided.** My first version recommended
"option D — don't run S4", which Codex correctly read as replacing an authorised piece
of preparation with a way of not doing it. The mechanism below is the proposal; it is
**not implemented**, and no live Apple call is authorised.

### 6.1 The requirement

S4 needs the actual `appTransactionID`, and §2.3 forbids it from ever reaching a
public log. It must therefore leave the device by a route that is **not a log**, is
**not a whole-container download**, and **retains nothing afterwards**.

### 6.2 Proposed mechanism — one file, one copy, deleted

**Write.** Under the same `-F1Probe` argument, and only then, the probe writes the
identifier and nothing else to a single file in the app's **temporary** directory:

```
<app container>/tmp/f1_apptx.txt        // the identifier, one line, no newline padding
```

`tmp/` deliberately, not `Documents/`: it is already excluded from backup by
`BackupPolicy`, is not user data, and is not swept by anything that matters. The file
is written **only** when the argument is present, so an ordinary build cannot create it.

**Retrieve.** A single-file copy, which `devicectl` supports directly — verified
locally from `xcrun devicectl device copy from --help`:

```bash
xcrun devicectl device copy from \
  --device "<Device A>" \
  --domain-type appDataContainer \
  --domain-identifier com.sdsongs.etudes \
  --source tmp/f1_apptx.txt \
  --destination ./f1_apptx.txt
```

**No whole-container download**, so no unrelated personal data moves. This is exactly
the concern that made Xcode's Devices-window container download unacceptable.

**Retention and removal, specified rather than assumed:**

1. The probe **deletes any existing `f1_apptx.txt` at the start of every run**, so a
   stale value can never be read as a fresh one.
2. After S4, the local copy is deleted, and the on-device file is deleted by an
   ordinary launch of the app (the probe's own start-of-run delete) or by removing the
   app's tmp file explicitly.
3. **S6's probe deletion removes the writer entirely**, so the file cannot be
   recreated once F1 is scored.
4. The value is **never** pasted into a review document, a commit, a log, or any
   message to either agent. It is used once, for the S4 request, and discarded.

### 6.3 Why not the alternatives

| | Rejected because |
|---|---|
| `Logger` with `privacy: .private` | Still writes the value into the unified log, and its off-Xcode redaction is an assumption I have not measured |
| Xcode Devices → Download Container | Pulls the whole personal container for one string |
| On-screen display | Needs temporary UI, and a screenshot defeats it |
| Not running S4 | Was my first recommendation and is withdrawn — it avoids the mechanism rather than proposing one |

### 6.4 Not yet written

**The file-write is NOT in the probe as it stands.** The probe currently emits
presence only and writes nothing. If this mechanism is accepted, it is roughly ten
lines under the same argument guard, with the start-of-run delete; if it is rejected,
the probe stays as it is and S0–S3b still stand on their own.

---

## 7. Short instructions for Samuel

Not a request to act yet.

> 1. Create a fresh Sandbox tester in App Store Connect if you want one for later
>    steps. **Do not sign in to it yet**; it is not needed for S0–S3b.
> 2. Connect Device A (the beta burner) to the Mac.
> 3. Before anything: open Études and note **how many journal sessions and Scores**
>    you can see, and that you are still signed in to Connected.
> 4. In Xcode: Product → Scheme → Edit Scheme → Run → Arguments, add **`-F1Probe`**.
>    Check Run is **Release** and StoreKit Configuration is **None**.
> 5. Run to the device. **Watch the screen during launch** and tell us if any Apple
>    prompt or sign-in sheet appears.
> 6. Check the journal and Scores counts still match step 3.
> 7. Copy the Xcode console lines beginning `[F1]`. They contain no identifiers.
> 8. Quit the app and launch it **from the Home screen**. You should see **no new
>    `[F1]` lines at all** — that is the expected result and confirms the probe stays
>    switched off in ordinary use.
> 9. Then **Run from Xcode once more** for the second reading, and copy the new
>    `[F1]` lines.
> 10. Afterwards, remove `-F1Probe` from the scheme.
>
> **Nothing is purchased, deleted, reset or uploaded by the diagnostic, and your
> journal, Scores and media are not touched.** The app's ordinary startup still runs
> as it always does — it checks StoreKit and your Apple sign-in state, exactly as on
> any normal launch (§4.2).

---

## 8. Open, and not blocking this preparation

- **ASC introductory-offer configuration** — still uninspected. Samuel reports nothing
  set up at the App Store yet; per Codex, that is **not** to be read as the already-used
  Sandbox IAP products not existing. Not needed for S0–S3.
- **Fresh-install evidence** — not closable here (§4).
- **Public App Store admission** — not closable here, and no result from this run may
  be scored against it.
- **Adult assurance, server trust, retention** — open, outside F1.
- **F2** — not started and not authorised.

---

## 9. Dispositions on the diagnostic preparation review

| | Disposition | Where |
|---|---|---|
| **D1** Arbitrary error strings leak despite truncation | **Agree, and the false claim is withdrawn.** `String(describing:)` is gone. Errors now map to a **fixed allowlist** — `StoreKitError` case names, a numeric `URLError` code, the six `VerificationError` cases — with no userInfo, URL, payload or `localizedDescription`. My comment claimed truncation excluded token-sized data; **an identifier or credential fragment is far shorter than 200 characters**, so that was simply wrong. Unrecognised errors yield the Swift **type name** only, which is a compile-time identifier and cannot carry instance data; **say the word and it becomes a bare `"unrecognised"`** | Probe §"WHAT IT MAY AND MAY NOT EMIT", `category(of:)`, plan §2.3 |
| **D2** Home-screen launch loses Xcode arguments | **Agree, and it would have produced a false negative.** The old S3 told the operator to cold-launch from the Home screen and read `[F1]` lines — there would have been **none**, and silence reads as a broken probe. Split: **S3 is now an inertness control expecting zero lines**, S3b is the repeat **from Xcode**. Samuel's instructions say so explicitly | §5, §7 steps 8–9 |
| **D3** Predictions overgeneralise | **Agree.** P1 now states only that **this invocation** failed. P2 splits into **P2a verified / P2b unverified**. Added explicitly: **StoreKit's `.verified` is not our server's verdict** — `verifyChain` against the pinned anchor is a different check and only it governs admission — and an unexpected `production` value is **recorded without being promoted** into public-distribution evidence | §4.1 |
| **D4** Ordinary startup still runs | **Agree — I overclaimed about the session, not the probe.** New §4.2 enumerates the launch sequence from source: StoreKit product/entitlement load, Apple credential-state check, possible avatar sync, and the two paths expected to be skipped on an unentitled device. **The probe introduces none of it; the app does what it always does.** No lifecycle bypass proposed — suppressing startup would be a larger change than the diagnostic | §4.2, §7 closing note |
| **D5** Prepare the S4 transfer, do not omit it | **Agree — "option D" was avoiding the authorised work.** Concrete mechanism specified: a single file in the app's **`tmp/`** (already backup-excluded, not user data), written only under `-F1Probe`, retrieved by **`devicectl device copy from --domain-type appDataContainer`** — verified locally as supporting **single-file** copy, so **no whole-container download**. Retention and removal specified: deleted at the start of every run, after S4, and permanently when the probe is removed; never pasted into any document, commit, log or message. **Not yet written into the probe** — roughly ten lines, pending this review | §6 |
| **D6** Targeted cleanup only | **Agree.** `git checkout MOTIVO/MOTIVOApp.swift` would discard **any** unrelated edit that arrives before cleanup — destroying someone else's work to remove mine. Cleanup now removes **only the five inserted lines** plus the probe file, and verifies against the **recorded base blob `ec67523d9181dd665ee14860e36e302c43fbc5f4`**. A whole-file checkout is explicitly ruled out | §1 |

**One defect found while re-verifying, not raised by the review:** the first allowlist
omitted `StoreKitError.unsupported` and produced a **"switch must be exhaustive"
warning** — an added warning, which this project does not ship. Fixed; both
configurations now build with **zero warnings from either changed file**.

**Build evidence is compile evidence only.** Device signing and install remain
untested, as the review says.
