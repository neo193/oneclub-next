begin;

create table if not exists public.membership_invitations (
  id uuid primary key default gen_random_uuid(),
  enquiry_id uuid references public.enquiries(id) on delete set null,
  email text not null,
  token_hash text not null unique,
  status text not null default 'active' check (status in ('active','used','revoked','expired')),
  expires_at timestamptz not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  used_at timestamptz,
  used_by uuid references auth.users(id)
);

create index if not exists membership_invitations_email_idx on public.membership_invitations (lower(email));
create index if not exists membership_invitations_status_expiry_idx on public.membership_invitations (status, expires_at);
alter table public.membership_invitations enable row level security;
revoke all on table public.membership_invitations from anon, authenticated;

create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  details jsonb not null default '{}',
  created_at timestamptz not null default now()
);
alter table public.audit_log enable row level security;
revoke all on table public.audit_log from anon, authenticated;

create or replace function public.is_staff_or_admin()
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.profiles where id = auth.uid() and app_role in ('staff','admin'));
$$;
revoke all on function public.is_staff_or_admin() from public;

create or replace function public.list_enquiries_for_staff()
returns table (id uuid, full_name text, email text, phone text, status public.enquiry_status, marketing_consent boolean, created_at timestamptz)
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_staff_or_admin() then raise exception 'Not authorised'; end if;
  return query select e.id,e.full_name,e.email,e.phone,e.status,e.marketing_consent,e.created_at
  from public.enquiries e order by e.created_at desc;
end;
$$;
revoke all on function public.list_enquiries_for_staff() from public;
grant execute on function public.list_enquiries_for_staff() to authenticated;

create or replace function public.approve_enquiry_and_create_invitation(p_enquiry_id uuid)
returns text language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_email text; v_token text := encode(gen_random_bytes(32),'hex'); v_invitation_id uuid;
begin
  if not public.is_staff_or_admin() then raise exception 'Not authorised'; end if;
  select lower(email) into v_email from public.enquiries where id=p_enquiry_id for update;
  if v_email is null then raise exception 'Enquiry not found'; end if;
  update public.membership_invitations set status='revoked'
    where lower(email)=v_email and status='active';
  insert into public.membership_invitations(enquiry_id,email,token_hash,expires_at,created_by)
    values(p_enquiry_id,v_email,encode(digest(v_token,'sha256'),'hex'),now()+interval '30 days',auth.uid())
    returning id into v_invitation_id;
  update public.enquiries set status='approved',reviewed_at=now(),reviewed_by=auth.uid(),updated_at=now()
    where id=p_enquiry_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'invitation.created','membership_invitation',v_invitation_id::text,jsonb_build_object('email',v_email,'expires_in_days',30));
  return v_token;
end;
$$;
revoke all on function public.approve_enquiry_and_create_invitation(uuid) from public;
grant execute on function public.approve_enquiry_and_create_invitation(uuid) to authenticated;

create or replace function public.validate_membership_invitation(p_token text)
returns table(email text, expires_at timestamptz, status text)
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  return query select i.email,i.expires_at,
    case when i.status='active' and i.expires_at<=now() then 'expired' else i.status end
  from public.membership_invitations i
  where i.token_hash=encode(digest(p_token,'sha256'),'hex') limit 1;
end;
$$;
revoke all on function public.validate_membership_invitation(text) from public;
grant execute on function public.validate_membership_invitation(text) to anon, authenticated;

create or replace function public.accept_membership_invitation(p_token text)
returns boolean language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_inv public.membership_invitations%rowtype; v_email text := lower(coalesce(auth.jwt()->>'email',''));
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  select * into v_inv from public.membership_invitations
    where token_hash=encode(digest(p_token,'sha256'),'hex') for update;
  if v_inv.id is null then raise exception 'Invitation not found'; end if;
  if v_inv.status<>'active' or v_inv.expires_at<=now() then raise exception 'Invitation is no longer active'; end if;
  if lower(v_inv.email)<>v_email then raise exception 'Invitation belongs to a different email address'; end if;
  update public.membership_invitations set status='used',used_at=now(),used_by=auth.uid() where id=v_inv.id;
  update public.profiles set membership_state='payment_pending',updated_at=now() where id=auth.uid() and membership_state='none';
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'invitation.accepted','membership_invitation',v_inv.id::text,jsonb_build_object('email',v_email));
  return true;
end;
$$;
revoke all on function public.accept_membership_invitation(text) from public;
grant execute on function public.accept_membership_invitation(text) to authenticated;

create sequence if not exists public.founding_member_number_seq start with 3;

create or replace function public.grant_complimentary_membership(p_email text)
returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare v_target uuid; v_number text;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role='admin') then raise exception 'Administrator required'; end if;
  select u.id into v_target from auth.users u where lower(u.email)=lower(trim(p_email));
  if v_target is null then raise exception 'User not found'; end if;
  select member_number into v_number from public.profiles where id=v_target for update;
  if v_number is null then v_number := 'OC-F-'||lpad(nextval('public.founding_member_number_seq')::text,6,'0'); end if;
  update public.profiles set membership_state='active',member_number=v_number,updated_at=now() where id=v_target;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'membership.complimentary_granted','profile',v_target::text,jsonb_build_object('email',lower(trim(p_email)),'member_number',v_number));
  return v_number;
end;
$$;
revoke all on function public.grant_complimentary_membership(text) from public;
grant execute on function public.grant_complimentary_membership(text) to authenticated;

commit;
