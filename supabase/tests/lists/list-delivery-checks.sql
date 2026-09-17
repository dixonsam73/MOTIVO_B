-- Executed only in the local transaction owned by check-list-delivery.sh.
CREATE TEMP TABLE lists_test_ids AS SELECT gen_random_uuid() sender, gen_random_uuid() recipient,
    gen_random_uuid() second_recipient, gen_random_uuid() outsider, gen_random_uuid() asset;
GRANT SELECT ON lists_test_ids TO authenticated;
INSERT INTO auth.users (id,instance_id,aud,role,email,created_at,updated_at)
SELECT uid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
       uid::text||'@lists.local.invalid',now(),now()
FROM lists_test_ids, LATERAL unnest(ARRAY[sender,recipient,second_recipient,outsider]) uid;
INSERT INTO public.membership(user_id,environment,original_transaction_id,product_id,apple_status,
 renewal_date,is_in_billing_retry,renewal_info_signed_date,binding_method,bound_at)
SELECT uid,'Production','lists-'||uid,'fixture',1,now()+interval '1 day',false,now(),'purchase',now()
FROM lists_test_ids,LATERAL unnest(ARRAY[sender,recipient,second_recipient,outsider]) uid;
UPDATE public.membership_control SET enforcement_enabled=true WHERE id;
INSERT INTO public.account_privacy(user_id,age_band,lookup_enabled,lookup_set_under_band,follow_requests_enabled,follow_requests_set_under_band)
SELECT uid,CASE WHEN uid=recipient THEN 'band_13_17' ELSE 'band_18_plus' END,false,
 CASE WHEN uid=recipient THEN 'band_13_17' ELSE 'band_18_plus' END,true,
 CASE WHEN uid=recipient THEN 'band_13_17' ELSE 'band_18_plus' END
FROM lists_test_ids,LATERAL unnest(ARRAY[sender,recipient,second_recipient,outsider]) uid;
DO $setup$
DECLARE v lists_test_ids;
BEGIN
 SELECT * INTO v FROM lists_test_ids;
 IF NOT public.enforcement_active() OR NOT public.connected_member(v.sender)
    OR NOT public.connected_member(v.recipient) THEN RAISE EXCEPTION 'Fixture entitlement unavailable'; END IF;
END $setup$;

-- Teen initiates the permitted direction; sender approves it.
SELECT set_config('request.jwt.claims',json_build_object('sub',recipient,'role','authenticated')::text,true) IS NOT NULL FROM lists_test_ids;
SET LOCAL ROLE authenticated;
INSERT INTO public.follows(follower_user_id,followed_user_id,status) SELECT recipient,sender,'requested' FROM lists_test_ids;
RESET ROLE;
SELECT set_config('request.jwt.claims',json_build_object('sub',sender,'role','authenticated')::text,true) IS NOT NULL FROM lists_test_ids;
SET LOCAL ROLE authenticated;
UPDATE public.follows SET status='approved' WHERE follower_user_id=(SELECT recipient FROM lists_test_ids) AND followed_user_id=auth.uid();
RESET ROLE;
INSERT INTO public.follows(follower_user_id,followed_user_id,status) SELECT second_recipient,sender,'approved' FROM lists_test_ids;

-- The same teen cannot receive new requests to follow them (B40 remains intact).
SELECT set_config('request.jwt.claims',json_build_object('sub',outsider,'role','authenticated')::text,true) IS NOT NULL FROM lists_test_ids;
SET LOCAL ROLE authenticated;
DO $teen$
DECLARE v lists_test_ids;
BEGIN
 SELECT * INTO v FROM lists_test_ids;
 BEGIN
   INSERT INTO public.follows(follower_user_id,followed_user_id,status) VALUES(v.outsider,v.recipient,'requested');
   RAISE EXCEPTION 'FAIL: teen inbound follow was allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 RAISE NOTICE 'PASS: teen outbound follow/approval works; inbound teen follow stays denied';
END $teen$;
RESET ROLE;

SELECT set_config('request.jwt.claims',json_build_object('sub',sender,'role','authenticated')::text,true) IS NOT NULL FROM lists_test_ids;
SET LOCAL ROLE authenticated;
DO $send$
DECLARE v lists_test_ids;
BEGIN
 SELECT * INTO v FROM lists_test_ids;
 -- This is the existing app's ensemble delivery shape.
   INSERT INTO public.connected_attachments(asset_id,sender_user_id,recipient_user_id,storage_bucket,storage_path,filename,mime_type,byte_count,page_count)
   SELECT v.asset,v.sender,uid,'attachments','users/'||v.sender||'/connected/'||v.asset||'.etudeslist',
          'Friday.etudeslist','application/vnd.etudes.list+json',100,0
   FROM unnest(ARRAY[v.recipient,v.second_recipient]) uid
;
 IF EXISTS(SELECT 1 FROM public.connected_attachments WHERE asset_id=v.asset) THEN
   RAISE EXCEPTION 'FAIL: sender can read recipient state'; END IF;
 BEGIN
   INSERT INTO public.connected_attachments(asset_id,sender_user_id,recipient_user_id,storage_bucket,storage_path,filename,mime_type,byte_count,page_count)
   VALUES(v.asset,v.sender,v.outsider,'attachments','users/'||v.sender||'/connected/'||v.asset||'.etudeslist',
          'Friday.etudeslist','application/vnd.etudes.list+json',100,0);
   RAISE EXCEPTION 'FAIL: non-follower delivery was accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 RAISE NOTICE 'PASS: approved recipients receive; outsider denied; sender cannot read lifecycle';
