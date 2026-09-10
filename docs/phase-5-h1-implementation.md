# H-1 — IMPLEMENTATION READY. PRESENTATION-ONLY. AWAITING A DEVICE VISUAL PASS.

**NOT CLOSED.** Prediction: `docs/phase-5-h1-prediction.md` (`352cc2c`),
committed before mutation. It materially changes Profile's composition, so a
device pass is requested.

## 1. Result against the prediction

| | Prediction | Outcome |
|---|---|---|
| **P1** | new `connectedPreferencesSection`, header **"Connected"**, placed between Settings and Account | **MET** |
| **P2** | both controls + helper text move **verbatim** | **MET — proven, see §2** |
| **P3** | bindings and the sole discovery writer unchanged | **MET** |
| **P4** | gates preserved; no empty header in Solo | **MET** |
| **P5** | Settings keeps its own controls in order | **MET** |
| **P6** | Account untouched; already reads "Account" | **MET** |
| **P7** | zero behaviour change, no copy edit, no age recheck | **MET** |

**Debug and Release clean, on CLEAN derived data — 187 / 175, warning delta
ZERO.** **158 of 158 tests pass**, structured census. Two files: one product
file, one new test file.

## 2. The move is provably verbatim

Every line removed from `sessionSetupSection` reappears **byte-identical** in the
new section, with exactly **two** exceptions:

```
'if appModeManager.canShowConnectedAccountManagement {'
'}'
```

— the wrapper that became the new section's own gate. Nothing else changed:
`quietDivider()`, paddings, `.tint`, `.disabled(discoverabilityBusy)`, the
`.onChange` routing to `applyDiscoverability`, and both helper strings (pinned by
`U8-B5`/`U8-B6`) are untouched.

## 3. The three specifics, resolved as predicted

**(a)** The two "Account" sections are **mutually exclusive**, not duplicated —
Connected gets Manage Membership / Sign out / delete; Solo gets Explore Connected
/ About Études / erase. **Both kept exactly as they are.** Removing Solo's
entries would have been a behaviour change.

**(b)** `eraseAllEtudesDataButton` is **one button with a state-dependent label**
— "Erase All Études Data" in Solo, "Delete Account & All Études Data" in
Connected. Load-bearing (C-35). **Moved nowhere, changed in no way.**

**(c)** The discovery gate is **nested inside** the Connected gate, so the new
section's visibility is exactly the outer gate. **Solo renders no "Connected"
header at all** — asserted, not assumed.

## 4. Device visual checklist

Release build. **No account state, purchase or destructive action; nothing
touches production.**

**A — Connected (or Force Connected, which is enough here: this is client
presentation only and that is exactly what H-1 changed)**
1. Profile shows **three** sections in order: **Settings**, **Connected**,
   **Account**.
2. **Settings** holds Instruments · Activities · Journal Tint · Tasks · the
   `Show…` toggles — and **no** Connected preferences in the middle any more.
3. **Connected** holds Default to Private Posts + its explanation, then Let other
   members find you + its explanation.
4. Both toggles still reflect and change their state; the discovery toggle still
   persists (turn it off, leave Profile, return — it stays off).
5. Section spacing and card composition look deliberate, not like a block was cut
   and pasted.

**B — Solo**
6. **There is NO "Connected" section and no empty header.**
7. Settings looks correct without it.
8. The Account section still offers Explore Connected, About Études and **Erase
   All Études Data** (Solo wording).

**Report anything in 1–8 you want adjusted.** Spacing changes consequential to
the regrouping are in scope; a broader Profile redesign is not.
