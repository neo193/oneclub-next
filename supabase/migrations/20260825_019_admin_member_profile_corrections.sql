begin;

create or replace function public.admin_update_member_profile(p_member_id uuid,p_full_name text,p_phone text,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_old public.profiles; v_new public.profiles; v_fields text[]:='{}'; v_phone text;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then raise exception 'Administrator permission required'; end if;
  if char_length(trim(coalesce(p_full_name,''))) not between 2 and 100 then raise exception 'Display name must be between 2 and 100 characters'; end if;
  v_phone:=nullif(trim(coalesce(p_phone,'')),'');
  if v_phone is not null and (char_length(v_phone)>30 or v_phone !~ '^[0-9+() .-]{7,30}$') then raise exception 'Enter a valid phone number'; end if;
  if char_length(trim(coalesce(p_reason,''))) not between 3 and 500 then raise exception 'Reason must be between 3 and 500 characters'; end if;
  select * into v_old from public.profiles where id=p_member_id and app_role::text='member' for update;
  if not found then raise exception 'Member account not found'; end if;
  if v_old.full_name is distinct from trim(p_full_name) then v_fields:=array_append(v_fields,'full_name'); end if;
  if v_old.phone is distinct from v_phone then v_fields:=array_append(v_fields,'phone'); end if;
  if cardinality(v_fields)=0 then raise exception 'No profile changes were provided'; end if;
  update public.profiles set full_name=trim(p_full_name),phone=v_phone,updated_at=now() where id=p_member_id returning * into v_new;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'member.profile_corrected','member',p_member_id::text,jsonb_build_object('changed_fields',v_fields,'reason',trim(p_reason)));
  return jsonb_build_object('full_name',v_new.full_name,'phone',v_new.phone,'updated_at',v_new.updated_at);
end;
$$;

revoke all on function public.admin_update_member_profile(uuid,text,text,text) from public,anon;
grant execute on function public.admin_update_member_profile(uuid,text,text,text) to authenticated;

commit;
