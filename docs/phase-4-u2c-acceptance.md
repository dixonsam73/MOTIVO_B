# P4-U2c — THE ATTACHMENT-UPLOAD PRIVACY INVARIANT. ACCEPTANCE.

**Executed 2026-09-04. Prediction committed beforehand at `b720cd3`.**

**ZERO PRODUCTION CODE CHANGED** — `git diff b720cd3 -- 'MOTIVO/*.swift'` is
empty. U2c is assertions and one behavioural case, because the architecture
already guarantees the property.

---

## 1. THE INVARIANT, AND WHY NO CODE WAS NEEDED

> No attachment-upload path is reachable for a payload whose effective
> publication state is private/unshared.

**Traced, not assumed. Every link is single-entry:**

| link | measured |
|---|---|
| `uploadStorageObject` | 1 declaration + **1 call site** |
| that call site's enclosing function | **`uploadPost`** |
| `loadIncludedAttachments` | 1 declaration + **1 call site** |
| its enclosing function | **`uploadPost`** |
| `uploadPost` invocations app-wide | **1**, in `SessionSyncQueue` |
| between the guard and that call | **`payload.op == .unshare` … `continue`** |
| upload primitives inside `unsharePost` | **0** |

**The only door into Storage for a post attachment is inside `uploadPost`;
`uploadPost` has one caller; that caller sits behind a guard-and-`continue` on
the operation.** A private payload cannot arrive.

### 1.1 THE REPRESENTABLE DIVERGENCE, AND WHERE IT IS ACTUALLY CLOSED

**The `op` boundary alone is NOT sufficient, and saying so is the point of this
unit.** It discriminates on the *operation*, not on `isPublic`. A payload with
`op: .publish` **and** `isPublic: false` is representable, would reach
`uploadPost`, and would write `is_public: false` **while uploading its
attachments** — the mirror defect, in a state no current path constructs.

**It is closed at the call sites, by identity rather than by discipline:**

| call site | payload argument | publish argument |
|---|---|---|
| `AddEditSessionView` | `isPublic: isPublic` (`:2073`) | `shouldPublish: isPublic` (`:2094`) |
| `PostRecordDetailsView` | `isPublic: visibility` (`:1830`) | `shouldPublish: visibility` (`:1840`) |

**The same identifier is passed to both parameters, so existence and visibility
cannot diverge — they are the same value.** `U2c-9` and `U2c-10` assert exactly
that.

**This is why no runtime `guard` was added.** A guard would be redundant *and
weaker*: it would silently swallow a divergence at run time, where the assertion
fails loudly the moment a future edit lets the two arguments drift.

### 1.2 THE ASSERTION IS NON-VACUOUS — PROVEN BY REVERTING U2b

`shouldPublish: isPublic` was temporarily reverted to `shouldPublish: true` in
`AddEditSessionView`:

```
divergence reintroduced :  U2c-9 FAIL  (13 passed, 1 failed)
restored               :  U2c-9 PASS  (14 passed, 0 failed)
```

`git diff` after restore is **empty** — byte-identical. **A structural assertion
that cannot fail is decoration; this one was made to fail on purpose before
being accepted.**

### 1.3 SCOPE — STATED, BECAUSE THE UNQUALIFIED CLAIM WOULD BE FALSE

Three other Storage writers exist and are **legitimately outside** this
invariant:

- **`ConnectedAttachmentSharing:215`** — attachments sent directly to named
  recipients (`connected_attachments`). Domain 3 **by design** per
  `architecture.md`; not post attachments, and they carry no `isPublic`.
- **`NetworkManager:502/558`** — avatars, i.e. the public identity row.
- **`DebugViewerView:365`** — inside **`#if DEBUG`** (opened at `:13`), as are
  both of its presentation sites (`SessionDetailView:324`, `ContentView:1702`).
  **Not compiled into Release**, the only configuration that can transact
  (`U2c-11`, `U2c-12`).

---

