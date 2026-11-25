-- Return remaining lifetime using server time; the phone subtracts its entire
-- measured round trip, so phone wall-clock skew cannot extend a request.
create or replace function public.drone_claim_next(p_session uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.drone_controller_sessions; r public.drone_dispatch_requests;
begin
  if not public.drone_is_operator() then raise exception 'operator access required' using errcode='42501'; end if;
  select * into s from public.drone_controller_sessions where id=p_session and operator_id=auth.uid() and ended_at is null and expires_at > now() for update;
  if s.id is null then raise exception 'controller session is not active'; end if;
  update public.drone_controller_sessions set last_seen_at=now() where id=s.id;
  select * into r from public.drone_dispatch_requests where status='queued' and expires_at > clock_timestamp() and requested_at >= s.armed_at order by id for update skip locked limit 1;
  if r.id is null then return null; end if;
  update public.drone_dispatch_requests set status='claimed', controller_session=s.id, claimed_at=now() where id=r.id;
  insert into public.drone_dispatch_logs(request_id,controller_session,state) values (r.id,s.id,'claimed');
  update public.drone_controller_sessions set ended_at=now() where id=s.id;
  return jsonb_build_object('id',r.id,'event_id',r.event_id,'event_type',r.event_type,'detected_at',r.detected_at,'expires_at',r.expires_at,'remaining_ms',greatest(0, floor(extract(epoch from (r.expires_at-clock_timestamp()))*1000)::integer));
end $$;
