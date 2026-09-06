# P5-C / CP-0 — EXECUTABLE TRANSACTION AND COMPLETE PREDICTED SURFACE. 2026-09-06

**NOT EXECUTED. NO MUTATION HAS BEEN PERFORMED. `SELECT` ONLY.**
For review. Companion to `docs/phase-5-c-cp0-prediction.md` (the census).

**Delete set held at 15. Samuel (`1fbf664a`) and Steve (`64ffb132`) untouched.**

---

## 1. RETENTION STATUS, AS CLARIFIED

| identity | status |
|---|---|
| **`1fbf664a`** — Samuel / Études Dev / Device B | **standing preservation requirement.** The only beta identity with one |
| **`64ffb132`** — Steve | **retained TEMPORARILY and CONDITIONALLY**, solely because Phase 4's outstanding device verification needs the two-identity approved-follow fixture. **Not a standing requirement.** Once conditions 2 and 8 and C-34 are dispositioned, Steve carries no retention claim and may be deleted by a later unit |
| the other 15 | deletable as required for the clean pre-launch architecture |

**This is recorded because the two keepers are kept for DIFFERENT reasons with
different lifetimes**, and a later reader who treats them as equivalent would
either delete Samuel or preserve Steve forever.

---

## 2. TWO STATE DISCOVERIES THAT CHANGE THE SURFACE

### 2.1 `membership_cutover` DOES NOT EXIST, AND THE GRANDFATHER CLAUSE IS GONE

**Measured three independent ways in production:**

- `to_regclass('public.membership_cutover')` → **null**; `public` holds 14 base
  tables and none is a cutover table;
- `membership_control` has **zero** columns matching `grandfather%`;
- the deployed `connected_member(uuid)` contains **no** `membership_cutover`
  reference and **no** grandfather arm — its middle `coalesce` argument is gone
  and it falls straight to `false`.

**B-36's grandfather retirement has already been applied to production.**
CLAUDE.md's U3 table — `grandfather_enabled: true`, a 16-row
`membership_cutover` — is **historical and no longer describes production**.

**Consequence for CP-0: there is no cutover table to clean, and no snapshot rows
to strand.** Had this not been measured, CP-0 would have carried a statement
against a table that does not exist, and the transaction would have failed at
execution — or worse, a reviewer would have believed 15 stale snapshot rows were
left behind.

### 2.2 `auth.audit_log_entries` is empty and has no FK

0 rows, and no foreign key to `auth.users`. **Nothing to retain or delete**, and
no audit trail of the deletion will exist there. Stated so its absence afterwards
is not read as a defect.

---

## 3. THE COMPLETE PREDICTED SURFACE — EVERY TABLE, CLASSIFIED

**All 45 base tables in `public`, `auth` and `storage` were enumerated from
production.** Every one is classified below; **none is omitted.**

### 3.1 EXPLICIT SQL DELETION — no FK reaches these

| table | column | before | **after** | deleted |
|---|---|---|---|---|
| `public.post_comment_views` | `viewer_user_id` | 9 | **3** | **6** |
| `public.posts` | `owner_user_id` | 101 | **7** | **94** |
| `auth.users` | `id` | 17 | **2** | **15** |

**`post_comment_views` has NO foreign key at all** — not to `auth.users` and not
to `posts` — so it orphans in both directions and must be deleted first.

### 3.2 MEASURED FK CASCADE

| table | cascades from | before | **after** | deleted |
|---|---|---|---|---|
| `public.post_comments` | `posts.id` | 5 | **5** | **0** — measured 0 on deleted posts |
| `public.post_shares` | `posts.id` | 0 | **0** | 0 — none exist |
| `public.account_directory` | `auth.users.id` | 17 | **2** | **15** |
| `public.follows` | `auth.users.id` ×2 | 9 | **2** | **7** |
| `public.membership` | `auth.users.id` | 1 | **1** | 0 |
| `public.membership_binding` | `auth.users.id` | 1 | **1** | 0 |
| `public.membership_binding_conflict` | `auth.users.id` | 0 | **0** | 0 |
| `public.shadow_enforcement_stat` | `auth.users.id` | 79 | **75** | **4** |
| `auth.identities` | `auth.users.id` | 17 | **2** | **15** |
| `auth.sessions` | `auth.users.id` | 44 | **23** | **21** |
| `auth.refresh_tokens` | `auth.sessions.id` **(transitive)** | 769 | **382** | **387** |
| `auth.mfa_amr_claims` | `auth.sessions.id` **(transitive)** | 44 | **23** | **21** — *derived from the 1:1 with sessions, to be scored* |
| `auth.mfa_factors` | `auth.users.id` | 0 | **0** | 0 |
| `auth.oauth_authorizations` | `auth.users.id` | — | — | 0 |
| `auth.oauth_consents` | `auth.users.id` | 0 | **0** | 0 |
| `auth.one_time_tokens` | `auth.users.id` | 0 | **0** | 0 |
| `auth.webauthn_challenges` | `auth.users.id` | — | — | 0 |
| `auth.webauthn_credentials` | `auth.users.id` | 0 | **0** | 0 |

