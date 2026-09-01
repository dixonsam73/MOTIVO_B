-- G11 PRECONDITION — delete the single membership row so the server no longer
-- knows this identity, leaving membership_binding INTACT.
--
-- RUN THIS ONLY IMMEDIATELY BEFORE THE COLD LAUNCH. The fixture is a live
-- Sandbox subscription on a ~30-minute renewal cycle under Apple's ~12-renewal
-- cap; a long gap between this and the relaunch risks the entitlement expiring
-- and the gate becoming unscoreable.
--
-- ONE SUBMISSION, GUARD INSIDE, ENDING IN A SELECT THAT RETURNS A ROW.
-- "Success. No rows returned." is the symptom of a submission that ran the wrong
-- text -- it happened on the U6a deploy and cost a full diagnosis cycle.
--
-- membership_binding IS NEVER TOUCHED, and both the pre- and post-conditions
-- assert it by exact timestamp. A deleted binding would mint a new token,
-- mismatch, and reject the legitimate owner as a conflict.

begin;

do $g11$
declare n integer; b integer;
begin
  -- PRECONDITION 1 — exactly one membership row
  select count(*) into n from public.membership;
  if n <> 1 then
    raise exception 'ABORT: expected exactly 1 membership row, found %', n;
  end if;

  -- PRECONDITION 2 — the binding row is the expected, never-updated one
  select count(*) into b from public.membership_binding
   where created_at = timestamptz '2026-08-25 17:31:54.005854+00'
     and updated_at = timestamptz '2026-08-25 17:31:54.005854+00';
  if b <> 1 then
    raise exception 'ABORT: binding row is not the expected untouched one (matched %)', b;
  end if;

  -- PRECONDITION 3 — the fixture must still be ENTITLED.
  -- Deleting a dead fixture spends it and leaves nothing to score.
  select count(*) into n from public.membership
   where original_transaction_id = '2000001228947923' and renewal_date > now();
  if n <> 1 then
    raise exception 'ABORT: subscription is no longer entitled -- the G11 fixture is spent. Resubscribe first; do not delete a dead fixture.';
  end if;

  -- THE DELETION, scoped to the subscription this gate is about
  delete from public.membership where original_transaction_id = '2000001228947923';
  get diagnostics n = row_count;
  if n <> 1 then
    raise exception 'ABORT: expected to delete exactly 1 row, deleted %', n;
  end if;

  -- POSTCONDITION 1 — membership is empty
  select count(*) into n from public.membership;
  if n <> 0 then
    raise exception 'ABORT: membership should be empty, found %', n;
  end if;

  -- POSTCONDITION 2 — membership_binding UNTOUCHED, by exact timestamp
  select count(*) into b from public.membership_binding
   where created_at = timestamptz '2026-08-25 17:31:54.005854+00'
     and updated_at = timestamptz '2026-08-25 17:31:54.005854+00';
  if b <> 1 then
    raise exception 'ABORT: membership_binding was modified -- this must never happen';
  end if;

  -- POSTCONDITION 3 — no conflict manufactured
  select count(*) into n from public.membership_binding_conflict;
  if n <> 0 then
    raise exception 'ABORT: a binding conflict row appeared (%)', n;
  end if;
end
$g11$;

commit;

-- Returns a ROW. No UID is selected.
select
  (select count(*) from public.membership)                                  as membership_rows,
  (select count(*) from public.membership_binding)                          as binding_rows,
  (select min(created_at) = min(updated_at) from public.membership_binding) as binding_never_updated,
  (select count(*) from public.membership_binding_conflict)                 as conflicts,
  (select public.membership_state(b.user_id)  from public.membership_binding b) as state_after,
  (select public.connected_member(b.user_id)  from public.membership_binding b) as connected_member_after,
  'G11 PRECONDITION SET -- membership deleted, binding intact'              as status;