END $send$;
RESET ROLE;
DO $count$
BEGIN
 IF (SELECT count(*) FROM public.connected_attachments WHERE asset_id=(SELECT asset FROM lists_test_ids))<>2 THEN
   RAISE EXCEPTION 'FAIL: expected two recipient deliveries'; END IF;
END $count$;
INSERT INTO storage.objects(bucket_id,name,metadata)
SELECT 'attachments','users/'||sender||'/connected/'||asset||'.etudeslist','{"mimetype":"application/vnd.etudes.list+json","size":100}'::jsonb FROM lists_test_ids;

-- Recipient read state and deletion are private and independent per delivery.
SELECT set_config('request.jwt.claims',json_build_object('sub',recipient,'role','authenticated')::text,true) IS NOT NULL FROM lists_test_ids;
SET LOCAL ROLE authenticated;
DO $receipt$
DECLARE v lists_test_ids;
BEGIN
 SELECT * INTO v FROM lists_test_ids;
 IF (SELECT count(*) FROM public.connected_attachments WHERE asset_id=v.asset AND viewed_at IS NULL)<>1 THEN
   RAISE EXCEPTION 'FAIL: recipient inbox/unread visibility'; END IF;
 IF NOT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='attachments' AND name='users/'||v.sender||'/connected/'||v.asset||'.etudeslist') THEN
   RAISE EXCEPTION 'FAIL: recipient cannot read list object'; END IF;
 UPDATE public.connected_attachments SET viewed_at=now() WHERE asset_id=v.asset AND viewed_at IS NULL;
 IF EXISTS(SELECT 1 FROM public.connected_attachments WHERE asset_id=v.asset AND viewed_at IS NULL) THEN
   RAISE EXCEPTION 'FAIL: mark viewed did not clear unread'; END IF;
 UPDATE public.connected_attachments SET deleted_at=now() WHERE asset_id=v.asset;
 IF EXISTS(SELECT 1 FROM public.connected_attachments WHERE asset_id=v.asset AND deleted_at IS NULL) THEN
   RAISE EXCEPTION 'FAIL: delete did not remove live reference'; END IF;
 IF EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='attachments' AND name='users/'||v.sender||'/connected/'||v.asset||'.etudeslist') THEN
   RAISE EXCEPTION 'FAIL: deleted recipient retains storage read'; END IF;
 RAISE NOTICE 'PASS: recipient can open, mark viewed and dismiss; deleted reference loses object access';
END $receipt$;
RESET ROLE;
DO $retained$
BEGIN
 IF (SELECT count(*) FROM public.connected_attachments WHERE asset_id=(SELECT asset FROM lists_test_ids) AND deleted_at IS NULL)<>1 THEN
   RAISE EXCEPTION 'FAIL: delete affected another recipient reference'; END IF;
 IF NOT EXISTS(SELECT 1 FROM storage.objects WHERE name LIKE '%'||(SELECT asset FROM lists_test_ids)||'.etudeslist') THEN
   RAISE EXCEPTION 'FAIL: recipient deletion removed shared object'; END IF;
 RAISE NOTICE 'PASS: shared object and second recipient survive delivery deletion';
END $retained$;

-- Expired recipients lose access, but send-time eligibility is still follow-based.
UPDATE public.membership SET renewal_date=now()-interval '1 day' WHERE user_id=(SELECT second_recipient FROM lists_test_ids);
SELECT set_config('request.jwt.claims',json_build_object('sub',second_recipient,'role','authenticated')::text,true) IS NOT NULL FROM lists_test_ids;
SET LOCAL ROLE authenticated;
DO $expired$
BEGIN
 IF EXISTS(SELECT 1 FROM public.connected_attachments WHERE asset_id=(SELECT asset FROM lists_test_ids)) THEN
   RAISE EXCEPTION 'FAIL: lapsed recipient can read inbox'; END IF;
 IF EXISTS(SELECT 1 FROM storage.objects WHERE name LIKE '%'||(SELECT asset FROM lists_test_ids)||'.etudeslist') THEN
   RAISE EXCEPTION 'FAIL: lapsed recipient can read object'; END IF;
 RAISE NOTICE 'PASS: recipient entitlement gates inbox and storage reads';
END $expired$;
RESET ROLE;
-- Expired sender cannot send even to an approved follower.
UPDATE public.membership SET renewal_date=now()-interval '1 day' WHERE user_id=(SELECT sender FROM lists_test_ids);
SELECT set_config('request.jwt.claims',json_build_object('sub',sender,'role','authenticated')::text,true) IS NOT NULL FROM lists_test_ids;
SET LOCAL ROLE authenticated;
DO $expired_sender$
DECLARE v lists_test_ids; a uuid:=gen_random_uuid();
BEGIN
 SELECT * INTO v FROM lists_test_ids;
 BEGIN
   INSERT INTO public.connected_attachments(asset_id,sender_user_id,recipient_user_id,storage_bucket,storage_path,filename,mime_type,byte_count,page_count)
   VALUES(a,v.sender,v.recipient,'attachments','users/'||v.sender||'/connected/'||a||'.etudeslist',
          'Friday.etudeslist','application/vnd.etudes.list+json',100,0);
   RAISE EXCEPTION 'FAIL: lapsed sender can send';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 RAISE NOTICE 'PASS: sender entitlement gates delivery';
END $expired_sender$;
RESET ROLE;
