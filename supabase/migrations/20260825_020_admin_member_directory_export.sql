begin;

create or replace function public.export_members_for_management()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_result jsonb;
begin
  if not public.can_manage_members() then
    raise exception 'Member management permission required';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,
    'member_number',p.member_number,
    'full_name',p.full_name,
    'email',u.email,
    'membership_state',p.membership_state,
    'account_created_at',u.created_at,
    'locality',p.locality,
    'profession',p.profession,
    'industry',p.industry
  ) order by coalesce(p.full_name,u.email)), '[]'::jsonb)
  into v_result
  from public.profiles p
  join auth.users u on u.id=p.id
  where p.app_role::text='member';

  return v_result;
end;
$$;

revoke all on function public.export_members_for_management() from public,anon;
grant execute on function public.export_members_for_management() to authenticated;

commit;
