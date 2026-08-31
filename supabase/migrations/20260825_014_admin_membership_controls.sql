begin;

alter table public.membership_terms add column if not exists payment_received_at timestamptz;

create or replace function public.get_member_membership_control(p_member_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_result jsonb;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then raise exception 'Administrator permission required'; end if;
  select jsonb_build_object(
    'member_id',p.id,'membership_state',p.membership_state,'plan',p.membership_plan,
    'founding_sequence',p.founding_member_sequence,'starts_at',p.membership_started_at,'expires_at',p.membership_expires_at,
    'founding_places_remaining',500-(select count(*) from public.profiles where founding_member_sequence is not null),
    'terms',coalesce((select jsonb_agg(jsonb_build_object(
      'id',t.id,'plan',t.plan,'source',t.source,'status',t.status,'starts_at',t.starts_at,'expires_at',t.expires_at,
      'amount_paise',t.amount_paise,'payment_method',t.payment_method,'transaction_reference',t.transaction_reference,
      'payment_received_at',t.payment_received_at,'reason',t.reason,'created_at',t.created_at
    ) order by t.created_at desc) from public.membership_terms t where t.member_id=p.id),'[]'::jsonb)
  ) into v_result from public.profiles p where p.id=p_member_id and p.app_role::text='member';
  if v_result is null then raise exception 'Member account not found'; end if;
  return v_result;
end;
$$;

create or replace function public.admin_cancel_membership(p_member_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_previous text;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then raise exception 'Administrator permission required'; end if;
  if char_length(trim(coalesce(p_reason,'')))<3 then raise exception 'Cancellation reason is required'; end if;
  select membership_state::text into v_previous from public.profiles where id=p_member_id and app_role::text='member' for update;
  if v_previous not in ('active','suspended','payment_pending') then raise exception 'This membership cannot be cancelled from its current state'; end if;
  update public.profiles set membership_state='cancelled',updated_at=now() where id=p_member_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'membership.cancelled','member',p_member_id::text,jsonb_build_object('previous_state',v_previous,'reason',trim(p_reason)));
end;
$$;

create or replace function public.admin_change_membership_expiry(p_member_id uuid,p_new_expiry timestamptz,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_old timestamptz; v_state text; v_plan text;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then raise exception 'Administrator permission required'; end if;
  if char_length(trim(coalesce(p_reason,'')))<3 then raise exception 'Reason is required'; end if;
  if p_new_expiry<=now() then raise exception 'The new expiry must be in the future'; end if;
  select membership_expires_at,membership_state::text,membership_plan into v_old,v_state,v_plan from public.profiles where id=p_member_id and app_role::text='member' for update;
  if v_plan<>'annual' or v_state not in ('active','suspended') then raise exception 'Only a current annual membership can have its expiry changed'; end if;
  update public.profiles set membership_expires_at=p_new_expiry,updated_at=now() where id=p_member_id;
  update public.membership_terms set expires_at=p_new_expiry,updated_at=now(),reason=concat_ws(E'\n',nullif(reason,''),'Expiry changed: '||trim(p_reason)) where member_id=p_member_id and status='active';
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'membership.expiry_changed','member',p_member_id::text,jsonb_build_object('previous_expiry',v_old,'new_expiry',p_new_expiry,'is_reduction',p_new_expiry<coalesce(v_old,p_new_expiry),'reason',trim(p_reason)));
end;
$$;

create or replace function public.admin_grant_complimentary_membership(p_member_id uuid,p_plan text,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_state text; v_existing_founder integer;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then raise exception 'Administrator permission required'; end if;
  if p_plan not in ('founding_lifetime','annual') then raise exception 'Select a valid membership plan'; end if;
  if char_length(trim(coalesce(p_reason,'')))<3 then raise exception 'Reason is required'; end if;
  select membership_state::text,founding_member_sequence into v_state,v_existing_founder from public.profiles where id=p_member_id and app_role::text='member' for update;
  if v_state<>'payment_pending' then raise exception 'Complimentary conversion is only available for payment-pending memberships'; end if;
  if v_existing_founder is not null and p_plan<>'founding_lifetime' then raise exception 'An allocated Founding Member cannot be converted to an annual plan'; end if;
  update public.profiles set pending_membership_plan=p_plan,pending_membership_source='complimentary',membership_state='active',updated_at=now() where id=p_member_id;
  update public.membership_terms set reason=trim(p_reason),amount_paise=0 where member_id=p_member_id and status='active';
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'membership.complimentary_granted','member',p_member_id::text,jsonb_build_object('plan',p_plan,'reason',trim(p_reason)));
end;
$$;

create or replace function public.admin_restore_membership(p_member_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_state text; v_plan text;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then raise exception 'Administrator permission required'; end if;
  if char_length(trim(coalesce(p_reason,'')))<3 then raise exception 'Reason is required'; end if;
  select membership_state::text,case when founding_member_sequence is not null then 'founding_lifetime' else 'annual' end into v_state,v_plan
  from public.profiles where id=p_member_id and app_role::text='member' for update;
  if v_state not in ('cancelled','expired') then raise exception 'Only a cancelled or expired membership can be restored'; end if;
  update public.profiles set pending_membership_plan=v_plan,pending_membership_source='complimentary',membership_state='active',updated_at=now() where id=p_member_id;
  update public.membership_terms set reason=trim(p_reason),amount_paise=0 where member_id=p_member_id and status='active';
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'membership.restored','member',p_member_id::text,jsonb_build_object('previous_state',v_state,'plan',v_plan,'reason',trim(p_reason)));
end;
$$;

create or replace function public.admin_record_offline_membership_payment(
  p_member_id uuid,p_plan text,p_amount_paise integer,p_payment_method text,
  p_transaction_reference text,p_payment_received_at timestamptz,p_reason text
)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_profile public.profiles; v_start timestamptz; v_expiry timestamptz; v_term_id uuid;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then raise exception 'Administrator permission required'; end if;
  if p_plan not in ('founding_lifetime','annual') then raise exception 'Select a valid membership plan'; end if;
  if p_amount_paise<=0 then raise exception 'Enter a payment amount greater than zero'; end if;
  if p_payment_method not in ('bank_transfer','upi','card_pos','cash','cheque','other') then raise exception 'Select a valid offline payment method'; end if;
  if char_length(trim(coalesce(p_transaction_reference,'')))<2 then raise exception 'Transaction reference is required'; end if;
  if p_payment_received_at is null or p_payment_received_at>now()+interval '5 minutes' then raise exception 'Enter a valid payment date'; end if;
  if char_length(trim(coalesce(p_reason,'')))<3 then raise exception 'Reason is required'; end if;
  select * into v_profile from public.profiles where id=p_member_id and app_role::text='member' for update;
  if not found then raise exception 'Member account not found'; end if;
  if v_profile.founding_member_sequence is not null then p_plan:='founding_lifetime'; end if;

  if v_profile.membership_state::text='active' then
    if v_profile.membership_plan<>'annual' then raise exception 'Lifetime memberships do not require renewal'; end if;
    if current_date<v_profile.membership_expires_at::date then raise exception 'Renewal is available on the final day of membership validity'; end if;
    v_start:=greatest(v_profile.membership_expires_at,now()); v_expiry:=v_start+interval '1 year';
    update public.membership_terms set status='superseded',updated_at=now() where member_id=p_member_id and status='active';
    insert into public.membership_terms(member_id,plan,source,status,starts_at,expires_at,amount_paise,payment_method,transaction_reference,payment_received_at,reason,created_by)
    values(p_member_id,'annual','offline','active',v_start,v_expiry,p_amount_paise,p_payment_method,trim(p_transaction_reference),p_payment_received_at,trim(p_reason),auth.uid()) returning id into v_term_id;
    update public.profiles set membership_plan='annual',membership_started_at=v_start,membership_expires_at=v_expiry,updated_at=now() where id=p_member_id;
  elsif v_profile.membership_state::text in ('payment_pending','cancelled','expired') then
    update public.profiles set pending_membership_plan=p_plan,pending_membership_source='offline',membership_state='active',updated_at=now() where id=p_member_id;
    update public.membership_terms set amount_paise=p_amount_paise,payment_method=p_payment_method,transaction_reference=trim(p_transaction_reference),payment_received_at=p_payment_received_at,reason=trim(p_reason)
    where member_id=p_member_id and status='active' returning id into v_term_id;
  else raise exception 'Offline membership payment cannot be recorded from the current account state';
  end if;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'membership.offline_payment_recorded','member',p_member_id::text,jsonb_build_object('term_id',v_term_id,'plan',p_plan,'amount_paise',p_amount_paise,'payment_method',p_payment_method,'transaction_reference',trim(p_transaction_reference),'payment_received_at',p_payment_received_at,'reason',trim(p_reason)));
end;
$$;

revoke all on function public.get_member_membership_control(uuid) from public,anon;
revoke all on function public.admin_cancel_membership(uuid,text) from public,anon;
revoke all on function public.admin_change_membership_expiry(uuid,timestamptz,text) from public,anon;
revoke all on function public.admin_grant_complimentary_membership(uuid,text,text) from public,anon;
revoke all on function public.admin_restore_membership(uuid,text) from public,anon;
revoke all on function public.admin_record_offline_membership_payment(uuid,text,integer,text,text,timestamptz,text) from public,anon;
grant execute on function public.get_member_membership_control(uuid) to authenticated;
grant execute on function public.admin_cancel_membership(uuid,text) to authenticated;
grant execute on function public.admin_change_membership_expiry(uuid,timestamptz,text) to authenticated;
grant execute on function public.admin_grant_complimentary_membership(uuid,text,text) to authenticated;
grant execute on function public.admin_restore_membership(uuid,text) to authenticated;
grant execute on function public.admin_record_offline_membership_payment(uuid,text,integer,text,text,timestamptz,text) to authenticated;

commit;
