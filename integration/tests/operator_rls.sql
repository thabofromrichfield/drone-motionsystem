-- Run after migrations on a disposable/test database; no fixtures persist.
begin;
create temp table test_ids (operator_id uuid, outsider_id uuid, camera_id uuid);
grant select on test_ids to authenticated;
insert into test_ids values (gen_random_uuid(),gen_random_uuid(),gen_random_uuid());
insert into auth.users(id,email,email_confirmed_at)
  select operator_id,'rls-operator@example.invalid',now() from test_ids
  union all select outsider_id,'rls-outsider@example.invalid',now() from test_ids;
insert into public.drone_operators(user_id) select operator_id from test_ids;
insert into public.xbox_cameras(id,label) select camera_id,'RLS test' from test_ids;
set local role authenticated;
select set_config('request.jwt.claim.sub',(select operator_id::text from test_ids),true);
do $$ declare n integer; begin
  select count(*) into n from public.xbox_cameras where id=(select camera_id from test_ids);
  if n<>1 then raise exception 'operator cannot read camera'; end if;
end $$;
select set_config('request.jwt.claim.sub',(select outsider_id::text from test_ids),true);
do $$ declare n integer; begin
  select count(*) into n from public.xbox_cameras where id=(select camera_id from test_ids);
  if n<>0 then raise exception 'uninvited user can read camera'; end if;
  begin
    insert into public.xbox_cameras(label) values ('unauthorized');
    raise exception 'uninvited user can write camera';
  exception when insufficient_privilege then null; end;
end $$;
rollback;
