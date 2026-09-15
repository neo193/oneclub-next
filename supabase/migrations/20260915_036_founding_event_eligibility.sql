begin;

alter table public.events add column if not exists audience text not null default 'all_members';
alter table public.events drop constraint if exists events_audience_check;
alter table public.events add constraint events_audience_check check (audience in ('all_members','founding_members'));

drop function if exists public.get_member_events();
create function public.get_member_events()
returns table(id uuid,title text,description text,venue text,starts_at timestamptz,booking_closes_at timestamptz,refund_cutoff_at timestamptz,capacity integer,price_paise integer,max_guests_per_member integer,pricing_model text,seats_available integer,audience text,can_book boolean)
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_founding boolean;
begin
  select founding_member_sequence is not null into v_founding from public.profiles where id=auth.uid() and app_role::text='member' and membership_state::text='active';
  if not found then raise exception 'Active membership required'; end if;
  return query select e.id,e.title,e.description,e.venue,e.starts_at,e.booking_closes_at,e.refund_cutoff_at,e.capacity,e.price_paise,e.max_guests_per_member,e.pricing_model,
    greatest(0,e.capacity-coalesce(sum(b.seats) filter(where b.status='confirmed' or (b.status='pending_payment' and b.reservation_expires_at>now())),0)::integer),e.audience,
    (e.audience='all_members' or v_founding)
  from public.events e left join public.event_bookings b on b.event_id=e.id
  where e.status='published' and e.starts_at>now() group by e.id order by e.starts_at;
end; $$;

drop function if exists public.list_events_for_management();
create function public.list_events_for_management()
returns table(id uuid,title text,description text,venue text,starts_at timestamptz,booking_closes_at timestamptz,refund_cutoff_at timestamptz,capacity integer,price_paise integer,max_guests_per_member integer,pricing_model text,status text,booked_seats integer,held_seats integer,audience text)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.can_manage_events() then raise exception 'Event management permission required'; end if;
  return query select e.id,e.title,e.description,e.venue,e.starts_at,e.booking_closes_at,e.refund_cutoff_at,e.capacity,e.price_paise,e.max_guests_per_member,e.pricing_model,e.status,
    coalesce(sum(b.seats) filter(where b.status='confirmed'),0)::integer,
    coalesce(sum(b.seats) filter(where b.status='pending_payment' and b.reservation_expires_at>now()),0)::integer,e.audience
  from public.events e left join public.event_bookings b on b.event_id=e.id group by e.id order by e.starts_at desc;
end; $$;

create or replace function public.set_event_audience(p_event_id uuid,p_audience text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.can_manage_events() then raise exception 'Event management permission required'; end if;
  if p_audience not in ('all_members','founding_members') then raise exception 'Invalid event audience'; end if;
  update public.events set audience=p_audience,updated_at=now() where id=p_event_id;
  if not found then raise exception 'Event not found'; end if;
end; $$;

create or replace function public.enforce_event_membership_audience()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if exists(select 1 from public.events where id=new.event_id and audience='founding_members')
     and not exists(select 1 from public.profiles where id=new.member_id and membership_state::text='active' and founding_member_sequence is not null)
  then raise exception 'This event is reserved for Founding Members'; end if;
  return new;
end; $$;
drop trigger if exists enforce_event_membership_audience_trigger on public.event_bookings;
create trigger enforce_event_membership_audience_trigger before insert or update of event_id,member_id on public.event_bookings for each row execute function public.enforce_event_membership_audience();

revoke all on function public.get_member_events() from public,anon;
revoke all on function public.list_events_for_management() from public,anon;
revoke all on function public.set_event_audience(uuid,text) from public,anon;
grant execute on function public.get_member_events() to authenticated;
grant execute on function public.list_events_for_management() to authenticated;
grant execute on function public.set_event_audience(uuid,text) to authenticated;

commit;

