begin;

alter table public.profiles add column if not exists payment_offer_expires_at timestamptz;
update public.profiles set payment_offer_expires_at=now()+interval '30 days'
where membership_state::text='payment_pending' and payment_offer_expires_at is null;

create or replace function public.set_membership_payment_window()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if new.membership_state::text='payment_pending' and old.membership_state::text<>'payment_pending' then
    new.payment_offer_expires_at:=now()+interval '30 days';
  elsif new.membership_state::text<>'payment_pending' then
    new.payment_offer_expires_at:=null;
  end if;
  return new;
end;
$$;
drop trigger if exists set_membership_payment_window_trigger on public.profiles;
create trigger set_membership_payment_window_trigger before update of membership_state on public.profiles
for each row execute function public.set_membership_payment_window();

create or replace function public.process_membership_lifecycle()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_expired integer:=0; v_cancelled integer:=0; v_row record;
begin
  for v_row in
    select id,membership_expires_at from public.profiles
    where app_role::text='member' and membership_plan='annual' and membership_state::text in ('active','suspended')
      and membership_expires_at is not null and membership_expires_at<=now() for update
  loop
    update public.membership_terms set status='expired',updated_at=now()
      where member_id=v_row.id and status='active';
    update public.profiles set membership_state='payment_pending',updated_at=now() where id=v_row.id;
    insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
    values(null,'membership.renewal_payment_opened','member',v_row.id::text,jsonb_build_object('expired_at',v_row.membership_expires_at,'payment_window_days',30));
    v_expired:=v_expired+1;
  end loop;

  for v_row in
    select id,payment_offer_expires_at from public.profiles
    where app_role::text='member' and membership_state::text='payment_pending'
      and payment_offer_expires_at is not null and payment_offer_expires_at<=now() for update
  loop
    update public.profiles set membership_state='cancelled',updated_at=now() where id=v_row.id;
    insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
    values(null,'membership.payment_offer_expired','member',v_row.id::text,jsonb_build_object('offer_expired_at',v_row.payment_offer_expires_at));
    v_cancelled:=v_cancelled+1;
  end loop;
  return jsonb_build_object('renewal_windows_opened',v_expired,'expired_offers_cancelled',v_cancelled,'processed_at',now());
end;
$$;

create or replace function public.admin_restore_cancelled_membership_offer(p_member_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then raise exception 'Administrator permission required'; end if;
  if char_length(trim(coalesce(p_reason,'')))<3 then raise exception 'Restoration reason is required'; end if;
  if not exists(select 1 from public.profiles where id=p_member_id and app_role::text='member' and membership_state::text='cancelled' for update)
  then raise exception 'Only a cancelled membership offer can be restored'; end if;
  update public.profiles set membership_state='payment_pending',updated_at=now() where id=p_member_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'membership.offer_restored','member',p_member_id::text,jsonb_build_object('payment_window_days',30,'reason',trim(p_reason)));
end;
$$;

create or replace function public.admin_reopen_expired_membership_for_payment(p_member_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then raise exception 'Administrator permission required'; end if;
  if char_length(trim(coalesce(p_reason,'')))<3 then raise exception 'Reason is required'; end if;
  if not exists(select 1 from public.profiles where id=p_member_id and app_role::text='member' and membership_state::text='expired' for update)
  then raise exception 'Only an expired membership can be reopened for payment'; end if;
  update public.profiles set membership_state='payment_pending',updated_at=now() where id=p_member_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'membership.expired_reopened_for_payment','member',p_member_id::text,jsonb_build_object('payment_window_days',30,'reason',trim(p_reason)));
end;
$$;

create or replace function public.admin_restore_expired_membership_complimentary(p_member_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_plan text;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then raise exception 'Administrator permission required'; end if;
  if char_length(trim(coalesce(p_reason,'')))<3 then raise exception 'Reason is required'; end if;
  select case when founding_member_sequence is not null then 'founding_lifetime' else 'annual' end into v_plan
  from public.profiles where id=p_member_id and app_role::text='member' and membership_state::text='expired' for update;
  if not found then raise exception 'Only an expired membership can be restored'; end if;
  update public.profiles set pending_membership_plan=v_plan,pending_membership_source='complimentary',membership_state='active',updated_at=now() where id=p_member_id;
  update public.membership_terms set reason=trim(p_reason),amount_paise=0 where member_id=p_member_id and status='active';
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'membership.expired_restored_complimentary','member',p_member_id::text,jsonb_build_object('plan',v_plan,'reason',trim(p_reason)));
end;
$$;

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
  elsif v_profile.membership_state::text='payment_pending' then
    update public.profiles set pending_membership_plan=p_plan,pending_membership_source='offline',membership_state='active',updated_at=now() where id=p_member_id;
    update public.membership_terms set amount_paise=p_amount_paise,payment_method=p_payment_method,transaction_reference=v_reference,payment_received_at=p_payment_received_at,reason=trim(p_reason)
    where member_id=p_member_id and status='active' returning id into v_term_id;
  else raise exception 'Offline payment can only complete a pending offer or renew an annual membership on its final validity day';
  end if;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'membership.offline_payment_recorded','member',p_member_id::text,jsonb_build_object('term_id',v_term_id,'plan',p_plan,'amount_paise',p_amount_paise,'payment_method',p_payment_method,'transaction_reference',v_reference,'payment_received_at',p_payment_received_at,'reason',trim(p_reason)));
end;
$$;

create or replace function public.get_member_membership_control(p_member_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_result jsonb;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then raise exception 'Administrator permission required'; end if;
  select jsonb_build_object(
    'member_id',p.id,'membership_state',p.membership_state,'status_context',p.membership_status_context,
    'plan',p.membership_plan,'founding_sequence',p.founding_member_sequence,'starts_at',p.membership_started_at,
    'expires_at',p.membership_expires_at,'payment_offer_expires_at',p.payment_offer_expires_at,
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

create extension if not exists pg_cron with schema extensions;
select cron.schedule('oneclub-membership-lifecycle','15 * * * *','select public.process_membership_lifecycle();');

revoke all on function public.set_membership_payment_window() from public,anon,authenticated;
revoke all on function public.process_membership_lifecycle() from public,anon,authenticated;
revoke all on function public.admin_restore_cancelled_membership_offer(uuid,text) from public,anon;
revoke all on function public.admin_reopen_expired_membership_for_payment(uuid,text) from public,anon;
revoke all on function public.admin_restore_expired_membership_complimentary(uuid,text) from public,anon;
revoke all on function public.get_member_membership_control(uuid) from public,anon;
revoke all on function public.admin_record_offline_membership_payment(uuid,text,integer,text,text,timestamptz,text) from public,anon;
grant execute on function public.admin_restore_cancelled_membership_offer(uuid,text) to authenticated;
grant execute on function public.admin_reopen_expired_membership_for_payment(uuid,text) to authenticated;
grant execute on function public.admin_restore_expired_membership_complimentary(uuid,text) to authenticated;
grant execute on function public.get_member_membership_control(uuid) to authenticated;
grant execute on function public.admin_record_offline_membership_payment(uuid,text,integer,text,text,timestamptz,text) to authenticated;

commit;
