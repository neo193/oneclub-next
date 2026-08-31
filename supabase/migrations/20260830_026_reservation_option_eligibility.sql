begin;

create or replace function public.get_member_reservation_options()
returns jsonb
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_result jsonb;
begin
  if not exists(
    select 1 from public.profiles
    where id=auth.uid() and app_role::text='member' and membership_state::text='active'
  ) then
    raise exception 'Active membership is required to create a reservation';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'property_id',pp.id,
    'partner_id',p.id,
    'partner_name',p.name,
    'property_name',pp.name,
    'address',pp.address,
    'is_primary',pp.is_primary
  ) order by p.name,pp.is_primary desc,pp.name),'[]'::jsonb)
  into v_result
  from public.partner_properties pp
  join public.partners p on p.id=pp.partner_id
  where pp.status='active'
    and p.status::text='active'
    and nullif(trim(pp.reservation_email),'') is not null
    and exists(
      select 1 from public.benefits b
      where b.partner_id=p.id and b.status::text='active'
    );

  return v_result;
end;
$$;

revoke all on function public.get_member_reservation_options() from public,anon;
grant execute on function public.get_member_reservation_options() to authenticated;

commit;
