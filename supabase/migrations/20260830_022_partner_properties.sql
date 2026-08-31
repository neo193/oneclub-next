begin;

create table if not exists public.partner_properties (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete restrict,
  name text not null check(char_length(trim(name)) between 2 and 160),
  slug text not null check(slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  address text not null check(char_length(trim(address)) between 3 and 500),
  status text not null default 'draft' check(status in ('draft','active','inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(partner_id,slug)
);

create index if not exists partner_properties_partner_status_idx on public.partner_properties(partner_id,status);
alter table public.partner_properties enable row level security;
revoke all on table public.partner_properties from public,anon,authenticated;

create or replace function public.can_manage_partner_content()
returns boolean
language sql stable security definer set search_path=public,pg_temp
as $$
  select exists(
    select 1 from public.profiles
    where id=auth.uid()
      and (app_role::text='admin' or (app_role::text='staff' and staff_role::text='general'))
  );
$$;

create or replace function public.list_partner_properties_for_management()
returns jsonb
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_result jsonb;
begin
  if not public.can_manage_partner_content() then raise exception 'Partner and benefit management permission required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',pp.id,'partner_id',pp.partner_id,'partner_name',p.name,'name',pp.name,
    'slug',pp.slug,'address',pp.address,'status',pp.status,'created_at',pp.created_at,'updated_at',pp.updated_at
  ) order by p.name,pp.name),'[]'::jsonb)
  into v_result
  from public.partner_properties pp join public.partners p on p.id=pp.partner_id;
  return v_result;
end;
$$;

create or replace function public.save_partner_property(
  p_id uuid,p_partner_id uuid,p_name text,p_slug text,p_address text,p_status text
)
returns uuid
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_id uuid; v_action text;
begin
  if not public.can_manage_partner_content() then raise exception 'Partner and benefit management permission required'; end if;
  if not exists(select 1 from public.partners where id=p_partner_id) then raise exception 'Partner not found'; end if;
  if char_length(trim(coalesce(p_name,''))) not between 2 and 160 then raise exception 'Property name must be between 2 and 160 characters'; end if;
  if coalesce(p_slug,'') !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then raise exception 'Property slug is invalid'; end if;
  if char_length(trim(coalesce(p_address,''))) not between 3 and 500 then raise exception 'Property address is required'; end if;
  if p_status not in ('draft','active','inactive') then raise exception 'Property status is invalid'; end if;

  if p_id is null then
    insert into public.partner_properties(partner_id,name,slug,address,status)
    values(p_partner_id,trim(p_name),p_slug,trim(p_address),p_status) returning id into v_id;
    v_action:='partner_property.created';
  else
    update public.partner_properties set partner_id=p_partner_id,name=trim(p_name),slug=p_slug,
      address=trim(p_address),status=p_status,updated_at=now() where id=p_id returning id into v_id;
    if v_id is null then raise exception 'Property not found'; end if;
    v_action:='partner_property.updated';
  end if;

  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),v_action,'partner_property',v_id::text,jsonb_build_object('partner_id',p_partner_id,'status',p_status));
  return v_id;
exception when unique_violation then
  raise exception 'This partner already has a property using that slug';
end;
$$;

create or replace function public.check_partner_deletion(p_id uuid)
returns jsonb
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_name text; v_benefits integer; v_properties integer;
begin
  if not public.can_manage_partner_content() then raise exception 'Partner and benefit management permission required'; end if;
  select name into v_name from public.partners where id=p_id;
  if v_name is null then raise exception 'Partner not found'; end if;
  select count(*) into v_benefits from public.benefits where partner_id=p_id;
  select count(*) into v_properties from public.partner_properties where partner_id=p_id;
  return jsonb_build_object(
    'allowed',v_benefits=0 and v_properties=0,
    'confirmation_value',v_name,
    'message',case
      when v_benefits>0 and v_properties>0 then format('This partner still has %s benefit%s and %s propert%s. Remove those records before deleting the partner.',v_benefits,case when v_benefits=1 then '' else 's' end,v_properties,case when v_properties=1 then 'y' else 'ies' end)
      when v_benefits>0 then format('This partner still has %s benefit%s. Delete or reassign those benefits before deleting the partner.',v_benefits,case when v_benefits=1 then '' else 's' end)
      when v_properties>0 then format('This partner still has %s propert%s. Remove those properties before deleting the partner.',v_properties,case when v_properties=1 then 'y' else 'ies' end)
      else null end
  );
end;
$$;

create or replace function public.delete_partner(p_id uuid)
returns void
language plpgsql security definer set search_path=public,pg_temp
as $$
begin
  if not public.can_manage_partner_content() then raise exception 'Partner and benefit management permission required'; end if;
  if exists(select 1 from public.benefits where partner_id=p_id) then raise exception 'Delete or reassign this partner''s benefits before deleting the partner.'; end if;
  if exists(select 1 from public.partner_properties where partner_id=p_id) then raise exception 'Remove this partner''s properties before deleting the partner.'; end if;
  delete from public.partners where id=p_id;
  if not found then raise exception 'Partner not found'; end if;
end;
$$;

revoke all on function public.can_manage_partner_content() from public,anon;
revoke all on function public.list_partner_properties_for_management() from public,anon;
revoke all on function public.save_partner_property(uuid,uuid,text,text,text,text) from public,anon;
revoke all on function public.check_partner_deletion(uuid) from public,anon;
grant execute on function public.list_partner_properties_for_management() to authenticated;
grant execute on function public.save_partner_property(uuid,uuid,text,text,text,text) to authenticated;
grant execute on function public.check_partner_deletion(uuid) to authenticated;

commit;
