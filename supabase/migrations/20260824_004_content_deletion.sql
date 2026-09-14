begin;

-- This migration is the first post-invitation application migration. The
-- original build applied the following stage files before later incremental
-- patches, so a fresh project must establish this baseline here.
-- Restored authoritative baseline: OneClub_Supabase_Stage5_Member_Experience.sql
create table if not exists public.partners (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  category text not null,
  description text not null,
  location text not null,
  website text,
  status text not null default 'active' check (status in ('draft','active','inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.benefits (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  title text not null,
  description text not null,
  redemption_instructions text not null,
  terms text not null,
  status text not null default 'active' check (status in ('draft','active','inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(partner_id,title)
);

alter table public.partners enable row level security;
alter table public.benefits enable row level security;
revoke all on table public.partners from anon, authenticated;
revoke all on table public.benefits from anon, authenticated;

insert into public.partners(name,slug,category,description,location,website,status) values
('Aurelia Hills Retreat','aurelia-hills-retreat','Hotels & Resorts','A refined hillside retreat pairing quiet luxury with considered hospitality.','Nandi Hills, Karnataka','https://example.com/aurelia','active'),
('Form & Flow Club','form-and-flow-club','Gyms & Wellness','A private training and recovery studio for strength, mobility and wellbeing.','Indiranagar, Bangalore','https://example.com/form-flow','active'),
('Serein Spa House','serein-spa-house','Spa & Salons','An intimate wellness house offering restorative rituals and premium grooming.','Lavelle Road, Bangalore','https://example.com/serein','active'),
('Northline Auto Atelier','northline-auto-atelier','Automotive','A specialist detailing studio focused on preservation, finish and discreet service.','Whitefield, Bangalore','https://example.com/northline','active'),
('Wild Meridian Escapes','wild-meridian-escapes','Adventure Stays','Curated wilderness stays and small-group outdoor experiences across Karnataka.','Coorg, Karnataka','https://example.com/wild-meridian','active')
on conflict(slug) do update set name=excluded.name,category=excluded.category,description=excluded.description,location=excluded.location,website=excluded.website,status=excluded.status,updated_at=now();

insert into public.benefits(partner_id,title,description,redemption_instructions,terms,status)
select id,'Preferred stay privilege','Receive 15% off selected room categories, with early check-in and late checkout where available.','Present your active One Club member ID when booking and again at check-in.','Subject to availability; blackout dates may apply. Non-transferable.','active' from public.partners where slug='aurelia-hills-retreat'
on conflict(partner_id,title) do update set description=excluded.description,redemption_instructions=excluded.redemption_instructions,terms=excluded.terms,status=excluded.status,updated_at=now();

insert into public.benefits(partner_id,title,description,redemption_instructions,terms,status)
select id,'Member performance access','Receive 10% off selected training packages and a complimentary movement assessment.','Show your active member ID before purchasing an eligible package.','New packages only; advance appointment required.','active' from public.partners where slug='form-and-flow-club'
on conflict(partner_id,title) do update set description=excluded.description,redemption_instructions=excluded.redemption_instructions,terms=excluded.terms,status=excluded.status,updated_at=now();

insert into public.benefits(partner_id,title,description,redemption_instructions,terms,status)
select id,'Restorative ritual privilege','Receive 15% off selected spa rituals with preferred appointment assistance.','Mention One Club while booking and present your active member ID on arrival.','Cannot be combined with other offers.','active' from public.partners where slug='serein-spa-house'
on conflict(partner_id,title) do update set description=excluded.description,redemption_instructions=excluded.redemption_instructions,terms=excluded.terms,status=excluded.status,updated_at=now();

insert into public.benefits(partner_id,title,description,redemption_instructions,terms,status)
select id,'Signature detailing privilege','Receive 10% off the signature detailing package and priority scheduling.','Share your member ID when requesting an appointment.','Valid for one vehicle per booking; subject to available slots.','active' from public.partners where slug='northline-auto-atelier'
on conflict(partner_id,title) do update set description=excluded.description,redemption_instructions=excluded.redemption_instructions,terms=excluded.terms,status=excluded.status,updated_at=now();

insert into public.benefits(partner_id,title,description,redemption_instructions,terms,status)
select id,'Curated escape privilege','Receive 12% off selected stays and preferred experience planning.','Contact the property using the member instructions and provide your active member ID.','Selected dates and properties only; advance booking required.','active' from public.partners where slug='wild-meridian-escapes'
on conflict(partner_id,title) do update set description=excluded.description,redemption_instructions=excluded.redemption_instructions,terms=excluded.terms,status=excluded.status,updated_at=now();

create or replace function public.get_active_member_benefits()
returns table(partner_name text,category text,partner_description text,location text,website text,benefit_title text,benefit_description text,redemption_instructions text,terms text)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and membership_state='active') then
    raise exception 'Active membership required';
  end if;
  return query select p.name,p.category,p.description,p.location,p.website,b.title,b.description,b.redemption_instructions,b.terms
  from public.partners p join public.benefits b on b.partner_id=p.id
  where p.status='active' and b.status='active' order by p.category,p.name,b.title;
end;
$$;

revoke all on function public.get_active_member_benefits() from public;
grant execute on function public.get_active_member_benefits() to authenticated;

-- Restored authoritative baseline: OneClub_Supabase_Stage6A_Events_Bookings.sql
create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null,
  venue text not null,
  starts_at timestamptz not null,
  booking_closes_at timestamptz not null,
  refund_cutoff_at timestamptz not null,
  capacity integer not null check (capacity > 0),
  price_paise integer not null default 0 check (price_paise >= 0),
  status text not null default 'published' check (status in ('draft','published','cancelled','completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint event_dates_valid check (refund_cutoff_at <= booking_closes_at and booking_closes_at < starts_at)
);

create table if not exists public.event_bookings (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete restrict,
  member_id uuid not null references public.profiles(id) on delete restrict,
  guest_name text,
  seats integer not null check (seats in (1,2)),
  status text not null default 'pending_payment' check (status in ('pending_payment','confirmed','cancelled')),
  amount_paise integer not null check (amount_paise >= 0),
  payment_status text not null default 'unpaid' check (payment_status in ('unpaid','paid','refund_pending','refunded')),
  reservation_expires_at timestamptz,
  booked_at timestamptz not null default now(),
  cancelled_at timestamptz,
  updated_at timestamptz not null default now()
);

create unique index if not exists one_open_booking_per_member_event
  on public.event_bookings(event_id,member_id) where status in ('pending_payment','confirmed');

alter table public.events enable row level security;
alter table public.event_bookings enable row level security;
revoke all on table public.events from anon,authenticated;
revoke all on table public.event_bookings from anon,authenticated;

insert into public.events(title,description,venue,starts_at,booking_closes_at,refund_cutoff_at,capacity,price_paise,status)
select 'Founder''s Breakfast','An intimate morning gathering for founding members, thoughtful introductions and conversation over breakfast.','The Courtyard Room, Bangalore','2026-11-15 09:00:00+05:30','2026-11-13 09:00:00+05:30','2026-11-01 09:00:00+05:30',30,250000,'published'
where not exists(select 1 from public.events where title='Founder''s Breakfast' and starts_at='2026-11-15 09:00:00+05:30');

create or replace function public.get_member_events()
returns table(id uuid,title text,description text,venue text,starts_at timestamptz,booking_closes_at timestamptz,refund_cutoff_at timestamptz,capacity integer,price_paise integer,seats_available integer)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not exists(select 1 from public.profiles where profiles.id=auth.uid() and app_role='member' and membership_state='active') then raise exception 'Active membership required'; end if;
  return query
  select e.id,e.title,e.description,e.venue,e.starts_at,e.booking_closes_at,e.refund_cutoff_at,e.capacity,e.price_paise,
    greatest(0,e.capacity-coalesce(sum(b.seats) filter(where b.status='confirmed' or (b.status='pending_payment' and b.reservation_expires_at>now())),0)::integer) seats_available
  from public.events e left join public.event_bookings b on b.event_id=e.id
  where e.status='published' and e.starts_at>now()
  group by e.id order by e.starts_at;
end; $$;

create or replace function public.create_event_booking(p_event_id uuid,p_guest_name text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_event public.events; v_seats integer; v_taken integer; v_id uuid;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role='member' and membership_state='active') then raise exception 'Active membership required'; end if;
  select * into v_event from public.events where id=p_event_id and status='published' for update;
  if not found then raise exception 'Event not available'; end if;
  if now()>=v_event.booking_closes_at then raise exception 'Booking has closed'; end if;
  v_seats:=case when nullif(trim(p_guest_name),'') is null then 1 else 2 end;
  select coalesce(sum(seats),0) into v_taken from public.event_bookings where event_id=p_event_id and (status='confirmed' or (status='pending_payment' and reservation_expires_at>now()));
  if v_event.capacity-v_taken<v_seats then raise exception 'Not enough places available'; end if;
  update public.event_bookings set status='cancelled',cancelled_at=now(),updated_at=now() where event_id=p_event_id and member_id=auth.uid() and status='pending_payment' and reservation_expires_at<=now();
  insert into public.event_bookings(event_id,member_id,guest_name,seats,amount_paise,reservation_expires_at)
  values(p_event_id,auth.uid(),nullif(trim(p_guest_name),''),v_seats,v_event.price_paise*v_seats,now()+interval '15 minutes') returning id into v_id;
  return v_id;
exception when unique_violation then raise exception 'You already have a booking for this event';
end; $$;

create or replace function public.get_my_event_bookings()
returns table(booking_id uuid,event_id uuid,title text,venue text,starts_at timestamptz,guest_name text,seats integer,status text,amount_paise integer,payment_status text,reservation_expires_at timestamptz,can_cancel boolean,refund_eligible boolean)
language sql security definer set search_path=public,pg_temp as $$
select b.id,e.id,e.title,e.venue,e.starts_at,b.guest_name,b.seats,b.status,b.amount_paise,b.payment_status,b.reservation_expires_at,
  (b.status in ('pending_payment','confirmed') and now()<e.starts_at),
  (b.payment_status='paid' and now()<=e.refund_cutoff_at)
from public.event_bookings b join public.events e on e.id=b.event_id where b.member_id=auth.uid() order by e.starts_at;
$$;

create or replace function public.cancel_event_booking(p_booking_id uuid)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v_booking public.event_bookings; v_cutoff timestamptz; v_result text;
begin
  select b.* into v_booking from public.event_bookings b where b.id=p_booking_id and b.member_id=auth.uid() for update;
  if not found or v_booking.status not in ('pending_payment','confirmed') then raise exception 'Booking cannot be cancelled'; end if;
  select refund_cutoff_at into v_cutoff from public.events where id=v_booking.event_id;
  v_result:=case when v_booking.payment_status='paid' and now()<=v_cutoff then 'refund_pending' else v_booking.payment_status end;
  update public.event_bookings set status='cancelled',payment_status=v_result,cancelled_at=now(),updated_at=now() where id=p_booking_id;
  return v_result;
end; $$;

revoke all on function public.get_member_events() from public;
revoke all on function public.create_event_booking(uuid,text) from public;
revoke all on function public.get_my_event_bookings() from public;
revoke all on function public.cancel_event_booking(uuid) from public;
grant execute on function public.get_member_events() to authenticated;
grant execute on function public.create_event_booking(uuid,text) to authenticated;
grant execute on function public.get_my_event_bookings() to authenticated;
grant execute on function public.cancel_event_booking(uuid) to authenticated;

-- Restored authoritative baseline: OneClub_Supabase_Stage6B_Payments.sql
create table if not exists public.payment_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  purpose text not null check (purpose in ('membership','event')),
  booking_id uuid references public.event_bookings(id) on delete restrict,
  amount_paise integer not null check (amount_paise > 0),
  currency text not null default 'INR' check (currency='INR'),
  razorpay_order_id text not null unique,
  razorpay_payment_id text unique,
  status text not null default 'created' check (status in ('created','paid','failed')),
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint payment_purpose_booking check ((purpose='event' and booking_id is not null) or (purpose='membership' and booking_id is null))
);

alter table public.payment_attempts enable row level security;
revoke all on table public.payment_attempts from anon,authenticated;

create or replace function public.finalize_razorpay_payment(p_attempt_id uuid,p_payment_id text)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v payment_attempts; v_number text;
begin
  select * into v from public.payment_attempts where id=p_attempt_id for update;
  if not found then raise exception 'Payment attempt not found'; end if;
  if v.status='paid' then return v.purpose; end if;
  update public.payment_attempts set status='paid',razorpay_payment_id=p_payment_id,paid_at=now(),updated_at=now() where id=v.id;
  if v.purpose='membership' then
    select member_number into v_number from public.profiles where id=v.user_id for update;
    if v_number is null then v_number:='OC-F-'||lpad(nextval('public.founding_member_number_seq')::text,6,'0'); end if;
    update public.profiles set membership_state='active',member_number=v_number,updated_at=now() where id=v.user_id and membership_state='payment_pending';
    if not found then raise exception 'Membership is not awaiting payment'; end if;
    insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values(v.user_id,'membership.payment_confirmed','profile',v.user_id::text,jsonb_build_object('member_number',v_number,'payment_id',p_payment_id));
  else
    update public.event_bookings set status='confirmed',payment_status='paid',reservation_expires_at=null,updated_at=now() where id=v.booking_id and member_id=v.user_id and status='pending_payment';
    if not found then raise exception 'Event reservation is no longer payable'; end if;
    insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values(v.user_id,'event.payment_confirmed','event_booking',v.booking_id::text,jsonb_build_object('payment_id',p_payment_id));
  end if;
  return v.purpose;
end; $$;

revoke all on function public.finalize_razorpay_payment(uuid,text) from public;
grant execute on function public.finalize_razorpay_payment(uuid,text) to service_role;

-- Restored authoritative baseline: OneClub_Supabase_Stage7A_Member_Administration.sql
create or replace function public.can_manage_members()
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
select exists(select 1 from public.profiles where id=auth.uid() and (app_role='admin' or (app_role='staff' and staff_role='general')));
$$;
revoke all on function public.can_manage_members() from public;
grant execute on function public.can_manage_members() to authenticated;

create or replace function public.list_members_for_management()
returns table(id uuid,email text,full_name text,phone text,member_number text,membership_state text,created_at timestamptz)
language plpgsql security definer set search_path=public,auth,pg_temp as $$
begin
  if not public.can_manage_members() then raise exception 'Member management permission required'; end if;
  return query select p.id,u.email::text,p.full_name,p.phone,p.member_number,p.membership_state::text,p.created_at
  from public.profiles p join auth.users u on u.id=p.id where p.app_role='member'
  order by case p.membership_state when 'active' then 1 when 'suspended' then 2 when 'payment_pending' then 3 else 4 end,p.created_at;
end; $$;

create or replace function public.set_member_access_state(p_member_id uuid,p_action text,p_reason text default null)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v_current membership_state; v_next membership_state;
begin
  if not public.can_manage_members() then raise exception 'Member management permission required'; end if;
  select membership_state into v_current from public.profiles where id=p_member_id and app_role='member' for update;
  if not found then raise exception 'Member not found'; end if;
  if p_action='suspend' and v_current='active' then v_next:='suspended';
  elsif p_action='reactivate' and v_current='suspended' then v_next:='active';
  else raise exception 'This member cannot be % from the current state',p_action; end if;
  update public.profiles set membership_state=v_next,updated_at=now() where id=p_member_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'membership.'||p_action,'profile',p_member_id::text,jsonb_build_object('previous_state',v_current::text,'new_state',v_next::text,'reason',nullif(trim(p_reason),'')));
  return v_next::text;
end; $$;

revoke all on function public.list_members_for_management() from public;
revoke all on function public.set_member_access_state(uuid,text,text) from public;
grant execute on function public.list_members_for_management() to authenticated;
grant execute on function public.set_member_access_state(uuid,text,text) to authenticated;

-- Restored authoritative baseline: OneClub_Supabase_Stage7B_Member_Support.sql
create table if not exists public.member_support_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  category text not null check (category in ('membership_access','payment','event_booking','profile','other')),
  message text not null check (char_length(message) between 10 and 2000),
  status text not null default 'open' check (status in ('open','in_progress','resolved','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.member_support_requests enable row level security;
revoke all on table public.member_support_requests from anon,authenticated;

create or replace function public.submit_member_support_request(p_category text,p_message text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
  if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'Sign in required'; end if;
  if p_category not in ('membership_access','payment','event_booking','profile','other') then raise exception 'Invalid support category'; end if;
  if char_length(trim(p_message))<10 or char_length(trim(p_message))>2000 then raise exception 'Message must contain between 10 and 2000 characters'; end if;
  insert into public.member_support_requests(user_id,category,message) values(auth.uid(),p_category,trim(p_message)) returning id into v_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'member.support_requested','member_support_request',v_id::text,jsonb_build_object('category',p_category));
  return v_id;
end; $$;

revoke all on function public.submit_member_support_request(text,text) from public;
grant execute on function public.submit_member_support_request(text,text) to authenticated;

-- Restored authoritative baseline: OneClub_Supabase_Stage7C_Support_Operations.sql
create or replace function public.list_support_requests_for_staff(p_status text default null)
returns table(id uuid,member_id uuid,email text,full_name text,member_number text,membership_state text,category text,message text,status text,created_at timestamptz,updated_at timestamptz)
language plpgsql security definer set search_path=public,auth,pg_temp as $$
begin
  if not public.can_manage_members() then raise exception 'Support workspace permission required'; end if;
  if p_status is not null and p_status not in ('open','in_progress','resolved','closed') then raise exception 'Invalid support status'; end if;
  return query select r.id,r.user_id,u.email::text,p.full_name,p.member_number,p.membership_state::text,r.category,r.message,r.status,r.created_at,r.updated_at
  from public.member_support_requests r join public.profiles p on p.id=r.user_id join auth.users u on u.id=r.user_id
  where p_status is null or r.status=p_status
  order by case r.status when 'open' then 1 when 'in_progress' then 2 when 'resolved' then 3 else 4 end,r.created_at;
end; $$;

create or replace function public.update_support_request_status(p_request_id uuid,p_status text)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v_previous text;
begin
  if not public.can_manage_members() then raise exception 'Support workspace permission required'; end if;
  if p_status not in ('open','in_progress','resolved','closed') then raise exception 'Invalid support status'; end if;
  select status into v_previous from public.member_support_requests where id=p_request_id for update;
  if not found then raise exception 'Support request not found'; end if;
  if v_previous=p_status then return p_status; end if;
  update public.member_support_requests set status=p_status,updated_at=now() where id=p_request_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'support.status_changed','member_support_request',p_request_id::text,jsonb_build_object('previous_status',v_previous,'new_status',p_status));
  return p_status;
end; $$;

revoke all on function public.list_support_requests_for_staff(text) from public;
revoke all on function public.update_support_request_status(uuid,text) from public;
grant execute on function public.list_support_requests_for_staff(text) to authenticated;
grant execute on function public.update_support_request_status(uuid,text) to authenticated;

-- Restored authoritative baseline: OneClub_Supabase_Stage7D_Event_Management.sql
create or replace function public.can_manage_events()
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
select exists(select 1 from public.profiles where id=auth.uid() and (app_role='admin' or (app_role='staff' and staff_role='marketing')));
$$;
revoke all on function public.can_manage_events() from public;
grant execute on function public.can_manage_events() to authenticated;

create or replace function public.list_events_for_management()
returns table(id uuid,title text,description text,venue text,starts_at timestamptz,booking_closes_at timestamptz,refund_cutoff_at timestamptz,capacity integer,price_paise integer,status text,booked_seats integer)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.can_manage_events() then raise exception 'Event management permission required'; end if;
  return query select e.id,e.title,e.description,e.venue,e.starts_at,e.booking_closes_at,e.refund_cutoff_at,e.capacity,e.price_paise,e.status,
    coalesce(sum(b.seats) filter(where b.status='confirmed'),0)::integer
  from public.events e left join public.event_bookings b on b.event_id=e.id group by e.id order by e.starts_at desc;
end; $$;

create or replace function public.save_event(p_id uuid,p_title text,p_description text,p_venue text,p_starts_at timestamptz,p_booking_closes_at timestamptz,p_refund_cutoff_at timestamptz,p_capacity integer,p_price_paise integer,p_status text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_booked integer;
begin
  if not public.can_manage_events() then raise exception 'Event management permission required'; end if;
  if char_length(trim(p_title))<3 or char_length(trim(p_description))<10 or char_length(trim(p_venue))<3 then raise exception 'Please complete the event details'; end if;
  if p_status not in ('draft','published','cancelled','completed') then raise exception 'Invalid event status'; end if;
  if p_capacity<1 or p_price_paise<0 then raise exception 'Capacity or price is invalid'; end if;
  if not (p_refund_cutoff_at<=p_booking_closes_at and p_booking_closes_at<p_starts_at) then raise exception 'The refund cutoff must precede booking close, which must precede the event'; end if;
  if p_id is null then
    insert into public.events(title,description,venue,starts_at,booking_closes_at,refund_cutoff_at,capacity,price_paise,status)
    values(trim(p_title),trim(p_description),trim(p_venue),p_starts_at,p_booking_closes_at,p_refund_cutoff_at,p_capacity,p_price_paise,p_status) returning id into v_id;
    insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'event.created','event',v_id::text,jsonb_build_object('title',trim(p_title),'status',p_status));
  else
    select coalesce(sum(seats),0)::integer into v_booked from public.event_bookings where event_id=p_id and status='confirmed';
    if p_capacity<v_booked then raise exception 'Capacity cannot be lower than confirmed seats (%)',v_booked; end if;
    update public.events set title=trim(p_title),description=trim(p_description),venue=trim(p_venue),starts_at=p_starts_at,booking_closes_at=p_booking_closes_at,refund_cutoff_at=p_refund_cutoff_at,capacity=p_capacity,price_paise=p_price_paise,status=p_status,updated_at=now() where id=p_id returning id into v_id;
    if v_id is null then raise exception 'Event not found'; end if;
    insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'event.updated','event',v_id::text,jsonb_build_object('title',trim(p_title),'status',p_status));
  end if;
  return v_id;
end; $$;

revoke all on function public.list_events_for_management() from public;
revoke all on function public.save_event(uuid,text,text,text,timestamptz,timestamptz,timestamptz,integer,integer,text) from public;
grant execute on function public.list_events_for_management() to authenticated;
grant execute on function public.save_event(uuid,text,text,text,timestamptz,timestamptz,timestamptz,integer,integer,text) to authenticated;

-- Restored authoritative baseline: OneClub_Supabase_Stage7E_Partner_Benefit_Management.sql
create or replace function public.can_manage_partner_content()
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
select exists(select 1 from public.profiles where id=auth.uid() and (app_role='admin' or (app_role='staff' and staff_role='general')));
$$;
revoke all on function public.can_manage_partner_content() from public;
grant execute on function public.can_manage_partner_content() to authenticated;

create or replace function public.list_partner_content_for_management()
returns table(partner_id uuid,partner_name text,slug text,category text,partner_description text,location text,website text,partner_status text,benefit_id uuid,benefit_title text,benefit_description text,redemption_instructions text,terms text,benefit_status text)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.can_manage_partner_content() then raise exception 'Partner content permission required'; end if;
  return query select p.id,p.name,p.slug,p.category,p.description,p.location,p.website,p.status,b.id,b.title,b.description,b.redemption_instructions,b.terms,b.status
  from public.partners p left join public.benefits b on b.partner_id=p.id order by p.name,b.title;
end; $$;

create or replace function public.save_partner(p_id uuid,p_name text,p_slug text,p_category text,p_description text,p_location text,p_website text,p_status text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
  if not public.can_manage_partner_content() then raise exception 'Partner content permission required'; end if;
  if char_length(trim(p_name))<2 or char_length(trim(p_slug))<2 or p_slug!~'^[a-z0-9]+(?:-[a-z0-9]+)*$' or char_length(trim(p_description))<10 or char_length(trim(p_location))<2 then raise exception 'Please complete valid partner details'; end if;
  if p_status not in ('draft','active','inactive') then raise exception 'Invalid partner status'; end if;
  if nullif(trim(p_website),'') is not null and p_website!~'^https?://' then raise exception 'Website must begin with http:// or https://'; end if;
  if p_id is null then insert into public.partners(name,slug,category,description,location,website,status) values(trim(p_name),trim(p_slug),trim(p_category),trim(p_description),trim(p_location),nullif(trim(p_website),''),p_status) returning id into v_id;
  else update public.partners set name=trim(p_name),slug=trim(p_slug),category=trim(p_category),description=trim(p_description),location=trim(p_location),website=nullif(trim(p_website),''),status=p_status,updated_at=now() where id=p_id returning id into v_id; if v_id is null then raise exception 'Partner not found'; end if; end if;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),case when p_id is null then 'partner.created' else 'partner.updated' end,'partner',v_id::text,jsonb_build_object('name',trim(p_name),'status',p_status));
  return v_id;
exception when unique_violation then raise exception 'That partner slug is already in use';
end; $$;

create or replace function public.save_benefit(p_id uuid,p_partner_id uuid,p_title text,p_description text,p_redemption_instructions text,p_terms text,p_status text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
  if not public.can_manage_partner_content() then raise exception 'Partner content permission required'; end if;
  if not exists(select 1 from public.partners where id=p_partner_id) then raise exception 'Partner not found'; end if;
  if char_length(trim(p_title))<3 or char_length(trim(p_description))<10 or char_length(trim(p_redemption_instructions))<10 or char_length(trim(p_terms))<3 then raise exception 'Please complete the benefit details'; end if;
  if p_status not in ('draft','active','inactive') then raise exception 'Invalid benefit status'; end if;
  if p_id is null then insert into public.benefits(partner_id,title,description,redemption_instructions,terms,status) values(p_partner_id,trim(p_title),trim(p_description),trim(p_redemption_instructions),trim(p_terms),p_status) returning id into v_id;
  else update public.benefits set partner_id=p_partner_id,title=trim(p_title),description=trim(p_description),redemption_instructions=trim(p_redemption_instructions),terms=trim(p_terms),status=p_status,updated_at=now() where id=p_id returning id into v_id; if v_id is null then raise exception 'Benefit not found'; end if; end if;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),case when p_id is null then 'benefit.created' else 'benefit.updated' end,'benefit',v_id::text,jsonb_build_object('title',trim(p_title),'partner_id',p_partner_id,'status',p_status));
  return v_id;
