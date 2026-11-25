-- Run against a disposable/test database after applying the migrations.
-- The transaction rolls back its fixture camera and events.
begin;
do $$
declare c uuid; t timestamptz := clock_timestamp() - interval '10 seconds'; n integer; expiry timestamptz;
begin
  insert into public.xbox_cameras(label) values ('transactional-expiry-test') returning id into c;
  insert into public.xbox_detection_events(camera_id,session_id,event_type,meta) values
    (c,'test-session','motion',jsonb_build_object('detected_at',t)),
    (c,'test-session','motion',jsonb_build_object('detected_at',t)),
    (c,'test-session','motion',jsonb_build_object('detected_at',t-interval '1 minute')),
    (c,'test-session','test',jsonb_build_object('detected_at',t)),
    (c,'test-session','motion',jsonb_build_object('detected_at','invalid'));
  select count(*), max(expires_at) into n, expiry from public.drone_dispatch_requests where camera_id=c;
  if n <> 1 or expiry <> t+interval '20 seconds' then raise exception 'deduplication or expiry failed'; end if;
  update public.xbox_cameras set armed=false where id=c;
  insert into public.xbox_detection_events(camera_id,session_id,event_type,meta)
    values (c,'test-session','motion',jsonb_build_object('detected_at',clock_timestamp()));
  select count(*) into n from public.drone_dispatch_requests where camera_id=c;
  if n <> 1 then raise exception 'disarmed camera queued an alert'; end if;
end $$;
rollback;
