-- Controller leases are explicit, short lived and tied to the signed-in operator.
-- Claiming is at-most-once: a lost response is never retried as a new takeoff.
alter table public.drone_dispatch_requests drop constraint drone_dispatch_requests_status_check;
alter table public.drone_dispatch_requests add column controller_session uuid;
alter table public.drone_dispatch_requests add column claimed_at timestamptz;
alter table public.drone_dispatch_requests add constraint drone_dispatch_requests_status_check check (status in ('queued','claimed','sdk_accepted','failed'));

create table public.drone_controller_sessions (
  id uuid primary key default gen_random_uuid(),
  operator_id uuid not null references auth.users(id),
  armed_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '10 minutes',
  last_seen_at timestamptz not null default now(),
  ended_at timestamptz
);
alter table public.drone_controller_sessions enable row level security;
revoke all on public.drone_controller_sessions from public, anon, authenticated;
grant select on public.drone_controller_sessions to authenticated;
create policy "operators read controller" on public.drone_controller_sessions for select to authenticated using (public.drone_is_operator());

create table public.drone_dispatch_logs (
  id bigint generated always as identity primary key,
  request_id bigint not null references public.drone_dispatch_requests(id) on delete cascade,
  controller_session uuid not null references public.drone_controller_sessions(id),
  state text not null check (state in ('claimed','sdk_accepted','failed')),
  detail text,
  created_at timestamptz not null default now()
);
alter table public.drone_dispatch_logs enable row level security;
revoke all on public.drone_dispatch_logs from public, anon, authenticated;
grant select on public.drone_dispatch_logs to authenticated;
create policy "operators read dispatch logs" on public.drone_dispatch_logs for select to authenticated using (public.drone_is_operator());

create function public.drone_arm_controller() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.drone_controller_sessions;
begin
  if not public.drone_is_operator() then raise exception 'operator access required' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtext('drone_controller_single_lease'));
  update public.drone_controller_sessions set ended_at=now() where ended_at is null and expires_at <= now();
  if exists (select 1 from public.drone_controller_sessions where ended_at is null) then raise exception 'another controller is armed'; end if;
  insert into public.drone_controller_sessions(operator_id) values (auth.uid()) returning * into s;
  return jsonb_build_object('id',s.id,'armed_at',s.armed_at,'expires_at',s.expires_at);
end $$;

create function public.drone_claim_next(p_session uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.drone_controller_sessions; r public.drone_dispatch_requests;
begin
  if not public.drone_is_operator() then raise exception 'operator access required' using errcode='42501'; end if;
  select * into s from public.drone_controller_sessions where id=p_session and operator_id=auth.uid() and ended_at is null and expires_at > now() for update;
  if s.id is null then raise exception 'controller session is not active'; end if;
  update public.drone_controller_sessions set last_seen_at=now() where id=s.id;
  select * into r from public.drone_dispatch_requests where status='queued' and expires_at > now() and requested_at >= s.armed_at order by id for update skip locked limit 1;
  if r.id is null then return null; end if;
  update public.drone_dispatch_requests set status='claimed', controller_session=s.id, claimed_at=now() where id=r.id;
  insert into public.drone_dispatch_logs(request_id,controller_session,state) values (r.id,s.id,'claimed');
  -- One alert per arming. End the session immediately to prevent another claim.
  update public.drone_controller_sessions set ended_at=now() where id=s.id;
  return jsonb_build_object('id',r.id,'event_id',r.event_id,'event_type',r.event_type,'detected_at',r.detected_at,'expires_at',r.expires_at);
end $$;

create function public.drone_report_result(p_session uuid,p_request bigint,p_success boolean,p_detail text default null) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare next_state text := case when p_success then 'sdk_accepted' else 'failed' end;
begin
  if not public.drone_is_operator() then raise exception 'operator access required' using errcode='42501'; end if;
  update public.drone_dispatch_requests r set status=next_state
  where r.id=p_request and r.controller_session=p_session and r.status='claimed'
    and exists(select 1 from public.drone_controller_sessions s where s.id=p_session and s.operator_id=auth.uid());
  if not found then raise exception 'claim not found or already completed'; end if;
  insert into public.drone_dispatch_logs(request_id,controller_session,state,detail) values (p_request,p_session,next_state,left(p_detail,500));
end $$;

create function public.drone_disarm_controller(p_session uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.drone_is_operator() then raise exception 'operator access required' using errcode='42501'; end if;
  update public.drone_controller_sessions set ended_at=now() where id=p_session and operator_id=auth.uid() and ended_at is null;
end $$;

revoke all on function public.drone_arm_controller(),public.drone_claim_next(uuid),public.drone_report_result(uuid,bigint,boolean,text),public.drone_disarm_controller(uuid) from public,anon;
grant execute on function public.drone_arm_controller(),public.drone_claim_next(uuid),public.drone_report_result(uuid,bigint,boolean,text),public.drone_disarm_controller(uuid) to authenticated;
