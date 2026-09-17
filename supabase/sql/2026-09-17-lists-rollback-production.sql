-- LOCAL REVIEW ARTIFACT. Refuses to strand delivered Lists or stored list files.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $guard$
BEGIN
  IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conrelid='public.connected_attachments'::regclass
        AND conname='connected_attachments_supported_mime_types')
      IS DISTINCT FROM $expected$CHECK ((mime_type = ANY (ARRAY['application/pdf'::text, 'image/jpeg'::text, 'image/png'::text, 'image/heic'::text, 'image/heif'::text, 'audio/mpeg'::text, 'audio/mp4'::text, 'audio/x-m4a'::text, 'audio/wav'::text, 'audio/aac'::text, 'video/mp4'::text, 'video/quicktime'::text, 'application/vnd.etudes.list+json'::text])))$expected$
     OR NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id='attachments'
        AND NOT public AND allowed_mime_types=ARRAY['application/pdf','image/jpeg','image/png','image/heic','image/heif','video/mp4','video/quicktime','audio/m4a','audio/mp4','audio/x-m4a','audio/mpeg','audio/wav','audio/aac','application/vnd.etudes.list+json']::text[]
        AND file_size_limit=157286400) THEN
    RAISE EXCEPTION 'Lists rollback: schema or bucket changed; re-review required';
  END IF;
  IF EXISTS (SELECT 1 FROM public.connected_attachments WHERE mime_type='application/vnd.etudes.list+json')
     OR EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id='attachments'
        AND (name LIKE '%.etudeslist' OR metadata->>'mimetype'='application/vnd.etudes.list+json')) THEN
    RAISE EXCEPTION 'Lists exist: retain backend and receiver support; disable new sending instead';
  END IF;
END $guard$;
ALTER TABLE public.connected_attachments
  DROP CONSTRAINT connected_attachments_list_metadata,
  DROP CONSTRAINT connected_attachments_supported_mime_types,
  ADD CONSTRAINT connected_attachments_supported_mime_types CHECK ((mime_type = ANY (ARRAY['application/pdf'::text, 'image/jpeg'::text, 'image/png'::text, 'image/heic'::text, 'image/heif'::text, 'audio/mpeg'::text, 'audio/mp4'::text, 'audio/x-m4a'::text, 'audio/wav'::text, 'audio/aac'::text, 'video/mp4'::text, 'video/quicktime'::text])));
UPDATE storage.buckets SET allowed_mime_types=array_remove(allowed_mime_types,'application/vnd.etudes.list+json') WHERE id='attachments';
COMMIT;
SELECT 'Lists MIME rolled back (no list objects or deliveries existed)' AS verification;
