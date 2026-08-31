begin;

create extension if not exists pgcrypto;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'enquiry_status') then
    create type public.enquiry_status as enum ('new', 'contacted', 'approved', 'rejected', 'archived');
  end if;
end $$;

create table if not exists public.enquiries (
  id uuid primary key default gen_random_uuid(),
  full_name text not null check (char_length(full_name) between 2 and 120),
  email text not null check (char_length(email) between 5 and 254),
  phone text not null check (char_length(phone) between 8 and 18),
  status public.enquiry_status not null default 'new',
  source text not null default 'website',
  terms_accepted_at timestamptz not null,
  marketing_consent boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  internal_notes text
);

create index if not exists enquiries_status_created_idx
  on public.enquiries (status, created_at desc);

create index if not exists enquiries_email_idx
  on public.enquiries (lower(email));

alter table public.enquiries enable row level security;

revoke all on table public.enquiries from anon, authenticated;

create or replace function public.submit_enquiry(
  p_full_name text,
  p_email text,
  p_phone text,
  p_terms_accepted boolean,
  p_marketing_consent boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_name text := trim(p_full_name);
  v_email text := lower(trim(p_email));
  v_phone text := regexp_replace(trim(p_phone), '[^0-9+]', '', 'g');
begin
  if not p_terms_accepted then
    raise exception 'Terms must be accepted';
  end if;

  if char_length(v_name) < 2 or char_length(v_name) > 120 then
    raise exception 'Invalid name';
  end if;

  if v_email !~* '^[A-Z0-9._%+''-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' then
    raise exception 'Invalid email';
  end if;

  if char_length(v_phone) < 8 or char_length(v_phone) > 18 then
    raise exception 'Invalid phone';
  end if;

  -- Prevent accidental rapid duplicates without exposing existing records.
  if exists (
    select 1 from public.enquiries
    where lower(email) = v_email
      and created_at > now() - interval '5 minutes'
  ) then
    raise exception 'An enquiry for this email was recently submitted';
  end if;

  insert into public.enquiries (
    full_name, email, phone, terms_accepted_at, marketing_consent
  ) values (
    v_name, v_email, v_phone, now(), coalesce(p_marketing_consent, false)
  ) returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.submit_enquiry(text, text, text, boolean, boolean) from public;
grant execute on function public.submit_enquiry(text, text, text, boolean, boolean) to anon, authenticated;

comment on function public.submit_enquiry(text, text, text, boolean, boolean)
  is 'Validated public enquiry submission. Does not expose enquiry records.';

commit;
