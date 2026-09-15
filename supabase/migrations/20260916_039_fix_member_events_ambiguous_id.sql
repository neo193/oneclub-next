begin;

-- Migration 36 changed this RPC to PL/pgSQL and introduced an output column named
-- `id`. Qualify the profile lookup so PostgreSQL does not confuse that output
-- variable with profiles.id.
create or replace function public.get_member_events()
returns table(id uuid,title text,description text,venue text,starts_at timestamptz,booking_closes_at timestamptz,refund_cutoff_at timestamptz,capacity integer,price_paise integer,max_guests_per_member integer,pricing_model text,seats_available integer,audience text,can_book boolean)
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_founding boolean;
begin
  select p.founding_member_sequence is not null into v_founding
  from public.profiles p
  where p.id=auth.uid() and p.app_role::text='member' and p.membership_state::text='active';
  if not found then raise exception 'Active membership required'; end if;
  return query
  select e.id,e.title,e.description,e.venue,e.starts_at,e.booking_closes_at,e.refund_cutoff_at,e.capacity,e.price_paise,e.max_guests_per_member,e.pricing_model,
    greatest(0,e.capacity-coalesce(sum(b.seats) filter(where b.status='confirmed' or (b.status='pending_payment' and b.reservation_expires_at>now())),0)::integer),e.audience,
    (e.audience='all_members' or v_founding)
  from public.events e
  left join public.event_bookings b on b.event_id=e.id
  where e.status='published' and e.starts_at>now()
  group by e.id
  order by e.starts_at;
end; $$;

revoke all on function public.get_member_events() from public,anon;
grant execute on function public.get_member_events() to authenticated;

commit;
