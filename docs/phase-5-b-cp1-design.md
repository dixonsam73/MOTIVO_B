# ⚠️ SUPERSEDED IN PART — READ `docs/phase-5-b-cp1-design-r2.md` FIRST. 2026-09-06

**This is revision 1. Its AGE-DECLARATION MECHANISM is superseded** by
investigation of Apple's first-party **`DeclaredAgeRange`** framework (iOS 26+),
which r1 did not know about. **r1 assumed the age question had to be
product-owned and self-declared, and that assumption no longer holds.**

**SUPERSEDED HERE:** §3.1's Études-owned age question and its placement; §3.3's
retry semantics insofar as they concern asking our own question; §7 entirely
(promotion is Apple's, not ours); §2.1's provenance columns; §9's predictions.

**STILL CURRENT AND NOT RESTATED IN r2 — this is why r1 is retained:** §1's four
measured facts, **especially §1.3's three-layer `lookupEnabled: true` hazard**
and §1.4's client-writability finding; §2's four-ground rejection of
`account_directory` as the owner; §4.2's measured three Share-default windows;
§5's preference-vs-effective-visibility definition and its ordering constraint;
§6's initial-defaults separation; §8's honest correction to CP-0's stated
justification.

**Retained rather than rewritten**, per this project's standing practice that a
superseded record keeps its own dates and reasoning.

---

# P5-B / CP-1 — DESIGN. 2026-09-06

**DESIGN ONLY. NOTHING IMPLEMENTED, NOTHING DEPLOYED, NO PRODUCTION MUTATION.**
No SQL was executed against any database, local or production. Every fact below
was measured by reading committed source and the committed schema snapshot at
`5b2ebe3`.

**This document is for review before CP-0.** Its purpose is to settle creation
and persistence semantics completely enough that CP-0's justification, CP-1's
apply step and CP-3's client work are all decided *before* anything is deleted.

---

## 0. SUMMARY OF THE DESIGN

**The age band does NOT go on `account_directory`.** It goes on a new
server-authoritative table, `account_privacy`, which also owns the discovery
preference. `account_directory` keeps no privacy authority at all.

The single sentence the design turns on: **absence of an age declaration must
resolve to the protective answer everywhere, so the safe state needs no row.**

---

## 1. FOUR MEASURED FACTS THE DESIGN IS BUILT ON

**1.1 — `account_directory` is OPTIONAL and LATE.** `AuthManager:596` guards the
directory upsert on a non-empty display name and its failure branch only logs,
under `#if DEBUG`. `AppSetUpView:303` publishes only when
`canShareWithFollowers && isConnected`. **An identity can therefore exist with no
directory row — twice observed in production.**

**1.2 — `lookup_enabled` is already `NOT NULL DEFAULT false`**, and the schema
default is **never reached**, because the client always supplies the column
explicitly.

**1.3 — THE `lookupEnabled: true` HAZARD HAS THREE LAYERS, NOT ONE, AND FIXING
THE NAMED ONE WOULD CHANGE NOTHING.** The scope document names
`AuthManager:618`. Measured, the literal is applied three times over:

| # | site | what it does |
|---|---|---|
| 1 | `AuthManager:618`, `AppSetUpView:321`, `ProfileView:1392` | pass `lookupEnabled: true` |
| 2 | `AccountDirectoryService:328-329` | **discards the caller's value**: `let effectiveLookupEnabled = true` |
| 3 | `AccountDirectoryService:433-434` | **hard-codes `"lookup_enabled": true` in the payload**, never referencing the parameter |

**The `lookupEnabled` and `followRequestsEnabled` parameters of
`upsertSelfRowOnce` appear ONLY in its signature and nowhere in its body.** They
are dead parameters that read as controls. The write is a PostgREST upsert with
`Prefer: resolution=merge-duplicates`, so the literal is rewritten on **every
profile publish**, INSERT or UPDATE alike.

**This is the same shape as C-14 one unit earlier: the location named in the
durable record was not the operative one.** A CP-3 that edited `AuthManager:618`
and stopped would have shipped believing the hazard was closed.

**1.4 — `account_directory` is DIRECTLY CLIENT-WRITABLE.** Owner RLS policies
exist for INSERT/UPDATE/SELECT and `authenticated` holds INSERT+UPDATE column
grants on **every column**, including `entitled_until`. Nothing on that table is
protected by being behind an RPC.

**The established local precedent for defending such a column is
`tg_set_entitled_until`** — a `BEFORE INSERT OR UPDATE` trigger that **overwrites
whatever the client sent** with a server-derived value. The column stays
grantable and the client's input is simply irrelevant. That pattern is the model
for this design, and its limitation is equally instructive: it works because
`entitled_until` is *derivable server-side*. **An age band is not derivable from
anything.** It can only be declared, so it needs a different mechanism.

---

## 2. THE AUTHORITATIVE OWNER — A NEW TABLE, NOT `account_directory`

**`account_directory` is rejected as the owner on four independent grounds:**

1. **It is optional (1.1).** `age_band NOT NULL` there constrains only identities
   that happen to have a row, which is precisely the unresolved-age population
   the constraint exists to eliminate. The constraint would look total and be
   partial.
2. **Its semantics are "what others may see of me".** An age band must **never**
   be returned by either directory RPC. Putting it there invites exactly that,
   and both RPCs already return `select *`-shaped explicit column lists that a
   future edit could widen.
3. **It is fully client-writable (1.4).** A privacy-critical declaration must not
   sit on a table any client can PATCH.
4. **Its lifecycle is wrong.** The directory row is created, edited and (on
   ordinary expiry) *retained but undiscoverable*. The band's lifecycle is
   "declared once at join, promoted at most once, deleted with the account".

### 2.1 The proposed table

```sql
create table public.account_privacy (
  user_id            uuid primary key
                       references auth.users(id) on delete cascade,
  age_band           text        not null,
  lookup_enabled     boolean     not null,
  band_declared_at   timestamptz not null default now(),
  band_promoted_at   timestamptz,
  lookup_changed_at  timestamptz,
  constraint age_band_values
    check (age_band in ('band_13_17', 'band_18_plus'))
);
```

**Allowed values are exactly two, and they are opaque labels, not ages.**
`'band_13_17'` and `'band_18_plus'`. No DOB, no birth year, no age integer, no
"unknown" value.

**There is deliberately NO `'unknown'` band.** An explicit unknown would be a
value that must then be handled correctly at every read site, and one missed site
would grant adult treatment. **Absence of a row is the unknown state**, and
absence is handled by the *shape* of every predicate below rather than by a
branch anyone can forget. This is the D4 lesson applied: the row set that decides
existence must never fall through to the permissive answer.

**`NOT NULL` is trivially satisfiable here and needs no backfill, because the
table starts EMPTY.** See §8 — this materially changes CP-0's justification.

### 2.2 Writer authority — zero client DML

**`account_privacy` grants NOTHING to `anon`, `authenticated`, `service_role` or
`PUBLIC`**, on the table or any column, following U3's membership-table
precedent exactly. RLS is enabled with **zero policies**. Every write goes
through a `SECURITY DEFINER` function owned by the table owner:

| function | grant | semantics |
|---|---|---|
| `account_privacy_create_v1(band text)` | `authenticated` | **INSERT-IF-ABSENT, never overwrite.** Returns the surviving row's state. Idempotent under retry and concurrency |
| `account_privacy_promote_band_v1()` | `authenticated` | `band_13_17` → `band_18_plus` **only**. Refuses the reverse. **Does not touch `lookup_enabled`** |
| `account_privacy_set_lookup_v1(enabled boolean)` | `authenticated` | the **only** writer of the discovery preference |
| `account_privacy_self_v1()` | `authenticated` | reads the caller's own row; returns no row when absent |

All four take the identity from `auth.uid()` and **never from an argument**, so
no client parameter can name another user — the `ensure_membership_binding()`
rule, which is the narrowest client-reachable shape this project admits.

`account_privacy_create_v1` uses the **`insert … on conflict do update set
user_id = excluded.user_id returning`** idiom, copied deliberately from
`ensure_membership_binding`, whose own comment explains why `do nothing` is
wrong: under concurrency the loser skips without taking a lock and a following
`SELECT` can miss the winner's uncommitted row. **A band must never be
creatable twice, and a retry after an ambiguous network failure must return the
band that already exists rather than writing a second one.**

---

## 3. CREATION ORDER — EXACTLY WHERE THE QUESTION SITS

### 3.1 The sequence

```
Solo                       no account, NO age question at all
                           (Solo is a local journal; it is unrestricted)

Explore Connected
  ├─ AGE BAND QUESTION     asked BEFORE SIWA, answer held IN MEMORY ONLY
  │    └─ under 13 ────────► refuse Connected. NO SIWA. NO account minted.
  ├─ SIWA                  auth.users row now exists
  ├─ account_privacy_create_v1(band)   ◄── THE FIRST AUTHENTICATED CALL
  ├─ ensure_membership_binding()
  ├─ purchase(appAccountToken:)
  ├─ attestation
  └─ AppSetUpView          name + instrument → FIRST account_directory row
```

**Why the question is asked before SIWA:** so an under-13 is turned away
**without an identity being created at all**. Asking after SIWA would mint an
`auth.users` row for a child who cannot use Connected, which is a worse outcome
than a slightly earlier question — and deleting it afterwards would be a
destructive path running on a child's account.

**Why the answer is written after SIWA:** there is no authenticated identity to
attach it to before that. The answer is held in memory and written as the
**first authenticated call**, before binding, before purchase, and long before
any directory row.

**The measured no-display-name path (1.1) is handled, and NOT by making the
directory row mandatory.** Under this design that path is safe on its own terms:
the identity has an `account_privacy` row (written at step 3) and no
`account_directory` row, so it is undiscoverable because it has nothing to
discover, and its Share default is the protective one because the band drives it
(§4.2). **The hazard was never that the directory row is late; it was that
authority was proposed to live on it.** Moving the authority removes the hazard
instead of fighting it.

### 3.2 The database invariant that makes the ordering structural

A `BEFORE INSERT` trigger on `account_directory`:

```sql
if not exists (select 1 from public.account_privacy p
               where p.user_id = new.user_id) then
  raise exception 'age band must be declared before a directory row exists'
    using errcode = '23514';
end if;
```

**This is belt-and-braces on top of §5's discovery predicate, and it is worth
having.** The predicate protects the *current* read path; the trigger protects
every future one. Without it, "no directory row before a band" is a rule someone
must remember; with it, it is a rule the database enforces.

**It has a declared consequence for legacy rows** — see §8.3.

### 3.3 Partial, abandoned and retried onboarding

**Every interruption point resolves to a safe state, and none leaves state that
must be cleaned up.** Enumerated against the sequence in 3.1:

| interrupted at | server state | discoverable? | Share default | recovery |
|---|---|---|---|---|
| band answered, SIWA cancelled | **nothing** — the answer was only in memory | n/a, no identity | n/a | asked again next time; no orphan |
| under-13 answered | **nothing**, and no SIWA was attempted | n/a | n/a | refusal is terminal for Connected; Solo unaffected |
| SIWA succeeded, `create_v1` failed | `auth.users` row, **no `account_privacy` row** | **no** — §4.1 `EXISTS` is false, and §3.2's trigger refuses a directory row | **OFF** — no confirmed band | re-asked on next launch/foreground |
| band written, binding failed | band row | no directory row yet | OFF until band is read back | ordinary U5f retry; band is reused, **not re-asked** |
| band written, purchase abandoned | band row, no membership | no | per band | Connected simply inactive; band persists for a later join |
| band written, `AppSetUpView` abandoned | band row, **no directory row** | no | per band | the measured no-display-name path (1.1), already safe |

**The row that matters is the third**, because it is the only one that leaves an
authenticated identity in an unresolved-age state. It is safe on both axes
simultaneously and by two independent mechanisms — the `EXISTS` clause and the
`BEFORE INSERT` trigger — so it needs no compensating cleanup and no timeout.

**Recovery is a self-healing check, not a repair.** The client, on finding an
authenticated Connected identity whose `account_privacy_self_v1()` returns no
row, re-asks the band before permitting any Connected surface. This deliberately
copies **U5f's attestation invariant**: it runs at launch and on foreground, it
is **never gated on Connected mode already being active**, and a previous
success is not permanent authority. The reasoning is identical — the member the
mechanism exists to rescue is precisely the one whose Connected state is
incomplete, so gating the rescue on completeness would make it unreachable.

**Retry is safe by construction, not by the client being careful.**
`account_privacy_create_v1` is insert-if-absent and returns the surviving row
(§2.2), so a retry after an ambiguous network failure — the case where the write
landed but the response was lost — **returns the existing band rather than
writing a second one or overwriting the first**. The client therefore never has
to decide whether its previous attempt succeeded, which is the decision it is
least equipped to make.

**One consequence to accept knowingly:** a member who declares a band and
abandons before purchasing has a durable declaration and no membership. **That
row is not garbage-collected**, deliberately — deleting it would mean re-asking a
returning member their age, and a band is exactly the kind of state the expiry
matrix already says to retain, for the same reason `membership_binding` is
retained: destroying it makes the returning member's path worse, never safer.

---

---

## 4. NO INTERVAL OF ADULT DEFAULTS — THE PROOF, IN TWO HALVES

### 4.1 Discovery

CP-2's clause on `search_account_directory`:

```sql
and exists (
      select 1 from public.account_privacy p
       where p.user_id = ad.user_id
         and p.lookup_enabled
    )
```

**It is an `EXISTS`, not a `coalesce(..., true)` and not a `LEFT JOIN` with a
null-tolerant test.** Therefore:

| state | result |
|---|---|
| no `account_privacy` row (unresolved age) | `exists` false → **not discoverable** |
| `band_13_17`, preference untouched | `lookup_enabled` false → **not discoverable** |
| `band_13_17`, member opted in | discoverable |
| `band_18_plus`, initial default | discoverable — adult behaviour preserved |

**The unresolved-age case and the opted-out case produce the same answer by the
same mechanism**, so there is no branch that can be got wrong for one and not
the other. **This is D4's reasoning reused:** there, adding a filter to `WHERE`
emptied the row set and `bool_or` over an empty set returned NULL, which fell
through to a *permissive* clause. Here the empty set returns **false**, and
false is the protective answer.

`get_account_directory_by_user_ids` is **unchanged**. Attribution stays
independent of discoverability — that separation is already established (G10,
P4-U7) and the children's work must not collapse it: a 13–17 member who is
undiscoverable must still have their name render on a comment.

### 4.2 Share

Share default is **client-side** and is measured to have **three** windows, not
one:

| # | site | current |
|---|---|---|
| 1 | `AddEditSessionView:222`, `PostRecordDetailsView:235` | `@State private var isPublic: Bool = true` — **ON before any derivation runs** |
| 2 | `AddEditSessionView:1829` | `isPublic = isThoughtMode ? false : !fetchDefaultPostingIsPrivate()` |
| 3 | `PostRecordDetailsView:309` | `isPublic = !fetchDefaultPostingIsPrivate()` |

`fetchDefaultPostingIsPrivate()` reads Core Data `Profile.defaultPrivacy` and
**returns `false` on a missing profile and on a fetch error**, so today every
unknown resolves to Share **ON**.

**The rule CP-3 must implement:**

> **Share defaults ON only when the client holds a server-confirmed
> `band_18_plus`. Every other state — no band fetched, fetch failed, band
> `band_13_17` — defaults OFF.**

Expressed as a single derivation used by all three windows, with the `@State`
declarations initialised to `false` so that **the pre-derivation window is
protective rather than permissive**. A network failure yields the protective
answer, which is the correct failure direction and the inverse of today's.

**This governs the DEFAULT only.** A 13–17 member may still deliberately turn
Share on for an individual session — the settled decision that Thoughts are
default-private and user-shareable applies unchanged, and the Share toggle is
still offered (`AddEditSessionView:1123` is guarded by `canShareWithFollowers`,
not by band). **CP is not a capability restriction; it is a defaults change.**

---

## 5. `lookup_enabled` — STORED PREFERENCE, NOT EFFECTIVE VISIBILITY

**Definition, stated so it cannot drift:**

> **`account_privacy.lookup_enabled` is the member's STORED PREFERENCE: "may
> people who do not already follow me find me by searching?" It is NOT effective
> visibility, and nothing in the entitlement or enforcement lifecycle may ever
> write it.**

**Effective discoverability is COMPUTED at read time and never stored:**

```
discoverable(m) =  account_privacy.lookup_enabled          -- the preference
               AND (enforcement inactive OR entitled)      -- D-U6-1, unchanged
               AND m has an account_directory row
```

**Why the separation is load-bearing.** If `lookup_enabled` meant effective
visibility, then a lapse would have to write `false` and a resubscribe would have
to write `true` — and the resubscribe could not know whether the member had
*chosen* to be undiscoverable before lapsing. **The lifecycle would silently
overwrite a privacy preference, which is the exact hazard CP-3 exists to remove,
reintroduced from the other end.** It is also the retention lesson from the
expiry matrix, where `membership_binding` is retained precisely so a returning
member is not mis-served by state that was destroyed.

**Interaction with entitlement and enforcement, stated explicitly:** the existing
`entitled_until > now()` subject-side filter is **kept exactly as it is**,
including its `enforcement_active()` guard. The new clause is an **additional
conjunct** and, like D-U6-1, it must respect a kill switch — otherwise a rollback
of CP-2 would only half-roll-back, which is the mistake the U7 record already
names. **A lapsed 13–17 member is undiscoverable for two independent reasons,
and each is separately switchable.**

### 5.1 Removing the three-layer hazard

**Preference: profile publication must not mutate discovery preference at all**
— and under this design it *structurally cannot*, because the preference no
longer lives on the table profile publication writes.

`account_directory.lookup_enabled` becomes **dead**: nothing reads it. The three
client literals write to a column with no reader, which is inert but misleading,
so CP-3 also:

- deletes `lookup_enabled` and `follow_requests_enabled` from the
  `upsertSelfRowOnce` payload;
- deletes the two **dead parameters** from both function signatures, so no future
  caller believes it is passing a control;
- removes the `lookupEnabled:`/`followRequestsEnabled:` arguments at all three
  call sites.

**`follow_requests_enabled` is included deliberately.** It is the same defect —
hard-coded `true`, dead parameter — and leaving one of a matched pair fixed is
how the next reader concludes the other was intentional. It is **not** given new
semantics by CP; it is only stopped from being rewritten on every publish.

**ORDERING CONSTRAINT, and it is a real one.** `account_directory.lookup_enabled`
must **not** be dropped, and its column privileges must **not** be revoked, until
the client has stopped sending it. PostgREST would answer `400` on an unknown
column and `permission denied` on a revoked one, and either would break **every
profile publish**. So: server units add the new table and the read clause; CP-3
stops sending the column; only a later, separate step may drop it. **The design
does not require the drop at all** — it is tidying, and it is safest last.

---

## 6. INITIAL DEFAULTS ARE NOT PREFERENCES

**`lookup_enabled`'s initial value is DERIVED from the band, once, at row
creation, inside `account_privacy_create_v1`:**

```
band_18_plus  → lookup_enabled := true    -- adult behaviour preserved
band_13_17    → lookup_enabled := false   -- Standard 7: visible to others
                                          --   only if the child changes it
```

**After creation the band never touches the preference again.** This is made
structural rather than remembered:

- `account_privacy_promote_band_v1()` writes `age_band` and `band_promoted_at`
  and **nothing else**. A 13–17 member who chose to be discoverable and later
  turns 18 does not get re-defaulted; a 13–17 member who stayed private does not
  silently become discoverable on their promotion.
- `account_privacy_set_lookup_v1()` writes `lookup_enabled` and
  `lookup_changed_at` and **never** `age_band`.

**Two functions, two columns, no overlap** — so "the default was applied once"
and "the member has since chosen" cannot be conflated by any call sequence.

---

## 7. BECOMING 18 WITH NO DOB STORED

**The server can never compute this transition, and the design must not pretend
otherwise.** No DOB, no birth year, no age integer is stored, so there is nothing
to compare a clock to.

- **There is NO automatic promotion, and none may be added.** The tempting
  construction — `band_declared_at + 5 years` — would be an **invented
  provenance**: it assumes the member was 13 on declaration, which is true of at
  most one cohort in five. It is the same defect as U4's rejected
  `binding_method` inference, where a value derived from what had not shipped was
  provenance invented rather than established.
- **Promotion is a deliberate, member-initiated act** in settings, calling
  `account_privacy_promote_band_v1()`, and is presented neutrally with no
  nudging.
- **Only `band_13_17` → `band_18_plus` is permitted. The reverse is refused.**
  The server can verify neither direction; permitting a downgrade would make the
  band a self-serve toggle between two treatments. A genuine mis-declaration is a
  support matter, not a control in the app.
- **A member who turns 18 and never promotes keeps the child protections
  indefinitely.** That is the fail-safe direction and is accepted.

**FLAGGED FOR THE DPIA (P5-G), NOT SETTLED HERE.** Self-declaration with a
one-way self-serve promotion is an **age-assurance proportionality question**,
and the ICO's Children's Code treats proportionality as depending on the assessed
risk of the processing. The engineering design supports this shape; **whether it
is sufficient is a P5-G determination**, and P5-G may require a different
promotion story. **The design must not be read as having decided that.**

---

## 8. WHY CP-0 — AND AN HONEST CORRECTION TO ITS STATED JUSTIFICATION

### 8.1 The stated justification does not survive this design

`docs/phase-5-scope.md` records the ordering rationale as: *"the design comes
first because it is what establishes that a clean population makes
`age_band NOT NULL` achievable without backfill."*

**Under this design, CP-0 is NOT what makes `NOT NULL` achievable.** The band
lives on a **new table that starts empty**, so `age_band NOT NULL` is satisfied
trivially and by construction, for any population, with **no backfill and no
`'unknown'` value**. The 17 existing identities simply have no row, and §4 proves
that absence is the protective state at every read site.

**This is recorded rather than quietly absorbed**, because the scope document's
rationale would otherwise be carried forward as though it still held, and a later
reader would believe CP-0 was a technical precondition when it is not.

### 8.2 What CP-0 is still for

Two real reasons, neither of which is `NOT NULL`:

1. **Data minimisation.** Retaining 15 dormant pre-release beta identities and
   their personal data has no purpose, and a children's-privacy workstream that
   opens by *keeping* unnecessary personal data is arguing against itself. This
   is a P5-G/DPIA-facing reason, and it is the strong one.
2. **Legacy-row reduction** — see 8.3.

### 8.3 The legacy-row question, which CP-0 genuinely does shrink

§3.2's trigger blocks *new* directory rows without a band. It says nothing about
the **17 rows that already exist**, each with no band and a `lookup_enabled`
value that was never a preference (measured 9 true / 8 false — artefacts of the
three-layer literal, not choices).

Under §4.1's `EXISTS` clause **all 17 become undiscoverable the moment CP-2
ships**, which is safe but is a behaviour change for the retained pair. CP-0
reduces this population from **17 to 2**, at which point it is small enough to
disposition explicitly rather than by rule.

### 8.4 What data population P5-D expects

**P5-D expects `account_privacy` to be EMPTY at apply time, and to remain empty
until an identity declares a band through the real flow.** The apply is
therefore pure DDL plus functions; it writes no rows.

**The retained pair needs an explicit decision, and this design does not take
it.** Two options, with a recommendation:

- **(a) RECOMMENDED — they declare through the real CP-3 flow.** This exercises
  the path that matters and creates no operator-authored declarations. It
  requires CP-3 to have shipped, so the pair is simply undiscoverable between
  CP-2 and CP-3, which is acceptable for a two-identity pre-release fixture.
- **(b) An explicit operator INSERT by id**, recorded as an *operator
  declaration* with its own timestamp and note. Defensible only because the
  account holder knows both identities, and it must never be described as
  derived. **If (b) is chosen it must be recorded as spent authority**, in the
  way U3's single permitted repair was.

**RETAINED-PAIR GUARD INTERACTION, flagged not resolved.** Writing an
`account_privacy` row for `1fbf664a` or `64ffb132` is not a CP-0 deletion, but it
*is* a change to their state, and they are held as the only fixture that can
exercise Phase 4's conditions 2 and 8 and C-34's avatar test. **CP-2 shipping
will also make them undiscoverable.** Whether that disturbs the outstanding
Phase 4 verification is a question for whoever dispositions that guard, and it
should be answered **before** CP-2, not after.

---

## 9. PREDICTIONS

**These are design-time predictions to be re-derived and committed immediately
before P5-D executes. They are not authority for an apply.**

### 9.1 Schema delta (B-23 surfaces)

| surface | predicted |
|---|---|
| `columns` | **+6** (`account_privacy`) |
| `constraints` | **+3** — pkey, FK to `auth.users`, `age_band_values` check |
| `rls_enabled` | **+1** — RLS on, **zero policies** (U3 pattern) |
| `policies` | **0** — no client role reaches the table at all |
| `functions` | **+4 new**, **1 MODIFIED** (`search_account_directory`) |
| `function_grants` | **+4**, all to `authenticated` only |
| `triggers` | **+1** on `account_directory` |
| `table_grants` / `column_grants` | **ZERO** — every privilege revoked from `public`, `anon`, `authenticated`, `service_role`, per U3 |
| `storage_buckets` | identical |

**Like U4/U5b and unlike U3, this MODIFIES a deployed object**
(`search_account_directory`), so the rollback cannot be "drop what was added".

### 9.2 Client delta (CP-3, predicted — not this unit)

- `AccountDirectoryService`: remove 2 payload keys; remove 2 dead parameters from
  2 signatures; update 3 call sites.
- Share default: one shared derivation replacing 2 `@State` initialisers
  (`= true` → `= false`) and 2 derivation sites.
- New: band question in the Explore Connected flow; a discoverability control in
  settings; a promotion control; a coordinator that re-asks the band when an
  authenticated identity has no `account_privacy` row.

### 9.3 Rollback shape

- **Additive objects** — drop `account_privacy`, its 4 functions and the trigger.
- **The one modified object** — restore `search_account_directory` from its
  committed definition, byte-compared, as U6a's rollback was.
- **Kill switch first.** The CP-2 clause must be switchable without a migration,
  so discovery can be restored while the table stays in place. **Rolling back by
  dropping the table would strand the clause referencing a missing relation**,
  so the switch must be the first thing rehearsed and the drop the last.
- **No data loss on rollback at P5-D**, because the table is empty. **That stops
  being true the moment the first band is declared** — after which a drop
  destroys declarations that only the member can supply again.

---

## 10. WHAT THIS DESIGN DOES NOT SETTLE

- **Age-assurance sufficiency** — P5-G/DPIA. §7.
- **The retained-pair disposition** — §8.4, owned by whoever dispositions the
  Phase 4 guard.
- **The exact question wording** and the neutral just-in-time explanation. CP-3,
  and it is a copy/legal matter as much as a design one.
- **Whether `account_directory.lookup_enabled` is ultimately dropped** — §5.1
  says it must not be, until after CP-3, and that it is optional even then.
- **C-62 is untouched** and is not widened by this unit.
