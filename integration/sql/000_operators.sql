-- Fresh-project migration. The operator allowlist starts empty; provision an
-- operator by adding their auth.users.id from the Supabase SQL editor.
create table public.drone_operators (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.drone_operators enable row level security;
revoke all on public.drone_operators from public, anon, authenticated;

create function public.drone_is_operator() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.drone_operators where user_id = auth.uid());
$$;
revoke all on function public.drone_is_operator() from public, anon;
grant execute on function public.drone_is_operator() to authenticated;
