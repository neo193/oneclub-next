begin;

alter table public.events
  add column if not exists max_guests_per_member integer not null default 1,
  add column if not exists pricing_model text not null default 'per_person';

do $$
begin
  if not exists (select 1 from pg_constraint where conname='events_max_guests_valid' and conrelid='public.events'::regclass) then
    alter table public.events add constraint events_max_guests_valid check (max_guests_per_member between 0 and 20);
  end if;
  if not exists (select 1 from pg_constraint where conname='events_pricing_model_valid' and conrelid='public.events'::regclass) then
    alter table public.events add constraint events_pricing_model_valid check (pricing_model in ('per_person','fixed_booking'));
  end if;
end $$;

drop function if exists public.list_events_for_management();
create function public.list_events_for_management()
returns table(
  id uuid,title text,description text,venue text,starts_at timestamptz,
  booking_closes_at timestamptz,refund_cutoff_at timestamptz,capacity integer,
  price_paise integer,max_guests_per_member integer,pricing_model text,status text,
  booked_seats integer,held_seats integer
)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.can_manage_events() then raise exception 'Event management permission required'; end if;
  return query
  select e.id,e.title,e.description,e.venue,e.starts_at,e.booking_closes_at,e.refund_cutoff_at,
    e.capacity,e.price_paise,e.max_guests_per_member,e.pricing_model,e.status,
    coalesce(sum(b.seats) filter(where b.status='confirmed'),0)::integer,
    coalesce(sum(b.seats) filter(where b.status='pending_payment' and b.reservation_expires_at>now()),0)::integer
  from public.events e
  left join public.event_bookings b on b.event_id=e.id
  group by e.id
  order by e.starts_at desc;
end; $$;

drop function if exists public.save_event(uuid,text,text,text,timestamptz,timestamptz,timestamptz,integer,integer,text);
drop function if exists public.save_event(uuid,text,text,text,timestamptz,timestamptz,timestamptz,integer,integer,integer,text,text,text);
create function public.save_event(
  p_id uuid,p_title text,p_description text,p_venue text,p_starts_at timestamptz,
  p_booking_closes_at timestamptz,p_refund_cutoff_at timestamptz,p_capacity integer,
  p_price_paise integer,p_max_guests_per_member integer,p_pricing_model text,p_status text,
  p_capacity_change_reason text default null
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_id uuid;
  v_committed integer;
  v_previous public.events;
begin
  if not public.can_manage_events() then raise exception 'Event management permission required'; end if;
  if char_length(trim(p_title))<3 or char_length(trim(p_description))<10 or char_length(trim(p_venue))<3 then raise exception 'Please complete the event details'; end if;
  if p_status not in ('draft','published','cancelled','completed') then raise exception 'Invalid event status'; end if;
  if p_pricing_model not in ('per_person','fixed_booking') then raise exception 'Invalid pricing method'; end if;
  if p_capacity<1 or p_capacity>10000 or p_price_paise<0 then raise exception 'Capacity or price is invalid'; end if;
  if p_max_guests_per_member<0 or p_max_guests_per_member>20 then raise exception 'Guest limit must be between 0 and 20'; end if;
  if not (p_refund_cutoff_at<=p_booking_closes_at and p_booking_closes_at<p_starts_at) then raise exception 'The refund cutoff must precede booking close, which must precede the event'; end if;

  if p_id is null then
    insert into public.events(title,description,venue,starts_at,booking_closes_at,refund_cutoff_at,capacity,price_paise,max_guests_per_member,pricing_model,status)
    values(trim(p_title),trim(p_description),trim(p_venue),p_starts_at,p_booking_closes_at,p_refund_cutoff_at,p_capacity,p_price_paise,p_max_guests_per_member,p_pricing_model,p_status)
    returning id into v_id;
    insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'event.created','event',v_id::text,jsonb_build_object(
      'title',trim(p_title),'status',p_status,'capacity',p_capacity,
      'max_guests_per_member',p_max_guests_per_member,'pricing_model',p_pricing_model,'price_paise',p_price_paise
    ));
  else
    select * into v_previous from public.events where id=p_id for update;
    if not found then raise exception 'Event not found'; end if;

    select coalesce(sum(seats),0)::integer into v_committed
    from public.event_bookings
    where event_id=p_id and (status='confirmed' or (status='pending_payment' and reservation_expires_at>now()));
    if p_capacity<v_committed then raise exception 'Capacity cannot be lower than % committed seats',v_committed; end if;
    if v_previous.status='published' and p_capacity<>v_previous.capacity and nullif(trim(p_capacity_change_reason),'') is null then
      raise exception 'Enter a reason for changing the capacity of a published event';
    end if;

    update public.events set
      title=trim(p_title),description=trim(p_description),venue=trim(p_venue),starts_at=p_starts_at,
      booking_closes_at=p_booking_closes_at,refund_cutoff_at=p_refund_cutoff_at,capacity=p_capacity,
      price_paise=p_price_paise,max_guests_per_member=p_max_guests_per_member,pricing_model=p_pricing_model,
      status=p_status,updated_at=now()
    where id=p_id returning id into v_id;

    insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'event.updated','event',v_id::text,jsonb_build_object(
      'title',trim(p_title),'status',p_status,
      'previous_capacity',v_previous.capacity,'capacity',p_capacity,
      'capacity_change_reason',nullif(trim(p_capacity_change_reason),''),
      'previous_max_guests_per_member',v_previous.max_guests_per_member,'max_guests_per_member',p_max_guests_per_member,
      'previous_pricing_model',v_previous.pricing_model,'pricing_model',p_pricing_model,
      'previous_price_paise',v_previous.price_paise,'price_paise',p_price_paise
    ));
  end if;
  return v_id;
end; $$;

revoke all on function public.list_events_for_management() from public,anon;
revoke all on function public.save_event(uuid,text,text,text,timestamptz,timestamptz,timestamptz,integer,integer,integer,text,text,text) from public,anon;
grant execute on function public.list_events_for_management() to authenticated;
grant execute on function public.save_event(uuid,text,text,text,timestamptz,timestamptz,timestamptz,integer,integer,integer,text,text,text) to authenticated;

commit;
