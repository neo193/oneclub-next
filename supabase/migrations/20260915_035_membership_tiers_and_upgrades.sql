begin;

alter table public.payment_attempts
  add column if not exists membership_plan text,
  add column if not exists membership_credit_paise integer not null default 0;

alter table public.payment_attempts drop constraint if exists payment_attempts_membership_plan_check;
alter table public.payment_attempts add constraint payment_attempts_membership_plan_check
  check ((purpose='membership' and (membership_plan is null or membership_plan in ('annual','founding_lifetime'))) or (purpose<>'membership' and membership_plan is null));

create table if not exists public.founding_membership_reservations (
  member_id uuid primary key references public.profiles(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
alter table public.founding_membership_reservations enable row level security;
revoke all on table public.founding_membership_reservations from anon,authenticated;

create or replace function public.get_membership_purchase_options()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_profile public.profiles;v_credit integer:=0;v_remaining integer;
begin
  select * into v_profile from public.profiles where id=auth.uid() and app_role::text='member';
  if not found then raise exception 'Member account required'; end if;
  if v_profile.membership_state::text not in ('payment_pending','active') then raise exception 'Membership purchase is unavailable'; end if;
  if v_profile.membership_state::text='active' and v_profile.membership_plan<>'annual' then raise exception 'This membership does not require a purchase'; end if;
  if v_profile.membership_state::text='active' then
    select coalesce(amount_paise,0) into v_credit from public.membership_terms
    where member_id=auth.uid() and plan='annual' and status='active'
      and starts_at<=now() and expires_at>now() and amount_paise>0
    order by starts_at desc limit 1;
  end if;
  select greatest(0,500-count(*))::integer into v_remaining
  from (
    select founding_member_sequence::text from public.profiles where founding_member_sequence is not null
    union all
    select member_id::text from public.founding_membership_reservations where expires_at>now()
  ) occupied;
  return jsonb_build_object(
    'annual_price_paise',1800000,'founding_price_paise',5000000,
    'active_annual_credit_paise',least(v_credit,5000000),
    'founding_payable_paise',greatest(0,5000000-least(v_credit,5000000)),
    'founding_places_remaining',v_remaining,
    'is_upgrade',v_profile.membership_state::text='active' and v_profile.membership_plan='annual'
  );
end; $$;

create or replace function public.prepare_membership_payment(p_member_id uuid,p_plan text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_profile public.profiles;v_amount integer;v_credit integer:=0;
begin
  if p_plan not in ('annual','founding_lifetime') then raise exception 'Select a valid membership plan'; end if;
  perform pg_advisory_xact_lock(hashtext('oneclub-founding-member-allocation'));
  delete from public.founding_membership_reservations where expires_at<=now();
  select * into v_profile from public.profiles where id=p_member_id and app_role::text='member' for update;
  if not found then raise exception 'Member account required'; end if;
  if v_profile.membership_state::text='active' then
    if v_profile.membership_plan<>'annual' or p_plan<>'founding_lifetime' then raise exception 'Only an annual membership can be upgraded'; end if;
  elsif v_profile.membership_state::text<>'payment_pending' then raise exception 'Membership is not awaiting payment'; end if;
  if v_profile.membership_state::text='active' then
    select coalesce(amount_paise,0) into v_credit from public.membership_terms
    where member_id=p_member_id and plan='annual' and status='active' and starts_at<=now() and expires_at>now() and amount_paise>0
    order by starts_at desc limit 1;
  end if;
  if p_plan='annual' then v_amount:=1800000;
  else
    if (select count(*) from public.profiles where founding_member_sequence is not null) +
       (select count(*) from public.founding_membership_reservations where expires_at>now() and member_id<>p_member_id)>=500
      then raise exception 'All 500 Founding Membership places have been allocated'; end if;
    v_credit:=least(v_credit,5000000);
    v_amount:=5000000-v_credit;
    insert into public.founding_membership_reservations(member_id,expires_at) values(p_member_id,now()+interval '15 minutes')
    on conflict(member_id) do update set expires_at=excluded.expires_at;
  end if;
  return jsonb_build_object('plan',p_plan,'amount_paise',v_amount,'credit_paise',v_credit);
end; $$;

revoke all on function public.get_membership_purchase_options() from public,anon;
revoke all on function public.prepare_membership_payment(uuid,text) from public,anon,authenticated;
grant execute on function public.get_membership_purchase_options() to authenticated;
grant execute on function public.prepare_membership_payment(uuid,text) to service_role;

create or replace function public.finalize_razorpay_payment(p_attempt_id uuid,p_payment_id text)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.payment_attempts%rowtype;v_sequence integer;v_profile public.profiles;v_now timestamptz:=now();
begin
  select * into v from public.payment_attempts where id=p_attempt_id for update;
  if not found then raise exception 'Payment attempt not found'; end if;
  if v.status='paid' then return v.purpose; end if;
  update public.payment_attempts set status='paid',razorpay_payment_id=p_payment_id,paid_at=v_now,updated_at=v_now where id=v.id;
  if v.purpose='membership' then
    perform pg_advisory_xact_lock(hashtext('oneclub-founding-member-allocation'));
    select * into v_profile from public.profiles where id=v.user_id for update;
    if v.membership_plan='annual' then
      if v_profile.membership_state::text<>'payment_pending' then raise exception 'Membership is not awaiting payment'; end if;
      update public.profiles set pending_membership_plan='annual',pending_membership_source='razorpay',membership_state='active',updated_at=v_now where id=v.user_id;
    elsif v.membership_plan='founding_lifetime' then
      if v_profile.membership_state::text='active' and v_profile.membership_plan='annual' then
        select slot into v_sequence from generate_series(1,500) slot where not exists(select 1 from public.profiles p where p.founding_member_sequence=slot) order by slot limit 1;
        if v_sequence is null then raise exception 'All 500 Founding Membership places have been allocated'; end if;
        update public.membership_terms set status='cancelled',cancelled_at=v_now,reason='Upgraded to Founding Membership',updated_at=v_now where member_id=v.user_id and plan='annual' and status='active';
        update public.profiles set founding_member_sequence=v_sequence,member_number='OC-F-'||lpad(v_sequence::text,6,'0'),membership_plan='founding_lifetime',membership_started_at=v_now,membership_expires_at=null,updated_at=v_now where id=v.user_id;
        insert into public.membership_terms(member_id,plan,source,status,starts_at,amount_paise,payment_method,transaction_reference,payment_received_at,reason)
        values(v.user_id,'founding_lifetime','razorpay','active',v_now,v.amount_paise,'razorpay',p_payment_id,v_now,'Annual membership upgraded with active-term credit');
      else
        if v_profile.membership_state::text<>'payment_pending' then raise exception 'Membership is not awaiting payment'; end if;
        update public.profiles set pending_membership_plan='founding_lifetime',pending_membership_source='razorpay',membership_state='active',updated_at=v_now where id=v.user_id;
      end if;
      delete from public.founding_membership_reservations where member_id=v.user_id;
    else raise exception 'Payment attempt has no membership plan'; end if;
  else
    update public.event_bookings set status='confirmed',payment_status='paid',reservation_expires_at=null,updated_at=v_now where id=v.booking_id and member_id=v.user_id and status='pending_payment';
    if not found then raise exception 'Event reservation is no longer payable'; end if;
  end if;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values(v.user_id,v.purpose||'.payment_confirmed',v.purpose,v.user_id::text,jsonb_build_object('payment_id',p_payment_id,'plan',v.membership_plan,'credit_paise',v.membership_credit_paise));
  return v.purpose;
end; $$;
revoke all on function public.finalize_razorpay_payment(uuid,text) from public,anon,authenticated;
grant execute on function public.finalize_razorpay_payment(uuid,text) to service_role;

commit;

