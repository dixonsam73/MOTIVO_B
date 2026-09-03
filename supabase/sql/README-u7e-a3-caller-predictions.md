# U7e A3 — REPLACEMENT CALLER. PREDICTIONS, COMMITTED BEFORE THE WORKFLOW CHANGES. 2026-09-03

**Written before `.github/workflows/membership-cleanup.yml` was modified.** Scored
afterwards. Not edited after measurement; a miss is recorded as a miss.

**Why the caller is being replaced, stated once and then closed.** A stock-runner
`curl` invocation logged a 29-byte body and `uploaded_bytes=29`, while the
authenticated handler recorded **83 bytes, unparseable, no `mode` field, no
content-type**, arriving by the normal Cloudflare route with
`content-length: 83`. That payload was never identified. **The replacement avoids
the condition rather than explaining it**, and the investigation is closed unless
the new caller reproduces it.

**Nothing about the worker changes.** Cleanup eligibility, the Apple authority
path, the deletion logic and the `CLEANUP_INVOKE_KEY` boundary are untouched.

---

## 1. WHAT CHANGES

**One `run:` block.** `on:`, the concurrency group, `permissions`, the *Resolve
mode* step and the *Summary* step are untouched.

`curl` is replaced by inline `python3` + `urllib.request` — stdlib only, stock on
`ubuntu-latest`, no action and no new dependency. The heredoc delimiter is
**quoted** (`<<'PY'`), so the shell interpolates nothing: **the payload never
crosses a shell/argv boundary**, which is the boundary that proved ambiguous.

**The caller now fingerprints what it sends** — byte length and SHA-256 — so
agreement with the handler's `raw_sha256` is *provable at both ends* rather than
inferred. It also reports whether proxy environment variables are present
(boolean only; a proxy URL can embed credentials and is never printed).

---

## 2. PRESERVED, AND ASSERTED RATHER THAN ASSUMED

| Property | How it stays true |
|---|---|
| `CLEANUP_INVOKE_KEY` auth boundary | sent as `Authorization: Bearer …`, read from **env**, never argv, so it cannot appear in a process listing |
| `CLEANUP_MODE` the sole mode control | the *Resolve mode* step is unmodified; the caller reads `MODE` from its output |
| unset → `dry_run` | unchanged in *Resolve mode* |
| daily schedule + manual dispatch | `on:` unmodified |
| UUID redaction | the same regex, applied in Python before anything is printed or written |
| non-200 fails the run | `sys.exit("::error::…")` on any status other than 200 |
| no service-role credential in GitHub | unchanged — GitHub holds only the dedicated invocation key |
| worker cleanup/authority logic | **no worker change at all** |

---

## 3. LOCAL PREDICTIONS

| ID | Prediction |
|---|---|
| **P-1** | `MODE=execute` → body `{"mode":"execute","limit":25}`, **29 bytes**, sha **`1c1d0b8d3562235732a3b60ba5fd5ed13685c733ae14e9f0b0567cc07597b93a`** |
| **P-2** | `MODE=dry_run` → body `{"mode":"dry_run","limit":25}`, **29 bytes**, sha **`21236d46dfef69e682cd859caf012685b77d2ac689434836fb6067068811640d`** |
| **P-3** | **Client SHA equals the handler's `raw_sha256`** in both modes — the property curl could never establish |
| **P-4** | Handler reports `parsed_type: object`, `top_level_keys: ['limit','mode']`, `header_content_type: application/json` |
| **P-5** | `MODE=execute` resolves to `mode:"execute"` at the handler; `MODE=dry_run` to `dry_run` |
| **P-6** | Missing `INVOKE_KEY` → the run **fails loudly** and invokes nothing |
| **P-7** | Missing `FN_URL` → the run **fails loudly** and invokes nothing |
| **P-8** | A non-200 response **fails the run** |
| **P-9** | The workflow YAML still parses; `on:` has `schedule` (`17 3 * * *`) and `workflow_dispatch` with **no inputs**; **zero `inputs.` references** |
| **P-10** | No secret is printed: no `set -x`, and the key appears only in the `Authorization` header |
| **P-11** | The worker file is **unchanged** by this commit |

---

## 4. PRODUCTION ACCEPTANCE — PREDICTIONS FOR THE SUPERVISED RUN

| ID | Prediction |
|---|---|
| **A-1** | Dispatch with `CLEANUP_MODE` **unset** → caller logs 29 bytes / `21236d46…`; handler reports the same sha, `mode_field:'dry_run'`, `parsed_type:object`, keys `['limit','mode']`, content-type present; response `mode:"dry_run"`, `identities:0` |
| **A-2** | With `CLEANUP_MODE=execute` → caller logs 29 bytes / `1c1d0b8d…`; handler reports the **same** sha and `mode_field:'execute'`; response **`mode:"execute"`, `identities:0`** |
| **A-3** | **Production byte-identical** across both runs: users 17, posts 101, comments 5, follows 9, attachment objects 15, avatars 3, `connected_attachments` 31, directory 17, `cleanup_claimed_at` `2026-09-03 08:14:36`, `cleanup_completed_at` **NULL**, `pending_cleanup_at` `2026-11-01 15:16:44+00`, `updated_at` `08:14:37`, `renewal_info_signed_date` `08:14:36.792`, conflicts 0, enforcement true, `pg_cron` 0 |
| **A-4** | `identities: 0` is **correct**, not a defect — nothing is due until 2026-11-01 |
| **A-5** | **A3 passes only on A-2**, the execute-mode GitHub path demonstrated correct end to end |

**FALSIFIER FOR THE WHOLE REPLACEMENT:** the handler reporting a byte count or
SHA that differs from the caller's. That would mean the Python caller reproduces
the 83-byte condition — the one circumstance in which the closed investigation
reopens, and it would place the cause upstream of the client entirely.
