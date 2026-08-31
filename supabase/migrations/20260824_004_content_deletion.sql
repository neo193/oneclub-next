begin;

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
