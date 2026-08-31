begin;

create table if not exists public.booking_guests (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.event_bookings(id) on delete cascade,
  guest_name text not null check (char_length(trim(guest_name)) between 1 and 100),
  position integer not null check (position between 1 and 20),
  created_at timestamptz not null default now(),
  unique(booking_id,position)
);

insert into public.booking_guests(booking_id,guest_name,position)
select id,trim(guest_name),1 from public.event_bookings
where nullif(trim(guest_name),'') is not null
on conflict(booking_id,position) do nothing;

alter table public.booking_guests enable row level security;
revoke all on table public.booking_guests from anon,authenticated;

alter table public.event_bookings drop constraint if exists event_bookings_seats_check;
alter table public.event_bookings add constraint event_bookings_seats_check check (seats between 1 and 21);

drop function if exists public.get_member_events();
create function public.get_member_events()
returns table(id uuid,title text,description text,venue text,starts_at timestamptz,booking_closes_at timestamptz,refund_cutoff_at timestamptz,capacity integer,price_paise integer,max_guests_per_member integer,pricing_model text,seats_available integer)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not exists(select 1 from public.profiles where profiles.id=auth.uid() and app_role='member' and membership_state='active') then raise exception 'Active membership required'; end if;
  return query select e.id,e.title,e.description,e.venue,e.starts_at,e.booking_closes_at,e.refund_cutoff_at,e.capacity,e.price_paise,e.max_guests_per_member,e.pricing_model,
    greatest(0,e.capacity-coalesce(sum(b.seats) filter(where b.status='confirmed' or (b.status='pending_payment' and b.reservation_expires_at>now())),0)::integer)
  from public.events e left join public.event_bookings b on b.event_id=e.id
  where e.status='published' and e.starts_at>now() group by e.id order by e.starts_at;
end; $$;

drop function if exists public.create_event_booking(uuid,text);
drop function if exists public.create_event_booking(uuid,text[]);
create function public.create_event_booking(p_event_id uuid,p_guest_names text[] default '{}'::text[])
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_event public.events;v_guests text[];v_seats integer;v_taken integer;v_amount integer;v_id uuid;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role='member' and membership_state='active') then raise exception 'Active membership required'; end if;
  if cardinality(coalesce(p_guest_names,'{}'::text[]))>20 then raise exception 'Too many guests supplied'; end if;
  select coalesce(array_agg(trim(value) order by position),'{}'::text[]) into v_guests
  from unnest(coalesce(p_guest_names,'{}'::text[])) with ordinality as supplied(value,position) where nullif(trim(value),'') is not null;
  if cardinality(v_guests)<>cardinality(coalesce(p_guest_names,'{}'::text[])) then raise exception 'Every guest must have a name'; end if;
  if exists(select 1 from unnest(v_guests) as supplied_guest(name) where char_length(name)>100) then raise exception 'Guest names must be 100 characters or fewer'; end if;
  select * into v_event from public.events where id=p_event_id and status='published' for update;
  if not found then raise exception 'Event not available'; end if;
  if now()>=v_event.booking_closes_at then raise exception 'Booking has closed'; end if;
  if cardinality(v_guests)>v_event.max_guests_per_member then raise exception 'This event permits a maximum of % guests per member',v_event.max_guests_per_member; end if;
  v_seats:=1+cardinality(v_guests);
  select coalesce(sum(seats),0) into v_taken from public.event_bookings where event_id=p_event_id and (status='confirmed' or (status='pending_payment' and reservation_expires_at>now()));
  if v_event.capacity-v_taken<v_seats then raise exception 'Not enough places available'; end if;
  update public.event_bookings set status='cancelled',cancelled_at=now(),updated_at=now() where event_id=p_event_id and member_id=auth.uid() and status='pending_payment' and reservation_expires_at<=now();
  v_amount:=case when v_event.pricing_model='fixed_booking' then v_event.price_paise else v_event.price_paise*v_seats end;
  insert into public.event_bookings(event_id,member_id,guest_name,seats,amount_paise,reservation_expires_at)
  values(p_event_id,auth.uid(),v_guests[1],v_seats,v_amount,now()+interval '15 minutes') returning id into v_id;
  insert into public.booking_guests(booking_id,guest_name,position) select v_id,name,position::integer from unnest(v_guests) with ordinality as guest(name,position);
  return v_id;
exception when unique_violation then raise exception 'You already have a booking for this event';
end; $$;

drop function if exists public.get_my_event_bookings();
create function public.get_my_event_bookings()
returns table(booking_id uuid,event_id uuid,title text,venue text,starts_at timestamptz,guest_names text[],seats integer,status text,amount_paise integer,payment_status text,reservation_expires_at timestamptz,can_cancel boolean,refund_eligible boolean)
language sql security definer set search_path=public,pg_temp as $$
select b.id,e.id,e.title,e.venue,e.starts_at,array(select g.guest_name from public.booking_guests g where g.booking_id=b.id order by g.position),b.seats,b.status,b.amount_paise,b.payment_status,b.reservation_expires_at,
  (b.status in ('pending_payment','confirmed') and now()<e.starts_at),(b.payment_status='paid' and now()<=e.refund_cutoff_at)
from public.event_bookings b join public.events e on e.id=b.event_id where b.member_id=auth.uid() order by e.starts_at;
$$;

revoke all on function public.get_member_events() from public,anon;
revoke all on function public.create_event_booking(uuid,text[]) from public,anon;
revoke all on function public.get_my_event_bookings() from public,anon;
grant execute on function public.get_member_events() to authenticated;
grant execute on function public.create_event_booking(uuid,text[]) to authenticated;
grant execute on function public.get_my_event_bookings() to authenticated;

commit;
