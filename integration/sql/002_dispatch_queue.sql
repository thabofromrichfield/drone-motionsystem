-- An alert creates an expiring request, never a flight command. The consumer
-- and aircraft safety checks are intentionally not enabled by this migration.
create table public.drone_dispatch_requests (
  id bigint generated always as identity primary key,
  event_id bigint not null unique references public.xbox_detection_events(id) on delete cascade,
  camera_id uuid not null references public.xbox_cameras(id),
  camera_session text not null,
  detected_at timestamptz not null,
  event_type text not null,
  requested_at timestamptz not null default now(),
  expires_at timestamptz not null,
  status text not null default 'queued' check (status in ('queued')),
  unique(camera_id, camera_session, detected_at, event_type)
);
alter table public.drone_dispatch_requests enable row level security;
create policy "operators read dispatch requests" on public.drone_dispatch_requests for select to authenticated using (public.drone_is_operator());
revoke all on public.drone_dispatch_requests from public, anon, authenticated;
grant select on public.drone_dispatch_requests to authenticated;

create function public.drone_queue_alert() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
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
    values (new.id,new.camera_id,new.session_id,detected,new.event_type,now()+interval '20 seconds')
    on conflict do nothing;
  return new;
end $$;
revoke all on function public.drone_queue_alert() from public, anon, authenticated;
create trigger drone_queue_alert after insert on public.xbox_detection_events for each row execute function public.drone_queue_alert();
