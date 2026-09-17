# Claude closing check — Connected Lists backend deployment

2026-09-17. **READ-ONLY.** No repo edit, commit, push, deployment or live mutation.

## VERDICT: **ACCEPTED**

Applied and **structurally verified**. No discrepancy. One apparent ninth-surface change was
investigated to root cause and is **serialization, not schema** (§3). **Device
send/receive/adopt remains outstanding and is correctly not claimed.**

Everything below was verified by me from the evidence and the repository, not taken from the
automated result.

## 1. The apply

`lists-production-apply.json` contains **exactly one row**:

```json
"rows": [ { "verification": "Lists MIME enabled" } ]
```

No error object. `stderr` is a benign `Initialising login role...`. Applied
**2026-09-17T08:24:17.642957+00:00**.

This is the condition that mattered: in this project an apply once reported
*"Success. No rows returned."* while changing **nothing**, and the exit code is `0` even on
an aborted submission. **The verification row is present, so the intended text ran.**

`lists-postdeploy-validated.json` returns both constraints with **`convalidated: true`**.

## 2. The delta — verified independently against HEAD

| Surface | Result |
|---|---|
| `constraints.json` | **CHANGED, as predicted** |
| `storage_buckets.json` | **CHANGED, as predicted** |
| `columns.json`, `column_grants.json`, `function_grants.json`, `functions.json`, `policies.json`, `rls_enabled.json`, `table_grants.json`, `triggers.json` | **UNCHANGED vs HEAD** |

**`constraints.json` — exactly two changes, both on `connected_attachments`:**

- **added** `connected_attachments_list_metadata`:
  `CHECK (((mime_type <> 'application/vnd.etudes.list+json') OR (((byte_count >= 1) AND (byte_count <= 131072)) AND (page_count = 0) AND (storage_path ~~ '%.etudeslist'))))`
  — semantically identical to the reviewed text, with Postgres's normal rewriting of
  `BETWEEN` to `>= AND <=` and `LIKE` to `~~`.
- **modified** `connected_attachments_supported_mime_types`, now **13 types**, the added one
  being `application/vnd.etudes.list+json`.

**No other table's constraints moved.**

**`storage_buckets.json`:** attachments allowlist **13 → 14**, the new type **appended
last** after `audio/aac`; `public = false` and `file_size_limit = 157286400` unchanged.
Appending last is what lets a future `array_remove` restore byte-identity.

**This matches the reviewed change with nothing extra.** No policy, grant, function,
trigger, table or column moved — so eligibility, approved-follow direction, entitlement
enforcement and the teen position are untouched, as intended.

## 3. The one thing that looked like a discrepancy, and is not

A raw byte comparison of the ad-hoc pre-apply capture against the repo snapshot shows
`functions.json` differing — a **ninth** surface, contradicting the claim of eight unchanged.
**It is serialization only, and I confirmed the cause independently before accepting the
explanation.**

- **Full ordered whole-document equality** — `json.loads(before) == json.loads(after)` over
  the entire file, with **no keying and no dictionary collapsing** — returns **True**.
- **41 definitions compared positionally: 0 differ.**
- Raw difference is **exactly 15 bytes**, accounted for precisely: five non-ASCII characters
  — **U+2019 ×2, U+201C, U+201D, U+2014** — escaped as `\uXXXX` (6 ASCII bytes) in the
  preflight capture and literal UTF-8 (3 bytes) in the canonical one. **5 × 3 = 15.**
- The characters sit in three **SQL comments** (`get_unread_private_comment_groups`,
  `has_unread_private_comments`, `search_account_directory`) — typographic punctuation, not
  logic.
- **Working-tree `supabase/schema/functions.json` is BYTE-IDENTICAL to
  `git show 1f36ef1:supabase/schema/functions.json`** — the repo file never moved.

**No SQL definition changed.** The preflight uses `json.dumps` with `ensure_ascii=True`;
canonical `capture-schema.sh` uses `jq -S` with literal Unicode. The two capture paths differ
in encoding, not content.

**Two corrections belong to me here, and both are worth recording.** My first two attempts at
this comparison were **keyed dictionaries** — first on absent field names, then on `proname`
— and each silently collapsed rows and returned a vacuous "identical". **A keyed comparison
that silently drops rows reports success for a check it never performed**, which is the same
failure shape as this project's earlier source-text assertions. The positional comparison,
and the whole-document equality Codex named, are the honest forms. **Compare decoded JSON,
never bytes, whenever the two capture paths are mixed** — otherwise escaping noise can both
manufacture a false alarm and, more dangerously, hide a real change inside it.

## 4. Provenance and scope

- **The deployed source is what I reviewed.** All three SQL artefacts at `1f36ef1` hash
  **exactly** to my reviewed values: migration `6b6dcdb4…`, apply `47f290f3…`, rollback
  `09cda905…`.
- **Commit `1f36ef1` is 9 files** — the SQL, the test scripts, and the review/deployment
  notes. **Zero app, legal, invitation or `AGENTS.md` files.** Unrelated work preserved.
- **Nothing is pushed.** HEAD is 1 commit ahead of `origin/feature/solo-connected`.
- **No rollback executed, no device operated.**

## 5. Outstanding, and correctly recorded as such

- **Snapshot commit pending**, as intended: `supabase/schema/constraints.json`,
  `supabase/schema/storage_buckets.json`, and the updated
  `docs/connected-lists-backend-deployment.md`.
- **`docs/connected-lists-review.md` is untracked** — flagged only so it is not lost or
  swept; my review is committed separately as `docs/connected-lists-backend-review.md`.
- **Device acceptance is NOT claimed**, and the deployment record says so in its own words.
  **This is the right distinction and it should survive into whatever closes the feature:**
  the local delivery checks used **synthetic membership fixtures and temporary policy
  definitions** inside a rolled-back transaction, so a real Person send, receive and Save to
  Lists across the two devices is what settles it. Until then this is *applied and
  structurally verified*, nothing more.

## 6. What I did not do

No live production query — every schema fact here comes from the evidence files and the
repository. I did not run the test scripts, any build, or any device action, and I did not
re-execute the apply or the rollback.

**Accepted. Deployment and the snapshot commit remain Codex's under Samuel's existing
approval; nothing here changes that scope.**
