begin;

drop function if exists public.admin_restore_cancelled_membership_offer(uuid,text);
create function public.admin_restore_cancelled_membership_offer(p_member_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_state text; v_deadline timestamptz;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then raise exception 'Administrator permission required'; end if;
  if char_length(trim(coalesce(p_reason,'')))<3 then raise exception 'Restoration reason is required'; end if;
  perform 1 from public.profiles where id=p_member_id and app_role::text='member' and membership_state::text='cancelled' for update;
  if not found then raise exception 'Only a cancelled membership offer can be restored'; end if;

  update public.profiles
  set membership_state='payment_pending',payment_offer_expires_at=now()+interval '30 days',
      pending_membership_plan=null,pending_membership_source=null,updated_at=now()
  where id=p_member_id
  returning membership_state::text,payment_offer_expires_at into v_state,v_deadline;

  if v_state<>'payment_pending' or v_deadline is null or v_deadline<=now() then
    raise exception 'The restored payment window could not be verified';
  end if;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'membership.offer_restored','member',p_member_id::text,jsonb_build_object('payment_window_days',30,'payment_offer_expires_at',v_deadline,'reason',trim(p_reason)));
  return jsonb_build_object('membership_state',v_state,'payment_offer_expires_at',v_deadline);
end;
$$;

drop function if exists public.admin_reopen_expired_membership_for_payment(uuid,text);
create function public.admin_reopen_expired_membership_for_payment(p_member_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_state text; v_deadline timestamptz;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then raise exception 'Administrator permission required'; end if;
  if char_length(trim(coalesce(p_reason,'')))<3 then raise exception 'Reason is required'; end if;
  perform 1 from public.profiles where id=p_member_id and app_role::text='member' and membership_state::text='expired' for update;
  if not found then raise exception 'Only an expired membership can be reopened for payment'; end if;

  update public.profiles
  set membership_state='payment_pending',payment_offer_expires_at=now()+interval '30 days',
      pending_membership_plan=null,pending_membership_source=null,updated_at=now()
  where id=p_member_id
  returning membership_state::text,payment_offer_expires_at into v_state,v_deadline;

  if v_state<>'payment_pending' or v_deadline is null or v_deadline<=now() then
    raise exception 'The reopened payment window could not be verified';
  end if;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'membership.expired_reopened_for_payment','member',p_member_id::text,jsonb_build_object('payment_window_days',30,'payment_offer_expires_at',v_deadline,'reason',trim(p_reason)));
  return jsonb_build_object('membership_state',v_state,'payment_offer_expires_at',v_deadline);
end;
$$;

revoke all on function public.admin_restore_cancelled_membership_offer(uuid,text) from public,anon;
revoke all on function public.admin_reopen_expired_membership_for_payment(uuid,text) from public,anon;
grant execute on function public.admin_restore_cancelled_membership_offer(uuid,text) to authenticated;
grant execute on function public.admin_reopen_expired_membership_for_payment(uuid,text) to authenticated;

commit;
