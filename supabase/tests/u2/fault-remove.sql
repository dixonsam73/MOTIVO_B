-- U2 / B-13. Removes the B-4 fault so the SAME deletion can be retried from the
-- real partial state it left behind.
drop trigger if exists u2_b4_fault_posts on public.posts;
drop function if exists public.u2_b4_fault();
