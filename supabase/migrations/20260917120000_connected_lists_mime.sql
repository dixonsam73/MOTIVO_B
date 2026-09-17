-- Lists v1: storage-backed structured payload through the existing Connected inbox.
-- LOCAL / NOT DEPLOYED. This deliberately changes no eligibility, RLS, notification,
-- membership, account-deletion function, grant or existing attachment MIME type.
DO $lists_pre$
BEGIN
  IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conrelid='public.connected_attachments'::regclass
        AND conname='connected_attachments_supported_mime_types')
      IS DISTINCT FROM $expected$CHECK ((mime_type = ANY (ARRAY['application/pdf'::text, 'image/jpeg'::text, 'image/png'::text, 'image/heic'::text, 'image/heif'::text, 'audio/mpeg'::text, 'audio/mp4'::text, 'audio/x-m4a'::text, 'audio/wav'::text, 'audio/aac'::text, 'video/mp4'::text, 'video/quicktime'::text])))$expected$ THEN
    RAISE EXCEPTION 'Lists: unexpected existing MIME constraint';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id='attachments'
      AND NOT public AND allowed_mime_types = ARRAY['application/pdf','image/jpeg','image/png','image/heic','image/heif','video/mp4','video/quicktime','audio/m4a','audio/mp4','audio/x-m4a','audio/mpeg','audio/wav','audio/aac']::text[]
      AND file_size_limit=157286400) THEN
    RAISE EXCEPTION 'Lists: unexpected attachments bucket configuration';
  END IF;
END $lists_pre$;

ALTER TABLE public.connected_attachments
  DROP CONSTRAINT connected_attachments_supported_mime_types,
  ADD CONSTRAINT connected_attachments_supported_mime_types CHECK ((mime_type = ANY (ARRAY['application/pdf'::text, 'image/jpeg'::text, 'image/png'::text, 'image/heic'::text, 'image/heif'::text, 'audio/mpeg'::text, 'audio/mp4'::text, 'audio/x-m4a'::text, 'audio/wav'::text, 'audio/aac'::text, 'video/mp4'::text, 'video/quicktime'::text, 'application/vnd.etudes.list+json'::text]))),
  ADD CONSTRAINT connected_attachments_list_metadata CHECK (
    mime_type <> 'application/vnd.etudes.list+json' OR
    (byte_count BETWEEN 1 AND 131072 AND page_count = 0 AND storage_path LIKE '%.etudeslist')
  );
UPDATE storage.buckets SET allowed_mime_types = array_append(allowed_mime_types, 'application/vnd.etudes.list+json')
  WHERE id='attachments';

DO $lists_post$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id='attachments'
      AND NOT public AND 'application/vnd.etudes.list+json' = ANY(allowed_mime_types)) THEN
    RAISE EXCEPTION 'Lists: MIME type was not enabled on private bucket';
  END IF;
  IF (SELECT count(*) FROM pg_constraint WHERE conrelid='public.connected_attachments'::regclass
      AND conname IN ('connected_attachments_supported_mime_types','connected_attachments_list_metadata')
      AND convalidated) <> 2 THEN
    RAISE EXCEPTION 'Lists: expected validated constraints';
  END IF;
END $lists_post$;
