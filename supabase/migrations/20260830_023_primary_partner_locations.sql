begin;

alter table public.partner_properties add column if not exists is_primary boolean not null default false;
create unique index if not exists partner_properties_one_primary_idx on public.partner_properties(partner_id) where is_primary;

insert into public.partner_properties(partner_id,name,slug,address,status,is_primary)
select p.id,p.name,'primary-location',p.location,
  case when p.status::text='active' then 'active' when p.status::text='inactive' then 'inactive' else 'draft' end,
  true
from public.partners p
where not exists(select 1 from public.partner_properties pp where pp.partner_id=p.id and pp.is_primary);

create or replace function public.sync_partner_primary_property()
returns trigger
language plpgsql security definer set search_path=public,pg_temp
as $$
begin
  update public.partner_properties set
    name=new.name,address=new.location,
    status=case when new.status::text='active' then 'active' when new.status::text='inactive' then 'inactive' else 'draft' end,
    updated_at=now()
  where partner_id=new.id and is_primary;
  if not found then
    insert into public.partner_properties(partner_id,name,slug,address,status,is_primary)
    values(new.id,new.name,'primary-location',new.location,
      case when new.status::text='active' then 'active' when new.status::text='inactive' then 'inactive' else 'draft' end,true);
  end if;
  return new;
end;
$$;

drop trigger if exists sync_partner_primary_property_trigger on public.partners;
create trigger sync_partner_primary_property_trigger
after insert or update of name,location,status on public.partners
for each row execute function public.sync_partner_primary_property();

create or replace function public.list_partner_properties_for_management()
returns jsonb
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_result jsonb;
begin
  if not public.can_manage_partner_content() then raise exception 'Partner and benefit management permission required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',pp.id,'partner_id',pp.partner_id,'partner_name',p.name,'name',pp.name,
    'slug',pp.slug,'address',pp.address,'status',pp.status,'is_primary',pp.is_primary,
    'created_at',pp.created_at,'updated_at',pp.updated_at
  ) order by p.name,pp.is_primary desc,pp.name),'[]'::jsonb)
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
  if p_id is not null and exists(select 1 from public.partner_properties where id=p_id and is_primary) then raise exception 'Edit the partner form to change its primary location'; end if;
  if char_length(trim(coalesce(p_name,''))) not between 2 and 160 then raise exception 'Location name must be between 2 and 160 characters'; end if;
  if coalesce(p_slug,'') !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then raise exception 'Location slug is invalid'; end if;
  if char_length(trim(coalesce(p_address,''))) not between 3 and 500 then raise exception 'Location address is required'; end if;
  if p_status not in ('draft','active','inactive') then raise exception 'Location status is invalid'; end if;
  if p_id is null then
    insert into public.partner_properties(partner_id,name,slug,address,status,is_primary)
    values(p_partner_id,trim(p_name),p_slug,trim(p_address),p_status,false) returning id into v_id;
    v_action:='partner_property.created';
  else
    update public.partner_properties set partner_id=p_partner_id,name=trim(p_name),slug=p_slug,
      address=trim(p_address),status=p_status,updated_at=now() where id=p_id and not is_primary returning id into v_id;
    if v_id is null then raise exception 'Additional location not found'; end if;
    v_action:='partner_property.updated';
  end if;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),v_action,'partner_property',v_id::text,jsonb_build_object('partner_id',p_partner_id,'status',p_status));
  return v_id;
exception when unique_violation then raise exception 'This partner already has a location using that slug';
end;
$$;

create or replace function public.delete_partner_property(p_id uuid)
returns void
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_partner_id uuid; v_name text;
begin
  if not public.can_manage_partner_content() then raise exception 'Partner and benefit management permission required'; end if;
  select partner_id,name into v_partner_id,v_name from public.partner_properties where id=p_id and not is_primary;
  if v_partner_id is null then raise exception 'Additional location not found'; end if;
  delete from public.partner_properties where id=p_id and not is_primary;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'partner_property.deleted','partner_property',p_id::text,jsonb_build_object('partner_id',v_partner_id,'name',v_name));
end;
$$;

create or replace function public.check_partner_deletion(p_id uuid)
returns jsonb
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_name text; v_benefits integer; v_locations integer;
begin
  if not public.can_manage_partner_content() then raise exception 'Partner and benefit management permission required'; end if;
  select name into v_name from public.partners where id=p_id;
  if v_name is null then raise exception 'Partner not found'; end if;
  select count(*) into v_benefits from public.benefits where partner_id=p_id;
  select count(*) into v_locations from public.partner_properties where partner_id=p_id and not is_primary;
  return jsonb_build_object(
    'allowed',v_benefits=0 and v_locations=0,'confirmation_value',v_name,
    'message',case
      when v_benefits>0 and v_locations>0 then format('This partner still has %s benefit%s and %s additional location%s. Remove those records before deleting the partner.',v_benefits,case when v_benefits=1 then '' else 's' end,v_locations,case when v_locations=1 then '' else 's' end)
      when v_benefits>0 then format('This partner still has %s benefit%s. Delete or reassign those benefits before deleting the partner.',v_benefits,case when v_benefits=1 then '' else 's' end)
      when v_locations>0 then format('This partner still has %s additional location%s. Remove those locations before deleting the partner.',v_locations,case when v_locations=1 then '' else 's' end)
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
  if exists(select 1 from public.partner_properties where partner_id=p_id and not is_primary) then raise exception 'Remove this partner''s additional locations before deleting the partner.'; end if;
  delete from public.partner_properties where partner_id=p_id and is_primary;
  delete from public.partners where id=p_id;
  if not found then raise exception 'Partner not found'; end if;
end;
$$;

revoke all on function public.delete_partner_property(uuid) from public,anon;
grant execute on function public.delete_partner_property(uuid) to authenticated;

commit;
