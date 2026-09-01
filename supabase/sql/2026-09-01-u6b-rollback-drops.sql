-- U6b ROLLBACK, PART 2 — drop the additive objects.
--
-- RUN ONLY AFTER 2026-09-01-u6b-rollback-baseline-production.sql, never before.
-- That file restores the 23 policies and recreates `shadow_observe`; dropping
-- `enforcement_gate` first would leave 23 policies referencing a function that
-- no longer exists.
--
-- Rehearsed end to end locally on 2026-09-01: after this the B-23 gate returns
-- GATE MET, which is the real proof -- not that the drops succeeded, but that
-- the instance is structurally identical to production again.

begin;

drop trigger tg_posts_entitled_until     on public.posts;
drop trigger tg_shares_entitled_until    on public.post_shares;
drop trigger tg_follows_entitled_until   on public.follows;
drop trigger tg_directory_entitled_until on public.account_directory;
drop trigger tg_membership_propagate     on public.membership;

drop function public.tg_set_entitled_until();
drop function public.tg_membership_propagate_entitled_until();
drop function public.enforcement_gate(text);
drop function public.enforcement_active();
drop function public.membership_entitled_until(uuid);

alter table public.posts             drop column owner_entitled_until;
alter table public.post_shares       drop column owner_entitled_until;
alter table public.follows           drop column followed_entitled_until;
alter table public.account_directory drop column entitled_until;
alter table public.membership_control drop column enforcement_enabled;

-- `enforced` is IN the primary key, so the constraint comes off first and the
-- U6a-era key goes back on.
alter table public.shadow_enforcement_stat drop constraint shadow_enforcement_stat_pkey;
alter table public.shadow_enforcement_stat drop column enforced;
alter table public.shadow_enforcement_stat
  add constraint shadow_enforcement_stat_pkey
  primary key (user_id, surface, decided_clause, bucket_hour);

commit;

select
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public') as public_functions,
  (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','storage') and not t.tgisinternal) as triggers,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='shadow_observe') as shadow_observe_restored,
  'U6b ROLLED BACK' as status;
