-- Permission-controlled per-event booking export for the staff event workspace.

create or replace function public.export_event_bookings_for_management(p_event_id uuid)
returns table(
  booking_id uuid,
  member_number text,
  member_name text,
  member_email text,
  guest_names text[],
  seats integer,
  booking_status text,
  payment_status text,
  booking_source text,
  amount_paise integer,
  booked_at timestamptz
)
language plpgsql
security definer
set search_path=public,auth,pg_temp
as $$
begin
  if not public.can_manage_events() then
    raise exception 'Event management permission required';
  end if;
  if not exists(select 1 from public.events where id=p_event_id and status='published') then
    raise exception 'Only published events can be exported';
  end if;

  return query
  select b.id,p.member_number,p.full_name,u.email::text,
    array(select g.guest_name from public.booking_guests g where g.booking_id=b.id order by g.position),
    b.seats,b.status::text,b.payment_status::text,b.booking_source::text,b.amount_paise,b.booked_at
  from public.event_bookings b
  join public.profiles p on p.id=b.member_id
  join auth.users u on u.id=b.member_id
  where b.event_id=p_event_id and b.status in ('confirmed','pending_payment')
  order by b.status,b.booked_at,p.full_name;
end;
$$;

revoke all on function public.export_event_bookings_for_management(uuid) from public,anon;
grant execute on function public.export_event_bookings_for_management(uuid) to authenticated;
