-- B-45 rollback: restores the previous 150 MiB bucket limit. Review before use.
-- Expect the final row: attachments | 157286400.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id='attachments'
      AND NOT public AND file_size_limit=52428800
      AND allowed_mime_types = ARRAY['application/pdf','image/jpeg','image/png','image/heic','image/heif','video/mp4','video/quicktime','audio/m4a','audio/mp4','audio/x-m4a','audio/mpeg','audio/wav','audio/aac','application/vnd.etudes.list+json']::text[]) THEN
    RAISE EXCEPTION 'B-45 rollback: bucket is not in the B-45 state; re-review required';
  END IF;
END $guard$;
UPDATE storage.buckets SET file_size_limit = 157286400 WHERE id='attachments';
COMMIT;
SELECT id, file_size_limit FROM storage.buckets WHERE id='attachments';