## 2. THE FOUR REQUIRED DISTINCTIONS

| case | expected | evidence |
|---|---|---|
| new **private / Share-OFF** session — never enters `.publish`, never reaches `uploadPost` or attachment upload | no row, no object, **no `.publish` item** | `testIncludedAttachmentShareOffReachesNoUploadPath` **PASS** |
| **Thought** — same property | no row | `testConnectedThoughtCreatesNoPostRow` **PASS** |
| **existing shared → unshared** — enters `.unshare`, may demote/delete, **must never invoke the upload path** | objects and row removed, nothing uploaded | **NEW:** `testUnshareRemovesAttachmentsAndUploadsNothing` **PASS**, plus structural `U2c-8` |
| **Share ON** — continues through `.publish`, retains legitimate upload capability | row created, public, dequeued | `testShareOnStillPublishes` **PASS** |

**One case was added; the other three already existed and stay green.**

---

## 3. U2b'S FAILED SYNTHETIC CONTROL — RESOLVED BY NOT REPEATING IT

U2b could not make a synthetic Core Data fixture upload an attachment, so its
Share-OFF negative would have been vacuous and was withdrawn (`u2b-acceptance`
§4.1).

**U2c does not reopen that.** §1 is a **stronger** proof than the fixture could
have given: a topological argument covers **every** payload, where a fixture
covers one. The instruction not to turn this into a Core Data investigation is
therefore satisfied on the merits, not by omission — **and the cause of that
fixture failure remains unestablished and is still not claimed to be a product
defect.**

---

## 4. ASSERTIONS — 14 / 14

`supabase/tests/p4/u2c-acceptance.sh`. Two of them had to be corrected against
measurement before they were trustworthy:

- **the comment-stripper was broken in four places.** It was written
  `re.sub(r'//.*\$', …)`, and in a raw string `\$` is a **literal dollar**, so
  `//` comments were never stripped. `U2c-9`/`U2c-10` then matched text inside
  the very comments that explain the invariant — **U5c-34's shape, in my own
  harness.**
- **`U2c-9`/`U2c-10` compared the wrong occurrence.** The first textual
  `isPublic:` in both files is the `@State` **type annotation** `isPublic: Bool`,
  not an argument. Now filtered to lowercase-initial identifiers.

**Both were caught because the assertions failed on correct code**, which is the
only reason they are now worth anything.

---

## 5. GATES

| gate | result |
|---|---|
| Debug / Release build | **BUILD SUCCEEDED**, 0 errors |
| `MOTIVOTests` | **39 of 39**, exit 0 |
| `u5/client-structural.sh` | **60 / 60** |
| `p4/u2c-acceptance.sh` | **14 / 14** |
| `p4/u2b-acceptance.sh` | **16 / 16** |
| `p4/u2a2-acceptance.sh` | **22 / 22** |
| `p4/u2a-acceptance.sh` | **16 / 16** (pinned) |
| `p4/u1-baseline.sh` | 11 pass / its **5 documented flips** |

**A counting artefact worth recording:** one full run reported **38** and the
next **39**, both exit 0. The missing line was `attestationBodyIsJwsOnly`, whose
result simply did not appear in that run's interleaved output across parallel
simulator clones. **39 is the true count** (15 pure + 8 + 11 + 5); no test was
skipped or failed. Recorded because a silently-varying test count is exactly the
kind of thing that later gets mistaken for a regression.

---

## 6. NOTHING ELSE CHANGED

- **Production untouched:** 101 / 101 / 0, 9 owners — read-only checks only.
- **No membership state, no U6b enforcement change, no Device A action.**
- **Local stack restored:** 2 posts, 5 attachment objects (the pre-existing U7f
  `.pdf` fixtures), 0 `.jpg` leftovers.
- **U2s is NOT started** — `posts_insert_owner` still has no `is_public` guard
  (`U2c-14`).
- **U2b remains device-verification-pending** — Phase 4 exit condition 8.
