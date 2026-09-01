begin;

create or replace function public.get_active_member_benefit_catalogue()
returns table(
  category text,
  benefit_title text,
  partner_name text,
  location text,
  benefit_description text,
  redemption_instructions text,
  terms text,
  locations jsonb
)
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  if not exists(
    select 1 from public.profiles
    where id=auth.uid() and membership_state::text='active'
  ) then
    raise exception 'An active membership is required';
  end if;

  return query
  select
    p.category::text,
    b.title,
    p.name,
    p.location,
    b.description,
    b.redemption_instructions,
    b.terms,
    case
      when exists(select 1 from public.partner_properties x where x.partner_id=p.id and not x.is_primary)
      then coalesce((
        select jsonb_agg(jsonb_build_object('id',pp.id,'name',pp.name,'address',pp.address) order by pp.name)
        from public.partner_properties pp
        where pp.partner_id=p.id and not pp.is_primary and pp.status='active'
      ),'[]'::jsonb)
      else '[]'::jsonb
    end
  from public.partners p
  join public.benefits b on b.partner_id=p.id
  where p.status::text='active' and b.status::text='active'
  order by p.category,p.name;
end;
$$;

revoke all on function public.get_active_member_benefit_catalogue() from public,anon;
grant execute on function public.get_active_member_benefit_catalogue() to authenticated;

commit;
