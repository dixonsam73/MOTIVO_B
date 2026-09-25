-- B-46 weekly Connected storage usage. Read-only. See supabase/README.md.
with o as (
  select lower((storage.foldername(name))[2]) as member,
         coalesce((metadata->>'size')::bigint, 0) as bytes,
         created_at
  from storage.objects
  where bucket_id = 'attachments'
), m as (
  select member, count(*) as files, sum(bytes) as bytes,
         sum(bytes) filter (where created_at > now() - interval '30 days') as bytes_30d
  from o group by member
)
(select 'ALL MEMBERS' as member, sum(files) as files,
        round(sum(bytes) / 1e9, 2) as gb, round(coalesce(sum(bytes_30d), 0) / 1e9, 2) as gb_last_30d
 from m)
union all
(select member, files, round(bytes / 1e9, 2), round(coalesce(bytes_30d, 0) / 1e9, 2)
 from m order by bytes desc limit 10);
