DO $checks$
DECLARE sender uuid := gen_random_uuid(); recipient uuid := gen_random_uuid(); asset uuid := gen_random_uuid(); row_id uuid;
BEGIN
  INSERT INTO public.connected_attachments(asset_id,sender_user_id,recipient_user_id,storage_bucket,storage_path,filename,mime_type,byte_count,page_count)
  VALUES(asset,sender,recipient,'attachments','users/'||sender||'/connected/'||asset||'.etudeslist','Weekly work.etudeslist','application/vnd.etudes.list+json',100,0) RETURNING id INTO row_id;
  BEGIN
    UPDATE public.connected_attachments SET byte_count=131073 WHERE id=row_id;
    RAISE EXCEPTION 'Lists test failed: accepted metadata mutation';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'Lists test failed:%' THEN RAISE; END IF;
    IF SQLERRM <> 'Connected attachment identity and payload metadata are immutable' THEN RAISE; END IF;
  END;
  BEGIN
    INSERT INTO public.connected_attachments(asset_id,sender_user_id,recipient_user_id,storage_bucket,storage_path,filename,mime_type,byte_count,page_count)
    VALUES(asset,sender,gen_random_uuid(),'attachments','users/'||sender||'/connected/'||asset||'.etudeslist','Too big.etudeslist','application/vnd.etudes.list+json',131073,0);
    RAISE EXCEPTION 'Lists test failed: accepted oversized list metadata';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.connected_attachments(asset_id,sender_user_id,recipient_user_id,storage_bucket,storage_path,filename,mime_type,byte_count,page_count)
    VALUES(asset,sender,gen_random_uuid(),'attachments','users/'||sender||'/connected/'||asset||'.txt','Wrong extension.txt','application/vnd.etudes.list+json',100,0);
    RAISE EXCEPTION 'Lists test failed: accepted wrong extension';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  RAISE NOTICE 'PASS: valid list metadata accepted; immutable metadata, size and extension guards hold';
END $checks$;