### 3.3 INTENTIONALLY RETAINED — untouched, and guarded

| table | before/after | why |
|---|---|---|
| `public.connected_attachments` | **25 → 25** | **Measured: ZERO rows reference any delete-set identity** (sender 0, recipient 0). All 25 are pre-existing residue from already-deleted parties, all soft-deleted (`ca_live` 0). **Not CP-0's to sweep** |
| `public.membership_notification` | **74 → 74** | not keyed on a user |
| `public.membership_notification_reject_stat` | unchanged | aggregate, no user column |
| `public.membership_control` | unchanged | singleton control row; `enforcement_enabled` stays **true** |
| `auth.audit_log_entries` | 0 → 0 | empty, no FK (§2.2) |
| `auth.flow_state` | 0 → 0 | empty |
| `auth.instances`, `auth.schema_migrations`, `auth.sso_*`, `auth.saml_*`, `auth.oauth_client*`, `auth.custom_oauth_providers`, `auth.mfa_challenges` | unchanged | no user reference, or empty |
| `storage.buckets`, `storage.buckets_analytics`, `storage.buckets_vectors`, `storage.migrations`, `storage.vector_indexes`, `storage.s3_multipart_uploads*` | unchanged | no per-user rows |
| **The 8 surviving attachment objects** | retained | **pre-existing B-8-shaped residue owned by the retained pair.** Needs its own decision, not this one |

### 3.4 POST-COMMIT STORAGE DELETION — 4 objects, by explicit path

| bucket | owner md5[0:8] | objects | before → after |
|---|---|---|---|
| `avatars` | `daed2252`, `c0464940` | 2 | 3 → **1** |
| `attachments` | `daed2252`, `41aacc65` | 2 | 10 → **8** |

**Deleting them strands nothing:** all 10 attachment objects are **already
unreferenced** by any `connected_attachments` row, measured
`referenced 0 / unreferenced 10`.

---

## 4. THE TRANSACTION

**Raw UUIDs and raw storage paths are staged OUTSIDE the repository**, per the
standing rule and the `phase-4-ca-residue` precedent. The repository carries only
`md5[0:8]`. The staged file substitutes the 15 literal UUIDs into the `values`
block; **everything else is exactly as below.**

**"Explicit id" is not satisfied by `not in (keep)`.** A negated predicate is
still a predicate over the whole table: an identity created between census and
execution would be swept by it, which is the precise hazard B-22's rule exists to
prevent. **The 15 ids are enumerated, and the transaction then proves the
enumeration matches the census by hash.**

