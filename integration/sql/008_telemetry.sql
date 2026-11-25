-- Flight telemetry is operator-only and is written through a bounded RPC.
create table public.drone_telemetry (
  id bigint generated always as identity primary key,
  controller_session uuid not null references public.drone_controller_sessions(id),
  data jsonb not null check (jsonb_typeof(data) = 'object' and pg_column_size(data) <= 4096),
  created_at timestamptz not null default now()
);
create index drone_telemetry_session_time on public.drone_telemetry(controller_session, created_at desc);
alter table public.drone_telemetry enable row level security;
revoke all on public.drone_telemetry from public, anon, authenticated;
grant select on public.drone_telemetry to authenticated;
create policy "operators read drone telemetry" on public.drone_telemetry for select to authenticated using (public.drone_is_operator());

create function public.drone_report_telemetry(p_session uuid,p_data jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.drone_is_operator() then raise exception 'operator access required' using errcode='42501'; end if;
  if not exists (select 1 from public.drone_controller_sessions where id=p_session and operator_id=auth.uid() and armed_at > now()-interval '30 minutes') then
    raise exception 'controller session unavailable';
  end if;
  if jsonb_typeof(p_data) <> 'object' or pg_column_size(p_data) > 4096 then raise exception 'invalid telemetry'; end if;
  insert into public.drone_telemetry(controller_session,data) values (p_session,p_data);
end $$;
revoke all on function public.drone_report_telemetry(uuid,jsonb) from public,anon;
grant execute on function public.drone_report_telemetry(uuid,jsonb) to authenticated;
