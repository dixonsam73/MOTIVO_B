# U7e / U7 / PHASE 3 — CLOSED. 2026-09-03

**The scheduler is armed. `CLEANUP_MODE = execute` is set as a repository
variable and stays set: unattended expiry cleanup is live.**

---

## 1. FINAL VERIFICATION — FOUR POINTS, ALL CLEAN

### 1. The variable is armed
`CLEANUP_MODE = execute`, confirmed by the account holder. I hold no GitHub read
access and record it on their statement — **stated as attestation, not as
something I measured.**

### 2. Production at rest

| | |
|---|---|
| `auth.users` / posts / comments / follows | **17 / 101 / 5 / 9** |
| storage: attachments / avatars | **15 / 3** |
| `connected_attachments` / directory | **31 / 17** |
| `pending_cleanup_at` | **`2026-11-01 15:16:44+00`** |
| `cleanup_completed_at` | **NULL** |
| `cleanup_claimed_at` | `2026-09-03 08:14:36` — the expired lease from the P5 refusal |
| `renewal_info_signed_date` | `2026-09-03 08:14:36.792` — **unmoved: no scheduled run has ever reached Apple** |
| conflicts | **0** |
| `enforcement_enabled` / `enforcement_active()` / `u6b_bound_at` | **true / true / 2026-09-01 16:52:52** |
| `pg_cron` | **0** |
| **`due_now`** | **0** |

### 3. The worker

`membership_cleanup_v1` **v6, `afcf87a368d495ec`, ACTIVE, `verify_jwt=false`** —
the diagnostic-free build. The other five functions are untouched at their
original versions and SHAs.

**Auth boundary:** no header **401** · wrong credential **401** ·
**service-role key 401** · correct invocation key **200**.

**Response surface:** `['claimed','deleted','identities','mode','note','ok','results']`
— **`diag` absent.** The temporary diagnostic is gone from production.

### 4. The scheduler

`origin/main` at **`3454f61`**. The workflow is present, the caller is
**python3/urllib** (3 references), **zero `curl`** remaining, schedule
`17 3 * * *`, **zero `inputs.` references** so `CLEANUP_MODE` is the sole
control, unset still resolves to `dry_run`, UUID redaction present, non-200 fails
the run. **`pg_cron` remains 0** — the scheduler is outside the database, so U4's
`A57f` is unaffected and the ratified credential constraint holds.

---

## 2. WHAT IS NOW LIVE, AND WHAT STILL GATES IT

**Armed:** a daily 03:17 UTC job invokes the worker with `mode: execute`.

**Two gates survive arming, and neither is weakened by it:**

1. **Candidate selection.** Only identities with `pending_cleanup_at <= now()`
   and a free lease are selected. **That set is empty until 2026-11-01.**
2. **Fresh Apple authority.** Even a selected candidate must yield a successful
   live Apple read for **every** row of that identity, applied through the
   canonical writer, before `membership_cleanup_authorised_v1` will authorise.
   **This is measured, not asserted: on 2026-09-03 a manual `execute` against a
   deliberately-advanced schedule REFUSED**, and the reconciliation overwrote the
   artificial value with Apple's own derived date.

**Arming enables a capability; it does not schedule a deletion.**

---

## 3. A3 — PASSED

The execute-mode GitHub path is demonstrated correct end to end: caller logged
29 bytes / `1c1d0b8d…`, the handler reported the **same** SHA, `mode:"execute"`,
`identities:0`, and production was byte-identical afterwards. Step 4 then
repeated the dry-run path against the **diagnostic-free** worker with no `diag`
fields and production again unchanged.

**The defect A3 uncovered was a configuration one, not a design one:** a trailing
newline in the GitHub-held `CLEANUP_INVOKE_KEY`, which makes an `Authorization`
header value invalid. `curl` accepted it and something downstream reframed the
request into an 83-byte unparseable body; Python refused it before sending
anything. **The replacement caller did not merely avoid the ambiguity — it
diagnosed it**, and it now fingerprints every payload so caller and handler
agreement is provable at both ends rather than inferred.

**The exact reframing mechanism was never identified and is deliberately left
unexplained.** It is closed on the agreed condition — the Python caller does not
reproduce it. Two things make that residue tolerable: **`dry_run` is the
fail-safe default**, so a mangled body can only ever under-act; and the authority
path independently refuses anything Apple does not currently authorise. **The
unexplained behaviour never had a route to destroying data.**

---

## 4. U7 — CLOSED

| | |
|---|---|
| Cleanup primitive and born-lapsed floor deployed | **B-23 GATE MET** |
| Worker deployed, authorisation boundary measured in production | ✅ |
| Destructive behaviour verified locally against the full retention matrix | **75/75** |
| **Authority path verified in production against genuine Apple**, including a correct refusal | ✅ |
| **Unattended scheduler running and verified** | ✅ |

---

## 5. PHASE 3 — CLOSED

U3, U4, U5, U6 and U7 are complete and in production. Membership is
**established** authoritatively, **enforced** durably, and now **collected**
unattended under a live Apple authority check.

**Four obligations are carried, none ownerless:**

| | |
|---|---|
| **G7** | First naturally matured production cleanup. Owner U7; earliest `2026-11-01 15:16:44+00`. Its only remaining precondition is elapsed time |
| **C-31** | Production Billing Grace promotion in App Store Connect |
| **B-34** | Shadow telemetry blind to denied writes — an observability limitation, never a correctness defect |
| **Gate 6 part 3** | Production GRANT at the first real subscription — a post-public-release gate, on B-11 |

**Phase 3 closes carrying these deliberately.** The discipline that permits it is
the project's own: *forcing an obligation to fit a phase boundary would be the
opposite of the rule that says no obligation may be ownerless.*

---

## 6. WHAT REMAINS TRUE AND MUST NOT BE FORGOTTEN

- **Leaving Connected is not leaving Études.** No subscription lifecycle event
  deletes or resets local data. Invariant 1, untouched by anything in U7.
- **`pending_cleanup_at` SELECTS; it never AUTHORISES.** Demonstrated in
  production when a hand-advanced schedule was overwritten by Apple's own dates
  and cleanup refused.
- **The 60-day quarantine is never retroactively spent** — U7b's born-lapsed
  floor.
- **Kill switches, none of which touch membership state:** unset `CLEANUP_MODE`
  (back to `dry_run`), disable the workflow, delete the GitHub secret, or delete
  the Supabase secret (the worker then refuses every caller, fail-closed).
- **None of them undoes a completed deletion.** There is no backup of Domain 3
  content, and this record does not pretend otherwise.