```sql
begin;

-- ── 0. THE DELETE SET, BY EXPLICIT ID ONLY ────────────────────────────────
create temporary table cp0_delete (user_id uuid primary key) on commit drop;
insert into cp0_delete (user_id) values
  ('«uuid-01»'),('«uuid-02»'),('«uuid-03»'),('«uuid-04»'),('«uuid-05»'),
  ('«uuid-06»'),('«uuid-07»'),('«uuid-08»'),('«uuid-09»'),('«uuid-10»'),
  ('«uuid-11»'),('«uuid-12»'),('«uuid-13»'),('«uuid-14»'),('«uuid-15»');

-- ── 1. GUARDS. ANY FAILURE ABORTS. NOTHING IS REPAIRED FORWARD. ───────────
do $$
declare v_n int; v_keep int;
begin
  -- 1a. The enumeration is exactly 15 and matches the census by hash.
  select count(*) into v_n from cp0_delete;
  if v_n <> 15 then raise exception 'CP0 guard 1a: delete set is %, expected 15', v_n; end if;

  select count(*) into v_n from cp0_delete d
   where left(md5(d.user_id::text),8) not in (
     '965caeff','776bf498','c0464940','1778a35d','daed2252','41aacc65',
     'fb9b8413','d66695a2','a7d22d28','853397a4','9b8dde86','3d2b85bf',
     'b085b77e','fb543460','03fc4262');
  if v_n <> 0 then raise exception 'CP0 guard 1b: % id(s) not in the censused delete set', v_n; end if;

  -- 1c. SAMUEL AND STEVE ARE ABSENT FROM THE DELETE SET.
  select count(*) into v_n from cp0_delete d
   where left(md5(d.user_id::text),8) in ('1fbf664a','64ffb132');
  if v_n <> 0 then raise exception 'CP0 guard 1c: KEEPER PRESENT IN DELETE SET'; end if;

  -- 1d. Both keepers still exist.
  select count(*) into v_keep from auth.users u
   where left(md5(u.id::text),8) in ('1fbf664a','64ffb132');
  if v_keep <> 2 then raise exception 'CP0 guard 1d: keepers resolve to %, expected 2', v_keep; end if;

  -- 1e. THE MUTUAL APPROVED FOLLOW EXISTS, BOTH DIRECTIONS.
  select count(*) into v_n from public.follows f
   where f.status = 'approved'
     and left(md5(f.follower_user_id::text),8) in ('1fbf664a','64ffb132')
     and left(md5(f.followed_user_id::text),8) in ('1fbf664a','64ffb132')
     and f.follower_user_id <> f.followed_user_id;
  if v_n <> 2 then raise exception 'CP0 guard 1e: mutual approved follow is % rows, expected 2', v_n; end if;

  -- 1f. EVERY PRE-DELETE COUNT MATCHES THE CENSUS. ANY DRIFT ABORTS.
  if (select count(*) from auth.users)                    <> 17  then raise exception 'CP0 drift: auth.users'; end if;
  if (select count(*) from public.account_directory)      <> 17  then raise exception 'CP0 drift: account_directory'; end if;
  if (select count(*) from public.posts)                  <> 101 then raise exception 'CP0 drift: posts'; end if;
  if (select count(*) from public.post_comments)          <> 5   then raise exception 'CP0 drift: post_comments'; end if;
  if (select count(*) from public.post_shares)            <> 0   then raise exception 'CP0 drift: post_shares'; end if;
  if (select count(*) from public.post_comment_views)     <> 9   then raise exception 'CP0 drift: post_comment_views'; end if;
  if (select count(*) from public.follows)                <> 9   then raise exception 'CP0 drift: follows'; end if;
  if (select count(*) from public.connected_attachments)  <> 25  then raise exception 'CP0 drift: connected_attachments'; end if;
  if (select count(*) from public.membership)             <> 1   then raise exception 'CP0 drift: membership'; end if;
  if (select count(*) from public.membership_binding)     <> 1   then raise exception 'CP0 drift: membership_binding'; end if;
  if (select count(*) from public.shadow_enforcement_stat)<> 79  then raise exception 'CP0 drift: shadow_enforcement_stat'; end if;

  -- 1g. NOTHING IN THE RETAINED TABLES REFERENCES THE DELETE SET.
  --     A guard, deliberately, NOT a no-op DELETE: if drift introduced such a
  --     row, CP-0 must STOP rather than silently widen its own blast radius.
  select count(*) into v_n from public.connected_attachments a
   where a.sender_user_id    in (select user_id from cp0_delete)
      or a.recipient_user_id in (select user_id from cp0_delete);
  if v_n <> 0 then raise exception 'CP0 guard 1g: % connected_attachments row(s) reference the delete set', v_n; end if;

  -- 1h. No comment sits on a post about to be deleted.
  select count(*) into v_n from public.post_comments c
    join public.posts p on p.id = c.post_id
   where p.owner_user_id in (select user_id from cp0_delete);
  if v_n <> 0 then raise exception 'CP0 guard 1h: % comment(s) on deleted posts', v_n; end if;
end $$;

-- ── 2. CONTENT BEFORE IDENTITIES, IN THE MEASURED DEPENDENCY ORDER ────────

-- 2a. post_comment_views FIRST: it has NO foreign key in either direction, so
--     it orphans off deleted viewers AND off deleted posts. Both clauses are
--     present; the second is measured 0 today and is not assumed to stay 0.
delete from public.post_comment_views v
 where v.viewer_user_id in (select user_id from cp0_delete)
    or v.post_id in (select p.id from public.posts p
                      where p.owner_user_id in (select user_id from cp0_delete));

-- 2b. posts. Cascades post_comments and post_shares via post_id (measured 0 each).
delete from public.posts p
 where p.owner_user_id in (select user_id from cp0_delete);

-- 2c. auth.users LAST. Cascades account_directory, follows (both directions),
--     membership, membership_binding, membership_binding_conflict,
--     shadow_enforcement_stat, and the auth.* set including sessions, whose
--     cascade carries refresh_tokens and mfa_amr_claims.
delete from auth.users u
 where u.id in (select user_id from cp0_delete);

-- ── 3. FINAL VERIFICATION ROW. RETURNS A ROW, ALWAYS. ─────────────────────
--     "Success. No rows returned" must be the SYMPTOM, never the disguise.
select
  (select count(*) from auth.users)                     as auth_users,          -- 2
  (select count(*) from public.account_directory)       as directory,           -- 2
  (select count(*) from public.posts)                   as posts,               -- 7
  (select count(*) from public.post_comments)           as comments,            -- 5
  (select count(*) from public.post_shares)             as shares,              -- 0
  (select count(*) from public.post_comment_views)      as comment_views,       -- 3
  (select count(*) from public.follows)                 as follows,             -- 2
  (select count(*) from public.follows
    where status='approved')                            as follows_approved,    -- 2
  (select count(*) from public.connected_attachments)   as conn_attachments,    -- 25
  (select count(*) from public.membership)              as membership,          -- 1
  (select count(*) from public.membership_binding)      as binding,             -- 1
  (select count(*) from public.membership_binding_conflict) as conflicts,       -- 0
  (select count(*) from public.shadow_enforcement_stat) as shadow,              -- 75
  (select count(*) from public.membership_notification) as notifications,       -- 74
  (select count(*) from auth.identities)                as identities,          -- 2
  (select count(*) from auth.sessions)                  as sessions,            -- 23
  (select count(*) from auth.refresh_tokens)            as refresh_tokens,      -- 382
  (select count(*) from auth.mfa_amr_claims)            as amr_claims,          -- 23
  (select count(*) from storage.objects
    where bucket_id='avatars')                          as obj_avatars,         -- 3, UNCHANGED
  (select count(*) from storage.objects
    where bucket_id='attachments')                      as obj_attachments,     -- 10, UNCHANGED
  (select count(*) from public.follows f
    where f.status='approved'
      and left(md5(f.follower_user_id::text),8) in ('1fbf664a','64ffb132')
      and left(md5(f.followed_user_id::text),8) in ('1fbf664a','64ffb132')
      and f.follower_user_id <> f.followed_user_id)     as keeper_mutual_follow;-- 2

commit;
```

