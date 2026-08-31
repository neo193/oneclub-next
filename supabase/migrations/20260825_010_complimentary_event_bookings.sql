begin;

alter table public.event_bookings
  add column if not exists booking_source text not null default 'member_payment';

alter table public.event_bookings drop constraint if exists event_bookings_booking_source_check;
alter table public.event_bookings add constraint event_bookings_booking_source_check
  check (booking_source in ('member_payment','complimentary'));

alter table public.event_bookings drop constraint if exists event_bookings_payment_status_check;
alter table public.event_bookings add constraint event_bookings_payment_status_check
  check (payment_status in ('unpaid','paid','refund_pending','refunded','not_required'));

create or replace function public.grant_complimentary_event_booking(
  p_event_id uuid,
  p_email text,
  p_guest_names text[] default '{}'::text[],
  p_reason text default null
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_event public.events;
  v_member_id uuid;
  v_guests text[];
  v_seats integer;
  v_taken integer;
  v_id uuid;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then
    raise exception 'Administrator permission required';
  end if;
  if nullif(trim(p_reason),'') is null or char_length(trim(p_reason))<3 then
    raise exception 'Enter an internal reason for the complimentary booking';
  end if;
  if char_length(trim(p_reason))>500 then raise exception 'Reason must be 500 characters or fewer'; end if;

  select u.id into v_member_id
  from auth.users u join public.profiles p on p.id=u.id
  where lower(u.email)=lower(trim(p_email)) and p.app_role::text='member' and p.membership_state::text='active';
  if not found then raise exception 'No active member account was found for that email'; end if;

  if cardinality(coalesce(p_guest_names,'{}'::text[]))>20 then raise exception 'Too many guests supplied'; end if;
  select coalesce(array_agg(trim(value) order by position),'{}'::text[]) into v_guests
  from unnest(coalesce(p_guest_names,'{}'::text[])) with ordinality as supplied(value,position)
  where nullif(trim(value),'') is not null;
  if cardinality(v_guests)<>cardinality(coalesce(p_guest_names,'{}'::text[])) then raise exception 'Every guest must have a name'; end if;
  if exists(select 1 from unnest(v_guests) as supplied_guest(name) where char_length(name)>100) then
    raise exception 'Guest names must be 100 characters or fewer';
  end if;

  select * into v_event from public.events
  where id=p_event_id and status='published' and starts_at>now() for update;
  if not found then raise exception 'Select an upcoming published event'; end if;
  if cardinality(v_guests)>v_event.max_guests_per_member then
    raise exception 'This event permits a maximum of % guests per member',v_event.max_guests_per_member;
  end if;
  if exists(select 1 from public.event_bookings where event_id=p_event_id and member_id=v_member_id and status in ('pending_payment','confirmed')) then
    raise exception 'This member already has an active booking for the event';
  end if;

  v_seats:=1+cardinality(v_guests);
  select coalesce(sum(seats),0)::integer into v_taken from public.event_bookings
  where event_id=p_event_id and (status='confirmed' or (status='pending_payment' and reservation_expires_at>now()));
  if v_event.capacity-v_taken<v_seats then raise exception 'Not enough places available'; end if;

  insert into public.event_bookings(
    event_id,member_id,guest_name,seats,amount_paise,status,payment_status,
    reservation_expires_at,booking_source
  ) values (
    p_event_id,v_member_id,v_guests[1],v_seats,0,'confirmed','not_required',null,'complimentary'
  ) returning id into v_id;

  insert into public.booking_guests(booking_id,guest_name,position)
  select v_id,name,position::integer from unnest(v_guests) with ordinality as guest(name,position);

  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'event.complimentary_booking_granted','event_booking',v_id::text,jsonb_build_object(
    'event_id',p_event_id,'member_id',v_member_id,'member_email',lower(trim(p_email)),
    'seats',v_seats,'guest_names',to_jsonb(v_guests),'reason',trim(p_reason)
  ));
  return v_id;
exception when unique_violation then raise exception 'This member already has a booking for the event';
end; $$;

drop function if exists public.get_my_event_bookings();
create function public.get_my_event_bookings()
returns table(
  booking_id uuid,event_id uuid,title text,venue text,starts_at timestamptz,
  guest_names text[],seats integer,status text,amount_paise integer,payment_status text,
  booking_source text,reservation_expires_at timestamptz,cancelled_at timestamptz,
  can_cancel boolean,refund_eligible boolean
)
language sql security definer set search_path=public,pg_temp as $$
select b.id,e.id,e.title,e.venue,e.starts_at,
  array(select g.guest_name from public.booking_guests g where g.booking_id=b.id order by g.position),
  b.seats,b.status,b.amount_paise,b.payment_status,b.booking_source,b.reservation_expires_at,b.cancelled_at,
  (b.status in ('pending_payment','confirmed') and now()<e.starts_at),
  (b.booking_source='member_payment' and b.payment_status='paid' and now()<=e.refund_cutoff_at)
from public.event_bookings b join public.events e on e.id=b.event_id
where b.member_id=auth.uid();
$$;

revoke all on function public.grant_complimentary_event_booking(uuid,text,text[],text) from public,anon;
revoke all on function public.get_my_event_bookings() from public,anon;
grant execute on function public.grant_complimentary_event_booking(uuid,text,text[],text) to authenticated;
grant execute on function public.get_my_event_bookings() to authenticated;

commit;
