begin;

create or replace function public.get_pending_refund_count()
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  pending_count bigint;
begin
  if not exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and (
        app_role::text = 'admin'
        or (app_role::text = 'staff' and staff_role::text = 'technical')
      )
  ) then
    raise exception 'Technical diagnostics permission required';
  end if;

  select count(*)
  into pending_count
  from public.event_bookings
  where status::text = 'cancelled'
    and payment_status::text = 'refund_pending';

  return pending_count;
end;
$$;

revoke all on function public.get_pending_refund_count() from public, anon;
grant execute on function public.get_pending_refund_count() to authenticated;

commit;
