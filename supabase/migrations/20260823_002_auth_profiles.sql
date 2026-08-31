begin;

do $$ begin
  create type public.app_role as enum ('member', 'staff', 'admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.staff_role as enum ('technical', 'marketing', 'general');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.membership_state as enum ('none', 'payment_pending', 'active', 'suspended', 'cancelled', 'expired');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  birthday date,
  locality text,
  interests text[] not null default '{}',
  profession text,
  industry text,
  avatar_url text,
  app_role public.app_role not null default 'member',
  staff_role public.staff_role,
  membership_state public.membership_state not null default 'none',
  member_number text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint staff_role_matches_app_role check (
    (app_role = 'staff' and staff_role is not null)
    or (app_role <> 'staff' and staff_role is null)
  )
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Backfill profiles for any users created before this migration.
insert into public.profiles (id, full_name)
select id, coalesce(raw_user_meta_data ->> 'full_name', '')
from auth.users
on conflict (id) do nothing;

alter table public.profiles enable row level security;
revoke all on table public.profiles from anon;
revoke all on table public.profiles from authenticated;
grant select on table public.profiles to authenticated;
grant update (full_name, phone, birthday, locality, interests, profession, industry, avatar_url)
  on table public.profiles to authenticated;

drop policy if exists "Users read own profile" on public.profiles;
create policy "Users read own profile" on public.profiles
  for select to authenticated using (id = auth.uid());

drop policy if exists "Users update own profile fields" on public.profiles;
create policy "Users update own profile fields" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

commit;
