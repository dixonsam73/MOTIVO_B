# H-1 — PREDICTION, COMMITTED BEFORE MUTATION. PRESENTATION ONLY.

**Inspected at `c2c4719`, 2026-09-10.**
**Presentation-only:** controls move; bindings, behaviour, visibility rules and
membership/account semantics are all preserved. No teen→adult age recheck is
added — that stays scoped to P5-G/legal.

---

## 1. The current structure, measured

`ProfileView` composes (`:350`–`:358`): `profileSection` · `sessionSetupSection`
· then **either** `appSettingsSection` **or** `connectedPromoSection`, chosen by
`appModeManager.canShowConnectedAccountManagement`.

**"Settings" (`sessionSetupSection`, `:682`) currently holds, in order:**
Instruments · Activities · **Default to Private Posts + helper** · **Let other
members find you + helper** · Journal Tint · Tasks · Show Metronome / Drone /
Tasks Pad / Scores / Thread Suggestions / Tuner.

**The two Connected controls sit in the MIDDLE of Settings** — which is exactly
what H-1 corrects.

## 2. THREE SPECIFICS THE APPROVED LIST DID NOT COVER

Reported rather than improvised. **Each is forced by "preserve behaviour and
visibility rules", so none is a free choice.**

**(a) There are TWO sections titled "Account", and they are MUTUALLY EXCLUSIVE —
not a duplicate.** Connected gets `appSettingsSection` (Manage Membership · Sign
out · erase/delete); Solo gets `connectedPromoSection` (Explore Connected ·
About Études · erase/delete). **The approved Account list describes the CONNECTED
one.** Solo's section keeps its own contents — removing Explore Connected or
About Études would be a behaviour change, not a reorganisation.

**(b) "Delete Account & All Études Data" is a STATE-DEPENDENT LABEL, not a fixed
string.** Both sections render the same `eraseAllEtudesDataButton`, whose wording
and blast radius differ between Solo ("Erase All Études Data") and Connected
("Delete Account & All Études Data"). **That distinction is load-bearing (C-35,
and the Phase-1 erase-vs-delete rule), so the button is moved verbatim and its
label logic is untouched.**

**(c) The discovery toggle's gate is NESTED inside the Connected gate.**
`if auth.accountPrivacyState != nil` (`:731`) sits **inside**
`if appModeManager.canShowConnectedAccountManagement` (`:707`). So the new
Connected section's visibility is exactly the outer gate — when it is false
neither control exists and **no empty "Connected" header may appear**.

## 3. PREDICTION

**P1.** A new `connectedPreferencesSection` carries
`Section(header: Text("Connected").sectionHeader())` — **"Connected", not
"Privacy"** — and is composed **between** `sessionSetupSection` and the
Account group.

**P2.** It holds, in order: **Default to Private Posts** + its helper text, then
**Let other members find you** + its helper text. Both blocks move **verbatim**,
including `quietDivider()`, paddings, `.tint`, `.disabled(discoverabilityBusy)`
and the `.onChange` that routes through `applyDiscoverability`.

**P3 — bindings preserved exactly.** `$defaultPrivacy` and `$discoverabilityOn`
are unchanged, and `applyDiscoverability` remains the only writer of the
discovery preference, still going through
`AccountPrivacyService.setLookupEnabled`.

**P4 — visibility preserved exactly.** The section renders only under
`canShowConnectedAccountManagement`; the discovery control keeps its nested
`accountPrivacyState != nil` condition. **Solo sees no Connected section at all.**

**P5 — Settings keeps everything else, in its existing order:** Instruments ·
Activities · Journal Tint · Tasks · the `Show…` toggles. Nothing is added or
removed.

**P6 — Account is untouched.** Both variants keep their contents, their gate and
`eraseAllEtudesDataButton` exactly as they are. The header already reads
"Account", not "Connected Account", so **no rename is needed** — verified, not
assumed.

**P7 — zero behaviour change.** No copy edit (the strings are pinned by
`U8-B5`/`U8-B6`), no semantic change, no new control, no teen→adult recheck.

### Evidence

Structural assertions that the two controls have left Settings and now sit under
a "Connected" header, that both gates survive, and that the helper copy is
byte-identical. Debug and Release clean; **warning delta measured on clean
derived data** — an incremental rebuild reports a false `0`, as C-71 showed;
structured full-suite census.

**A device visual pass will be requested afterwards**, because this materially
changes Profile's composition.
