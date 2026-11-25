-- A verified email must also be explicitly invited before it can operate the
-- system. Invites are managed by a database administrator, never the browser.
create table public.drone_operator_invites (
  email text primary key check (email = lower(email))
);
alter table public.drone_operator_invites enable row level security;
revoke all on public.drone_operator_invites from public, anon, authenticated;

create function public.drone_provision_verified_operator() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.email_confirmed_at is not null and exists (
    select 1 from public.drone_operator_invites where email = lower(new.email)
  ) then
    insert into public.drone_operators(user_id) values (new.id) on conflict do nothing;
  end if;
  return new;
end $$;
revoke all on function public.drone_provision_verified_operator() from public, anon, authenticated;
create trigger drone_provision_verified_operator after insert or update of email_confirmed_at on auth.users
for each row execute function public.drone_provision_verified_operator();
