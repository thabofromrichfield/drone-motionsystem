-- Authenticated phone-camera-to-controller database flow; always rolled back.
begin;
create temp table fixture(user_id uuid);
grant select on fixture to authenticated;
insert into fixture values (gen_random_uuid());
insert into auth.users(id,email,email_confirmed_at)
  select user_id,'phone-flow@example.invalid',now() from fixture;
insert into public.drone_operators(user_id) select user_id from fixture;
set local role authenticated;
select set_config('request.jwt.claim.sub',(select user_id::text from fixture),true);
do $$
<<mobile_flow>>
declare camera jsonb; session jsonb; claim jsonb; event_id bigint; n integer;
begin
  camera := public.xbox_register_camera('Phone fixture','mobile',null,'browser');
  perform public.xbox_heartbeat((camera->>'id')::uuid,'online','motion-only',8,0);
  session := public.drone_arm_controller();
  insert into public.xbox_detection_events(camera_id,session_id,event_type,meta)
    values ((camera->>'id')::uuid,'phone-session','motion',jsonb_build_object('detected_at',clock_timestamp()))
    returning id into event_id;
  select count(*) into n from public.drone_dispatch_requests r where r.event_id=mobile_flow.event_id;
  if n<>1 then raise exception 'phone motion event did not create a dispatch request'; end if;
  update public.xbox_detection_events e set snapshot_url='xbox/test/frame.jpg' where e.id=mobile_flow.event_id;
  if not found then raise exception 'operator cannot attach evidence'; end if;
  claim := public.drone_claim_next((session->>'id')::uuid);
  if claim is null or (claim->>'event_id')::bigint<>event_id then raise exception 'controller did not claim phone event'; end if;
  perform public.drone_report_result((session->>'id')::uuid,(claim->>'id')::bigint,false,'simulated refusal');
  select count(*) into n from public.drone_dispatch_logs where request_id=(claim->>'id')::bigint;
  if n<>2 then raise exception 'claim and result were not logged'; end if;
  insert into public.xbox_detection_events(camera_id,session_id,event_type,meta)
    values ((camera->>'id')::uuid,'phone-session','test',jsonb_build_object('detected_at',clock_timestamp()))
    returning id into event_id;
  select count(*) into n from public.drone_dispatch_requests r where r.event_id=mobile_flow.event_id;
  if n<>0 then raise exception 'test event must not dispatch'; end if;
end $$;
rollback;
