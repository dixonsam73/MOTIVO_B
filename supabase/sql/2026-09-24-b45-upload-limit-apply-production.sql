-- B-45 production apply. Requires Codex review and Samuel's approval before use.
-- Run: supabase db query --linked -f supabase/sql/2026-09-24-b45-upload-limit-apply-production.sql
-- Expect the final row: attachments | 52428800. Any other value means it did not apply.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
-- B-45: the Connected attachments bucket enforces the published 50 MiB per-file
-- limit (52428800 bytes), matching the client preflight. Changes only
-- file_size_limit. Existing objects are unaffected; none exceeded 50 MiB in
-- production when this was written (read-only check, 2026-09-24).
DO $b45_pre$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id='attachments'
      AND NOT public AND file_size_limit=157286400
      AND allowed_mime_types = ARRAY['application/pdf','image/jpeg','image/png','image/heic','image/heif','video/mp4','video/quicktime','audio/m4a','audio/mp4','audio/x-m4a','audio/mpeg','audio/wav','audio/aac','application/vnd.etudes.list+json']::text[]) THEN
    RAISE EXCEPTION 'B-45: unexpected attachments bucket configuration';
  END IF;
END $b45_pre$;

UPDATE storage.buckets SET file_size_limit = 52428800 WHERE id='attachments';

DO $b45_post$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id='attachments'
      AND NOT public AND file_size_limit=52428800
      AND allowed_mime_types = ARRAY['application/pdf','image/jpeg','image/png','image/heic','image/heif','video/mp4','video/quicktime','audio/m4a','audio/mp4','audio/x-m4a','audio/mpeg','audio/wav','audio/aac','application/vnd.etudes.list+json']::text[]) THEN
    RAISE EXCEPTION 'B-45: attachments bucket limit was not applied';
  END IF;
END $b45_post$;
COMMIT;
SELECT id, file_size_limit FROM storage.buckets WHERE id='attachments';
