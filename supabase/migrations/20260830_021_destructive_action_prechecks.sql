begin;

create or replace function public.check_event_deletion(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_title text;
  v_bookings integer;
begin
  if not exists (
    select 1 from public.profiles
    where id=auth.uid()
      and (app_role::text='admin' or (app_role::text='staff' and staff_role::text='marketing'))
  ) then raise exception 'Event management permission required'; end if;

  select title into v_title from public.events where id=p_id;
  if v_title is null then raise exception 'Event not found'; end if;
  select count(*) into v_bookings from public.event_bookings where event_id=p_id;

  return jsonb_build_object(
    'allowed',v_bookings=0,
    'confirmation_value',v_title,
    'message',case when v_bookings>0 then
      format('This event has %s booking record%s and cannot be permanently deleted. Mark it cancelled instead.',v_bookings,case when v_bookings=1 then '' else 's' end)
      else null end
  );
end;
$$;

create or replace function public.check_partner_deletion(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_name text;
  v_benefits integer;
begin
  if not exists (
    select 1 from public.profiles
    where id=auth.uid()
      and (app_role::text='admin' or (app_role::text='staff' and staff_role::text='general'))
  ) then raise exception 'Partner and benefit management permission required'; end if;

  select name into v_name from public.partners where id=p_id;
  if v_name is null then raise exception 'Partner not found'; end if;
  select count(*) into v_benefits from public.benefits where partner_id=p_id;

  return jsonb_build_object(
    'allowed',v_benefits=0,
    'confirmation_value',v_name,
    'message',case when v_benefits>0 then
      format('This partner still has %s benefit%s. Delete or reassign those benefits before deleting the partner.',v_benefits,case when v_benefits=1 then '' else 's' end)
      else null end
  );
end;
$$;

revoke all on function public.check_event_deletion(uuid) from public,anon;
revoke all on function public.check_partner_deletion(uuid) from public,anon;
grant execute on function public.check_event_deletion(uuid) to authenticated;
grant execute on function public.check_partner_deletion(uuid) to authenticated;

commit;
