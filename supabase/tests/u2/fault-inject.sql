-- U2 / B-4 fault injection. LOCAL DISPOSABLE DATABASE ONLY.
--
-- WHY THIS SHAPE. B-4 requires delete_account_v1 to fail HONESTLY at a named
-- step after meaningful work has begun. The three routes rejected in Phase 1
-- stay rejected: no temporarily-broken production deploy, no QA-only failure
-- injection inside the function, no DDL against production.
--
-- This is the fourth route, available only now that B-23 exists: DDL against a
-- disposable local database. It CANNOT alter production behaviour, because
--   (a) it is applied by hand to the local instance and is not in
--       supabase/migrations/, so no reproduction of the baseline contains it —
--       the B-23 gate would fail on an extra trigger if it ever did; and
--   (b) delete_account_v1's source is not touched at all. The function under
--       test is the real one, byte-identical to the deployed executable body.
--
-- It fires on the `posts` delete, which is step 5's fourth statement — after
-- received attachment rows, the recursive storage sweep, sent attachment rows,
-- the avatar sweep, post_comment_views, post_shares and post_comments have all
-- already succeeded. That is what makes the failure meaningful rather than an
-- early rejection.
create or replace function public.u2_b4_fault() returns trigger
language plpgsql as $$
begin
  raise exception 'U2/B-4 injected fault: posts delete blocked';
end;
$$;

create trigger u2_b4_fault_posts
  before delete on public.posts
  for each row execute function public.u2_b4_fault();
