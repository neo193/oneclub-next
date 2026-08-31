begin;

create or replace function public.admin_record_offline_membership_payment(
  p_member_id uuid,p_plan text,p_amount_paise integer,p_payment_method text,
  p_transaction_reference text,p_payment_received_at timestamptz,p_reason text
)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_profile public.profiles; v_start timestamptz; v_expiry timestamptz; v_term_id uuid; v_reference text;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then raise exception 'Administrator permission required'; end if;
  if p_plan not in ('founding_lifetime','annual') then raise exception 'Select a valid membership plan'; end if;
  if p_amount_paise<=0 then raise exception 'Enter a payment amount greater than zero'; end if;
  if p_payment_method not in ('bank_transfer','upi','card_pos','cash','cheque','other') then raise exception 'Select a valid offline payment method'; end if;
  v_reference:=nullif(trim(coalesce(p_transaction_reference,'')),'');
  if p_payment_method in ('bank_transfer','upi','card_pos','cheque') and v_reference is null then raise exception 'Transaction reference is required for this payment method'; end if;
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
    values(p_member_id,'annual','offline','active',v_start,v_expiry,p_amount_paise,p_payment_method,v_reference,p_payment_received_at,trim(p_reason),auth.uid()) returning id into v_term_id;
    update public.profiles set membership_plan='annual',membership_started_at=v_start,membership_expires_at=v_expiry,updated_at=now() where id=p_member_id;
  elsif v_profile.membership_state::text in ('payment_pending','cancelled','expired') then
    update public.profiles set pending_membership_plan=p_plan,pending_membership_source='offline',membership_state='active',updated_at=now() where id=p_member_id;
    update public.membership_terms set amount_paise=p_amount_paise,payment_method=p_payment_method,transaction_reference=v_reference,payment_received_at=p_payment_received_at,reason=trim(p_reason)
    where member_id=p_member_id and status='active' returning id into v_term_id;
  else raise exception 'Offline membership payment cannot be recorded from the current account state';
  end if;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'membership.offline_payment_recorded','member',p_member_id::text,jsonb_build_object('term_id',v_term_id,'plan',p_plan,'amount_paise',p_amount_paise,'payment_method',p_payment_method,'transaction_reference',v_reference,'payment_received_at',p_payment_received_at,'reason',trim(p_reason)));
end;
$$;

revoke all on function public.admin_record_offline_membership_payment(uuid,text,integer,text,text,timestamptz,text) from public,anon;
grant execute on function public.admin_record_offline_membership_payment(uuid,text,integer,text,text,timestamptz,text) to authenticated;

commit;
