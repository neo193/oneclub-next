begin;

create or replace function public.expire_my_event_reservations()
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_count integer;
begin
  update public.event_bookings
  set status='cancelled',cancelled_at=coalesce(cancelled_at,reservation_expires_at,now()),updated_at=now()
  where member_id=auth.uid() and status='pending_payment' and payment_status='unpaid'
    and reservation_expires_at is not null and reservation_expires_at<=now();
  get diagnostics v_count=row_count;
  return v_count;
end; $$;

drop function if exists public.get_my_event_bookings();
create function public.get_my_event_bookings()
returns table(
  booking_id uuid,event_id uuid,title text,venue text,starts_at timestamptz,
  guest_names text[],seats integer,status text,amount_paise integer,payment_status text,
  reservation_expires_at timestamptz,cancelled_at timestamptz,can_cancel boolean,refund_eligible boolean
)
language sql security definer set search_path=public,pg_temp as $$
select b.id,e.id,e.title,e.venue,e.starts_at,
  array(select g.guest_name from public.booking_guests g where g.booking_id=b.id order by g.position),
  b.seats,b.status,b.amount_paise,b.payment_status,b.reservation_expires_at,b.cancelled_at,
  (b.status in ('pending_payment','confirmed') and now()<e.starts_at),
  (b.payment_status='paid' and now()<=e.refund_cutoff_at)
from public.event_bookings b
join public.events e on e.id=b.event_id
where b.member_id=auth.uid();
$$;

revoke all on function public.expire_my_event_reservations() from public,anon;
revoke all on function public.get_my_event_bookings() from public,anon;
grant execute on function public.expire_my_event_reservations() to authenticated;
grant execute on function public.get_my_event_bookings() to authenticated;

commit;
