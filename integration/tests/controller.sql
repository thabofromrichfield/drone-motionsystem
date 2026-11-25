-- Run after migrations on a disposable/test database; no fixtures persist.
begin;
do $$
declare u uuid := gen_random_uuid(); outsider uuid := gen_random_uuid(); n integer; s jsonb; q jsonb; c uuid;
begin
  insert into public.drone_operator_invites(email) values ('fixture@example.invalid');
  insert into auth.users(id,email) values (u,'fixture@example.invalid'),(outsider,'outsider@example.invalid');
  update auth.users set email_confirmed_at=now() where id=outsider;
  select count(*) into n from public.drone_operators where user_id in (u,outsider);
  if n<>0 then raise exception 'unconfirmed or uninvited user provisioned'; end if;
  update auth.users set email_confirmed_at=now() where id=u;
  select count(*) into n from public.drone_operators where user_id=u;
  if n<>1 then raise exception 'verified invited user not provisioned'; end if;
  perform set_config('request.jwt.claim.sub',u::text,true);
  insert into public.xbox_cameras(label) values ('controller-test') returning id into c;
  s:=public.drone_arm_controller();
  -- A delayed upload must not turn an alert from before arming into a takeoff.
  insert into public.xbox_detection_events(camera_id,session_id,event_type,meta)
    values (c,'test','motion',jsonb_build_object('detected_at',clock_timestamp()-interval '5 seconds'));
  q:=public.drone_claim_next((s->>'id')::uuid);
  if q is not null then raise exception 'pre-arm detection was claimed'; end if;
  insert into public.xbox_detection_events(camera_id,session_id,event_type,meta)
    values (c,'test','motion',jsonb_build_object('detected_at',clock_timestamp()));
  q:=public.drone_claim_next((s->>'id')::uuid);
  if q is null or (q->>'remaining_ms')::integer<=0 then raise exception 'fresh claim failed'; end if;
  perform public.drone_report_result((s->>'id')::uuid,(q->>'id')::bigint,true,'SDK accepted');
  perform public.drone_report_telemetry((s->>'id')::uuid,'{"is_flying":true}'::jsonb);
  select count(*) into n from public.drone_dispatch_logs where request_id=(q->>'id')::bigint;
  if n<>2 then raise exception 'audit records missing'; end if;
  select count(*) into n from public.drone_telemetry where controller_session=(s->>'id')::uuid;
  if n<>1 then raise exception 'telemetry missing'; end if;
  begin
    perform public.drone_claim_next((s->>'id')::uuid);
    raise exception 'second claim accepted';
  exception when raise_exception then
    if sqlerrm='second claim accepted' then raise; end if;
  end;
end $$;
rollback;