exception when unique_violation then raise exception 'This partner already has a benefit with that title';
end; $$;

revoke all on function public.list_partner_content_for_management() from public;
revoke all on function public.save_partner(uuid,text,text,text,text,text,text,text) from public;
revoke all on function public.save_benefit(uuid,uuid,text,text,text,text,text) from public;
grant execute on function public.list_partner_content_for_management() to authenticated;
grant execute on function public.save_partner(uuid,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.save_benefit(uuid,uuid,text,text,text,text,text) to authenticated;

-- Restored authoritative baseline: OneClub_Supabase_Stage7F_Technical_Diagnostics.sql
create or replace function public.can_view_diagnostics()
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
select exists(select 1 from public.profiles where id=auth.uid() and (app_role='admin' or (app_role='staff' and staff_role='technical')));
$$;
revoke all on function public.can_view_diagnostics() from public;
grant execute on function public.can_view_diagnostics() to authenticated;

create or replace function public.get_technical_diagnostics()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_result jsonb;
begin
  if not public.can_view_diagnostics() then raise exception 'Technical diagnostics permission required'; end if;
  select jsonb_build_object(
    'checked_at',now(),
    'database','connected',
    'profiles',jsonb_build_object('total',(select count(*) from public.profiles),'active_members',(select count(*) from public.profiles where membership_state='active'),'suspended_members',(select count(*) from public.profiles where membership_state='suspended'),'payment_pending_members',(select count(*) from public.profiles where membership_state='payment_pending')),
    'sales',jsonb_build_object('new_enquiries',(select count(*) from public.enquiries where status='new'),'approved_enquiries',(select count(*) from public.enquiries where status='approved'),'active_invitations',(select count(*) from public.membership_invitations where status='active' and expires_at>now())),
    'support',jsonb_build_object('open',(select count(*) from public.member_support_requests where status='open'),'in_progress',(select count(*) from public.member_support_requests where status='in_progress')),
    'events',jsonb_build_object('published',(select count(*) from public.events where status='published'),'confirmed_bookings',(select count(*) from public.event_bookings where status='confirmed'),'pending_bookings',(select count(*) from public.event_bookings where status='pending_payment' and reservation_expires_at>now())),
    'payments',jsonb_build_object('paid',(select count(*) from public.payment_attempts where status='paid'),'created',(select count(*) from public.payment_attempts where status='created'),'failed',(select count(*) from public.payment_attempts where status='failed')),
    'content',jsonb_build_object('active_partners',(select count(*) from public.partners where status='active'),'active_benefits',(select count(*) from public.benefits where status='active')),
    'audit_entries',(select count(*) from public.audit_log)
  ) into v_result;
  return v_result;
end; $$;

revoke all on function public.get_technical_diagnostics() from public;
grant execute on function public.get_technical_diagnostics() to authenticated;

create or replace function public.delete_event(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid()
      and (app_role::text = 'admin' or (app_role::text = 'staff' and staff_role::text = 'marketing'))
  ) then
    raise exception 'Event management permission required';
  end if;

  if exists (select 1 from public.event_bookings where event_id = p_id) then
    raise exception 'This event has booking history and cannot be permanently deleted. Mark it cancelled instead.';
  end if;

  delete from public.events where id = p_id;
  if not found then raise exception 'Event not found'; end if;
end;
$$;

create or replace function public.delete_benefit(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid()
      and (app_role::text = 'admin' or (app_role::text = 'staff' and staff_role::text = 'general'))
  ) then
    raise exception 'Partner and benefit management permission required';
  end if;

  delete from public.benefits where id = p_id;
  if not found then raise exception 'Benefit not found'; end if;
end;
$$;

create or replace function public.delete_partner(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid()
      and (app_role::text = 'admin' or (app_role::text = 'staff' and staff_role::text = 'general'))
  ) then
    raise exception 'Partner and benefit management permission required';
  end if;

  if exists (select 1 from public.benefits where partner_id = p_id) then
    raise exception 'Delete this partner''s benefits before deleting the partner.';
  end if;

  delete from public.partners where id = p_id;
  if not found then raise exception 'Partner not found'; end if;
end;
$$;

revoke all on function public.delete_event(uuid) from public, anon;
revoke all on function public.delete_benefit(uuid) from public, anon;
revoke all on function public.delete_partner(uuid) from public, anon;
grant execute on function public.delete_event(uuid) to authenticated;
grant execute on function public.delete_benefit(uuid) to authenticated;
grant execute on function public.delete_partner(uuid) to authenticated;

commit;
