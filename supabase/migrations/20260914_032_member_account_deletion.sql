begin;

alter table public.profiles add column if not exists deleted_at timestamptz;
alter table public.profiles add column if not exists deletion_reference uuid;

-- A profile is the durable owner of financial and booking history. Authentication may
-- be removed while the anonymized profile remains as the historical subject.
alter table public.profiles drop constraint if exists profiles_id_fkey;
create unique index if not exists profiles_deletion_reference_idx
  on public.profiles(deletion_reference) where deletion_reference is not null;

create table if not exists public.account_deletion_support_contexts (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.profiles(id) on delete cascade,
  expires_at timestamptz not null default now() + interval '24 hours',
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists account_deletion_support_member_idx
  on public.account_deletion_support_contexts(member_id,expires_at desc);
alter table public.account_deletion_support_contexts enable row level security;
revoke all on table public.account_deletion_support_contexts from public,anon,authenticated;

-- The hidden category is accepted only by the guarded RPC below. Replace the
-- prototype category check without depending on its original generated name.
do $$ declare v_constraint record;begin
  for v_constraint in select conname from pg_constraint
    where conrelid='public.member_support_requests'::regclass and contype='c'
      and pg_get_constraintdef(oid) ilike '%category%'
  loop execute format('alter table public.member_support_requests drop constraint %I',v_constraint.conname);end loop;
end$$;
alter table public.member_support_requests alter column category drop default;
alter table public.member_support_requests alter column category type text using category::text;
alter table public.member_support_requests add constraint member_support_requests_category_check
  check(category::text in ('membership_access','payment','event_booking','reservation_change','profile','other','account_deletion'));

create or replace function public.get_account_deletion_eligibility()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_member uuid:=auth.uid();v_events int:=0;v_properties int:=0;v_legacy int:=0;v_refunds int:=0;v_context uuid;
begin
  if v_member is null or not exists(select 1 from public.profiles where id=v_member and app_role::text='member' and deleted_at is null) then
    raise exception 'Active member account required';
  end if;
  select count(*) into v_events from public.event_bookings b join public.events e on e.id=b.event_id
    where b.member_id=v_member and e.starts_at>now() and (b.status::text='confirmed' or (b.status::text='pending_payment' and b.reservation_expires_at>now()));
  if to_regclass('public.partner_itineraries') is not null then
    select count(*) into v_properties from public.partner_itineraries
      where member_id=v_member and status not in ('declined','cancelled','completed');
  end if;
  if to_regclass('oneclub_legacy.partner_reservations') is not null then
    execute 'select count(*) from oneclub_legacy.partner_reservations where member_id=$1 and status::text not in (''declined'',''cancelled'',''completed'')'
      into v_legacy using v_member;
  end if;
  select count(distinct b.id) into v_refunds from public.event_bookings b
    left join public.refund_requests r on r.booking_id=b.id
    where b.member_id=v_member and (b.payment_status::text='refund_pending' or r.status in ('requested','processing','failed'));
  if v_events+v_properties+v_legacy=0 and v_refunds>0 then
    delete from public.account_deletion_support_contexts where member_id=v_member and (consumed_at is not null or expires_at<=now());
    insert into public.account_deletion_support_contexts(member_id) values(v_member) returning id into v_context;
  end if;
  return jsonb_build_object('allowed',v_events+v_properties+v_legacy+v_refunds=0,
    'block_reason',case when v_events+v_properties+v_legacy>0 then 'upcoming_bookings' when v_refunds>0 then 'pending_refunds' else null end,
    'upcoming_event_bookings',v_events,'upcoming_property_bookings',v_properties+v_legacy,
    'pending_refunds',v_refunds,'support_context',v_context);
end;$$;

create or replace function public.validate_account_deletion_support_context(p_context uuid)
returns boolean language sql security definer set search_path=public,pg_temp as $$
  select exists(select 1 from public.account_deletion_support_contexts
    where id=p_context and member_id=auth.uid() and consumed_at is null and expires_at>now());
$$;

create or replace function public.consume_account_deletion_support_context(p_context uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  update public.account_deletion_support_contexts set consumed_at=now()
    where id=p_context and member_id=auth.uid() and consumed_at is null and expires_at>now();
  if not found then raise exception 'Account deletion support request is no longer valid';end if;
end;$$;

create or replace function public.submit_account_deletion_support_request(p_context uuid,p_message text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
  if char_length(trim(coalesce(p_message,''))) not between 10 and 2000 then raise exception 'Message must be between 10 and 2000 characters';end if;
  update public.account_deletion_support_contexts set consumed_at=now()
    where id=p_context and member_id=auth.uid() and consumed_at is null and expires_at>now();
  if not found then raise exception 'Account deletion support request is no longer valid';end if;
  insert into public.member_support_requests(user_id,category,message)
    values(auth.uid(),'account_deletion',trim(p_message)) returning id into v_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'member.account_deletion_support_requested','support_request',v_id::text,jsonb_build_object('context',p_context));
  return v_id;
end;$$;

create or replace function public.finalize_member_account_anonymization(p_member_id uuid,p_original_email text)
returns jsonb language plpgsql security definer set search_path=public,auth,oneclub_legacy,pg_temp as $$
declare v_ref uuid:=gen_random_uuid();v_tombstone text;v_legacy_active boolean:=false;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Service role required';end if;
  if not exists(select 1 from public.profiles where id=p_member_id and app_role::text='member') then raise exception 'Member account not found';end if;

  -- Re-check every blocker inside the mutation transaction using the supplied member id.
  if exists(select 1 from public.event_bookings b join public.events e on e.id=b.event_id where b.member_id=p_member_id and e.starts_at>now() and (b.status::text='confirmed' or (b.status::text='pending_payment' and b.reservation_expires_at>now()))) then raise exception 'Upcoming event bookings must be resolved first';end if;
  if exists(select 1 from public.partner_itineraries where member_id=p_member_id and status not in ('declined','cancelled','completed')) then raise exception 'Upcoming property bookings must be resolved first';end if;
  if to_regclass('oneclub_legacy.partner_reservations') is not null then
    execute 'select exists(select 1 from oneclub_legacy.partner_reservations where member_id=$1 and status::text not in (''declined'',''cancelled'',''completed''))' into v_legacy_active using p_member_id;
    if v_legacy_active then raise exception 'Upcoming legacy property bookings must be resolved first';end if;
  end if;
  if exists(select 1 from public.event_bookings b left join public.refund_requests r on r.booking_id=b.id where b.member_id=p_member_id and (b.payment_status::text='refund_pending' or r.status in ('requested','processing','failed'))) then raise exception 'Pending refunds must be resolved first';end if;

  v_tombstone:='removed+'||replace(p_member_id::text,'-','')||'@deleted.invalid';
  update public.booking_guests g set guest_name='Removed guest' from public.event_bookings b where g.booking_id=b.id and b.member_id=p_member_id;
  update public.event_bookings set guest_name=null where member_id=p_member_id;
  update public.member_admin_notes set note='Account record removed by member request.' where member_id=p_member_id;
  update public.member_support_requests set message='Content removed following account deletion.' where user_id=p_member_id;
  update public.partner_itineraries set contact_phone='Removed' where member_id=p_member_id;
  update public.partner_itinerary_stops s set special_requests=null,member_message=null
    from public.partner_itineraries i where s.itinerary_id=i.id and i.member_id=p_member_id;
  update public.reservation_notifications n set recipient_address=case when audience='member' then null else recipient_address end,
    payload=payload-'member_name'-'member_email'-'contact_phone'-'special_requests'-'member_message'
    from public.partner_itineraries i where n.itinerary_id=i.id and i.member_id=p_member_id;
  update public.membership_invitations set created_by=null where created_by=p_member_id;
  update public.membership_invitations set used_by=null where used_by=p_member_id;
  update public.membership_invitations set email=v_tombstone,expires_at=least(expires_at,now()) where lower(email)=lower(trim(p_original_email));
  update public.enquiries set full_name='Removed user',email=v_tombstone,phone='00000000',marketing_consent=false,internal_notes=null,status='archived',updated_at=now()
    where lower(email)=lower(trim(p_original_email));
  delete from public.account_deletion_support_contexts where member_id=p_member_id;
  update public.profiles set full_name='Removed user',phone=null,birthday=null,locality=null,interests='{}',profession=null,industry=null,avatar_url=null,
    membership_state='cancelled',member_number=null,founding_member_sequence=null,membership_plan=null,membership_started_at=null,membership_expires_at=null,
    pending_membership_plan=null,pending_membership_source=null,membership_status_context=null,payment_offer_expires_at=null,
    deleted_at=now(),deletion_reference=v_ref,updated_at=now() where id=p_member_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
    values(null,'member.account_deleted','member',p_member_id::text,jsonb_build_object('deletion_reference',v_ref));
  delete from auth.users where id=p_member_id;
  if not found then raise exception 'Authentication account was not removed';end if;
  return jsonb_build_object('deletion_reference',v_ref,'tombstone_email',v_tombstone);
end;$$;

drop policy if exists "Users read own profile" on public.profiles;
create policy "Users read own profile" on public.profiles for select to authenticated using(id=auth.uid() and deleted_at is null);
drop policy if exists "Users update own profile fields" on public.profiles;
create policy "Users update own profile fields" on public.profiles for update to authenticated using(id=auth.uid() and deleted_at is null) with check(id=auth.uid() and deleted_at is null);

revoke all on function public.get_account_deletion_eligibility(),public.validate_account_deletion_support_context(uuid),public.consume_account_deletion_support_context(uuid),public.submit_account_deletion_support_request(uuid,text),public.finalize_member_account_anonymization(uuid,text) from public,anon;
grant execute on function public.get_account_deletion_eligibility(),public.validate_account_deletion_support_context(uuid),public.consume_account_deletion_support_context(uuid),public.submit_account_deletion_support_request(uuid,text) to authenticated;
grant execute on function public.finalize_member_account_anonymization(uuid,text) to service_role;

commit;