**The two storage counts in the final row are deliberately the PRE-deletion
values**, because storage is not transactional with Postgres and has not been
touched at commit time. **A run that reports 1 and 8 here has done something
nobody asked for.**

---

## 5. POST-COMMIT STORAGE DELETION

**Only after the transaction has committed and its verification row has been
checked against §3.** Four objects, **by explicit path**, staged outside the
repository.

**Ordering:** database first, storage second. If the transaction aborts, the
objects are still present and nothing is inconsistent. **The reverse order could
destroy objects for a deletion that then rolls back**, which is unrecoverable —
there is no backup of Domain 3 content.

**Verification is against `storage.objects`, never an HTTP `GET`** — P4-U4
measured a `GET` returning **200 after a successful DELETE**, and that unit
stopped itself over exactly this. Expected afterwards: `avatars` **3 → 1**,
`attachments` **10 → 8**.

**`supabase storage rm` silently no-ops** at CLI 2.113.0 — exit 0, empty
`deleted` list, no DELETE issued. See `supabase/README.md` for the working route.

---

## 6. WHAT ABORTS THE RUN

**Any** guard failure, **any** census drift, **any** verification-row figure not
matching §3. **No figure is repaired forward and no statement is re-run with a
widened predicate.** The transaction rolls back whole; storage is untouched
because it has not been reached.

---

## 7. RE-CENSUS IS MANDATORY

**Today's census is NOT execution authority.** It must be re-taken immediately
before execution and compared to §3 line by line. Guard **1f** enforces this
inside the transaction — but the comparison is done first, by a person, because
a guard that aborts is a failed run and the point is not to start one.

## 8. NOT EXECUTED

**No mutation has been performed.** This document is a prediction awaiting
review.
