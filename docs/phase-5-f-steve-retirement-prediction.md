# STEVE RETIREMENT — PRE-MUTATION PREDICTION AND CHECKLIST. 2026-09-07

**COMMITTED BEFORE MUTATION. NOTHING HAS BEEN DELETED AT THIS COMMIT.**

**Authorised:** the 3 Samuel-authored comments on Steve's post are disposable
beta/test data and may go by cascade; Device A's local journal, Scores and media
are disposable and may be erased.

**Method:** the app's **real** *Erase all Études data and account* path
(`delete_account_v1` + `LocalFactoryReset`), not a hand-written SQL deletion. That
is deliberate — it exercises the shipping product path rather than simulating it.

---

## 1. PRE-STATE, MEASURED

| measure | value | | measure | value |
|---|---|---|---|---|
| `auth.users` | **2** | | `membership` | **1** |
| `auth.identities` | **2** | | `membership_binding` | **1** |
| `account_directory` | **2** | | `account_privacy` | **0** |
| `posts` | **7** | | `shadow_enforcement_stat` | **75** |
| `post_comments` | **5** | | — of which Steve's | **41** |
| `follows` (all / approved) | **2 / 2** | | storage `attachments` | **8** |
| `post_shares` | **0** | | storage `avatars` | **1** |
| `post_comment_views` | **3** | | `membership_notification` | **74** |
| `connected_attachments` | **25** | | | |

## 2. PREDICTED POST-STATE — SCORED EXACTLY

| measure | before | **after** | why |
|---|---|---|---|
| `auth.users` | 2 | **1** | Steve deleted **strictly last** |
| `auth.identities` | 2 | **1** | cascade |
| `account_directory` | 2 | **1** | explicit, then cascade |
| `posts` | 7 | **6** | Steve owned 1 |
| **`post_comments`** | 5 | **1** | 1 Steve authored + **3 Samuel-authored on Steve's post, by `post_id` cascade** |
| `follows` (all / approved) | 2 / 2 | **0 / 0** | **the entire mutual approved follow** |
| `membership` / `binding` | 1 / 1 | **0 / 0** | cascade |
| `shadow_enforcement_stat` | 75 | **34** | 41 were Steve's |
| storage `attachments` | 8 | **7** | 1 object under `users/<steve>/` |
| storage `avatars` | 1 | **1** | **Steve has none; Samuel's must survive** |
| `post_comment_views` | 3 | **3** | all Samuel's |
| `connected_attachments` | 25 | **25** | none reference Steve |
| `post_shares` | 0 | **0** | none exist |
| `account_privacy` | 0 | **0** | none exist |
| `membership_notification` | 74 | **74** | not user-keyed |

## 3. SAMUEL-OWNED DATA THAT MUST REMAIN — THE NEGATIVE CONTROLS

**If any of these moves, the run is a failure regardless of the other numbers.**

| Samuel (`1fbf664a`) | must be |
|---|---|
| identity present | **yes** |
| `account_directory` row | **present**, `account_id` = `samueldixon` |
| **avatar** (`avatar_key` non-null **and** the storage object) | **present** — C-34's fixture |
| posts owned | **6** |
| comments **authored** | **1** (was 4; 3 die with Steve's post) |
| `post_comment_views` | **3** |
| `membership` / `account_privacy` | **0 / 0** |

## 4. DEVICE A EXPECTED END STATE

- **first-run / onboarding**, not the journal — **C-49's exact assertion**, which
  was device-verified on 2026-08-15 and is re-exercised here;
- local journal, Scores, media and profile **erased**;
- **no Connected identity**, so `hasConnectedIdentity` is **false** — which is what
  makes the next CP-3 run take the genuine new-user path;
- the **Sandbox Apple Account `sdsongsltd+devicec@gmail.com` and its Age
  Assurance fixture remain in place** — they are device/Apple settings, untouched
  by an app erase.

## 5. WHAT IS BEING GIVEN UP, RECORDED AS A DELIBERATE RETIREMENT

**The Samuel↔Steve Phase-4 fixture is deliberately retired.** Phase 4's
conditions **2**, **8** and **C-34's avatar verification** remain **OUTSTANDING**
and now additionally require a **replacement entitled fixture** — two Connected
identities with an approved follow, which **cannot be built until a real
Production subscription exists**, because `follows_insert_requester`,
`posts` INSERT/SELECT and `storage.avatars` INSERT are all gated by
`enforcement_gate`.

**This is not a downgrade of those conditions.** They were already unreachable
for the same reason; what changes is that the fixture must be rebuilt when
entitlement arrives rather than found waiting. **Creating that follow is itself
part of what conditions 2 and 8 exercise.**

## 6. ABORT CONDITIONS

Any Samuel negative control in §3 moving; any §2 figure not matching; the erase
reporting success while `auth.users` remains 2. **Report, do not repair forward.**

## 7. STATUS

**NOTHING DELETED AT THIS COMMIT.**
