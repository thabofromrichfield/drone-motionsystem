-- Hardened adaptation of web/sql/schema.sql; requires 000_operators.sql.
create table public.xbox_cameras (
  id uuid primary key default gen_random_uuid(), label text not null, location text,
  kind text not null default 'mobile' check (kind in ('mobile','webcam','ip-cam','rtsp','bridge','other')),
  access_token text not null default replace(gen_random_uuid()::text,'-',''),
  armed boolean not null default true,
  sensitivity numeric(4,3) not null default 0.500 check (sensitivity between 0 and 1),
  motion_threshold numeric(5,3) not null default 0.012 check (motion_threshold between 0 and 1),
  cooldown_seconds integer not null default 20 check (cooldown_seconds between 0 and 3600),
  capture_snapshots boolean not null default true, max_fps integer not null default 8 check (max_fps between 1 and 60),
  status text not null default 'offline' check (status in ('online','offline','degraded')),
  engine text, fps_reported numeric(6,2), persons_last integer not null default 0,
  last_heartbeat_at timestamptz, last_event_at timestamptz, notes text,
  archived boolean not null default false, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.xbox_detection_events (
  id bigint generated always as identity primary key, camera_id uuid references public.xbox_cameras(id) on delete set null,
  camera_label text, session_id text,
  event_type text not null check (event_type in ('person','person+motion','motion','presence-gone','info','test')),
  severity text not null default 'info' check (severity in ('person','motion','clear','info')),
  person_count integer not null default 0, confidence numeric(4,3), motion_score numeric(6,4),
  bbox jsonb, skeleton jsonb, snapshot_url text, engine text, fps numeric(6,2), device text,
  is_alert boolean not null default false, acknowledged_at timestamptz, acknowledged_by text,
  meta jsonb, created_at timestamptz not null default now()
);
create index xbox_events_camera_time_idx on public.xbox_detection_events(camera_id, created_at desc);
create index xbox_events_time_idx on public.xbox_detection_events(created_at desc);
create index xbox_events_alerts_idx on public.xbox_detection_events(created_at desc) where is_alert;
create index xbox_cameras_hb_idx on public.xbox_cameras(last_heartbeat_at desc);

create function public.xbox_event_before_insert() returns trigger language plpgsql as $$
declare c record;
begin
  if new.skeleton is null then new.skeleton := '[]'::jsonb; end if;
  select armed, label into c from public.xbox_cameras where id = new.camera_id and archived = false;
  if new.camera_label is null then new.camera_label := c.label; end if;
  new.severity := case when new.event_type in ('person','person+motion') then 'person' when new.event_type = 'motion' then 'motion' when new.event_type = 'presence-gone' then 'clear' else 'info' end;
  new.is_alert := new.event_type in ('person','person+motion','motion') and coalesce(c.armed, false);
  return new;
end $$;
create trigger xbox_event_before_insert before insert on public.xbox_detection_events for each row execute function public.xbox_event_before_insert();
create function public.xbox_event_after_insert() returns trigger language plpgsql as $$
begin
  update public.xbox_cameras set last_event_at = new.created_at,
    persons_last = case when new.event_type in ('presence-gone','info','test') then persons_last else new.person_count end
    where id = new.camera_id;
  return new;
end $$;
create trigger xbox_event_after_insert after insert on public.xbox_detection_events for each row execute function public.xbox_event_after_insert();
create function public.xbox_touch_updated_at() returns trigger language plpgsql as $$ begin new.updated_at := now(); return new; end $$;
create trigger xbox_cameras_touch before update on public.xbox_cameras for each row execute function public.xbox_touch_updated_at();

create function public.xbox_register_camera(p_label text, p_kind text default 'mobile', p_location text default null, p_notes text default null)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare c public.xbox_cameras; was_created boolean := false;
begin
  select * into c from public.xbox_cameras where label = p_label and archived = false order by created_at asc limit 1;
  if c.id is null then
    insert into public.xbox_cameras(label,kind,location,notes) values (p_label,coalesce(nullif(p_kind,''),'mobile'),p_location,p_notes) returning * into c;
    was_created := true;
  end if;
  return jsonb_build_object('id',c.id,'label',c.label,'access_token',c.access_token,'created',was_created,'armed',c.armed,'sensitivity',c.sensitivity,'motion_threshold',c.motion_threshold,'cooldown_seconds',c.cooldown_seconds,'capture_snapshots',c.capture_snapshots,'max_fps',c.max_fps);
end $$;
create function public.xbox_heartbeat(p_camera_id uuid, p_status text default 'online', p_engine text default null, p_fps numeric default null, p_persons integer default null)
returns void language sql security invoker set search_path = public as $$
  update public.xbox_cameras set last_heartbeat_at = now(), status = case when p_status in ('online','offline','degraded') then p_status else status end,
    engine = coalesce(nullif(p_engine,''),engine), fps_reported = coalesce(p_fps,fps_reported),
    persons_last = case when p_persons is null then persons_last when last_heartbeat_at is null or now()-last_heartbeat_at > interval '25 seconds' then p_persons else persons_last end
  where id = p_camera_id and archived = false;
$$;
create function public.xbox_mark_ack(p_ids bigint[], p_by text default 'control-center') returns integer language sql security invoker set search_path = public as $$
  with u as (update public.xbox_detection_events set acknowledged_at = now(), acknowledged_by = p_by where id = any(coalesce(p_ids,'{}')::bigint[]) and acknowledged_at is null returning id) select count(*)::integer from u;
$$;
create function public.xbox_purge_events(p_keep_days integer default 14) returns integer language sql security invoker set search_path = public as $$
  with d as (delete from public.xbox_detection_events where created_at < now()-make_interval(days => greatest(coalesce(p_keep_days,14),1)) returning 1) select count(*)::integer from d;
$$;
create function public.xbox_sweep_stale() returns integer language sql security invoker set search_path = public as $$
  with u as (update public.xbox_cameras set status = 'offline' where archived = false and status <> 'offline' and (last_heartbeat_at is null or last_heartbeat_at < now()-interval '30 seconds') returning 1) select count(*)::integer from u;
$$;
create function public.xbox_housekeeping() returns void language plpgsql security invoker set search_path = public as $$
begin perform public.xbox_sweep_stale(); perform public.xbox_purge_events(30); end $$;

alter table public.xbox_cameras enable row level security;
alter table public.xbox_detection_events enable row level security;
create policy "operators cameras" on public.xbox_cameras for all to authenticated using (public.drone_is_operator()) with check (public.drone_is_operator());
create policy "operators events" on public.xbox_detection_events for all to authenticated using (public.drone_is_operator()) with check (public.drone_is_operator());
grant select,insert,update,delete on public.xbox_cameras,public.xbox_detection_events to authenticated;
grant usage,select on sequence public.xbox_detection_events_id_seq to authenticated;
revoke all on function public.xbox_register_camera(text,text,text,text), public.xbox_heartbeat(uuid,text,text,numeric,integer), public.xbox_mark_ack(bigint[],text), public.xbox_purge_events(integer), public.xbox_sweep_stale(), public.xbox_housekeeping() from public,anon;
grant execute on function public.xbox_register_camera(text,text,text,text), public.xbox_heartbeat(uuid,text,text,numeric,integer), public.xbox_mark_ack(bigint[],text), public.xbox_purge_events(integer), public.xbox_sweep_stale(), public.xbox_housekeeping() to authenticated;
alter publication supabase_realtime add table public.xbox_detection_events;
alter publication supabase_realtime add table public.xbox_cameras;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values ('xbox-snapshots','xbox-snapshots',false,4194304,array['image/jpeg','image/png']);
create policy "operators snapshots" on storage.objects for all to authenticated using (bucket_id = 'xbox-snapshots' and public.drone_is_operator()) with check (bucket_id = 'xbox-snapshots' and public.drone_is_operator());
