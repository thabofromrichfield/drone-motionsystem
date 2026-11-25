-- The expiration window starts at detection, not at delayed upload.
create or replace function public.drone_queue_alert() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare detected timestamptz;
begin
  if not new.is_alert or new.camera_id is null or nullif(new.session_id,'') is null
     or new.event_type not in ('person','person+motion','motion')
     or length(coalesce(new.meta->>'detected_at','')) > 40 then return new; end if;
  begin
    detected := (new.meta->>'detected_at')::timestamptz;
  exception when invalid_datetime_format or datetime_field_overflow then
    return new;
  end;
  -- Old queued frames, invalid timestamps, and implausible future times never
  -- become dispatch requests. Duplicate deliveries have one request only.
  if detected is null or detected < now() - interval '20 seconds' or detected > now() + interval '5 seconds' then return new; end if;
  insert into public.drone_dispatch_requests(event_id,camera_id,camera_session,detected_at,event_type,expires_at)
    values (new.id,new.camera_id,new.session_id,detected,new.event_type,detected+interval '20 seconds')
    on conflict do nothing;
  return new;
end $$;
