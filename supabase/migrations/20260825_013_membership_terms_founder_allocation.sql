begin;

alter table public.profiles
  add column if not exists founding_member_sequence smallint,
  add column if not exists membership_plan text,
  add column if not exists membership_started_at timestamptz,
  add column if not exists membership_expires_at timestamptz,
  add column if not exists pending_membership_plan text,
  add column if not exists pending_membership_source text;

alter table public.profiles drop constraint if exists profiles_founding_member_sequence_check;
alter table public.profiles add constraint profiles_founding_member_sequence_check check (founding_member_sequence between 1 and 500);
alter table public.profiles drop constraint if exists profiles_membership_plan_check;
alter table public.profiles add constraint profiles_membership_plan_check check (membership_plan is null or membership_plan in ('founding_lifetime','annual'));
alter table public.profiles drop constraint if exists profiles_pending_membership_plan_check;
alter table public.profiles add constraint profiles_pending_membership_plan_check check (pending_membership_plan is null or pending_membership_plan in ('founding_lifetime','annual'));
alter table public.profiles drop constraint if exists profiles_pending_membership_source_check;
alter table public.profiles add constraint profiles_pending_membership_source_check check (pending_membership_source is null or pending_membership_source in ('razorpay','complimentary','offline','legacy'));
create unique index if not exists profiles_founding_member_sequence_unique on public.profiles(founding_member_sequence) where founding_member_sequence is not null;

create table if not exists public.membership_terms (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.profiles(id) on delete restrict,
  plan text not null check (plan in ('founding_lifetime','annual')),
  source text not null check (source in ('razorpay','complimentary','offline','legacy')),
  status text not null default 'active' check (status in ('active','expired','cancelled','superseded')),
  starts_at timestamptz not null,
  expires_at timestamptz,
  amount_paise integer check (amount_paise is null or amount_paise >= 0),
  payment_method text check (payment_method is null or payment_method in ('razorpay','bank_transfer','upi','card_pos','cash','cheque','other')),
  transaction_reference text,
  reason text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  cancelled_at timestamptz,
  constraint membership_terms_dates_check check ((plan='founding_lifetime' and expires_at is null) or (plan='annual' and expires_at is not null and expires_at>starts_at))
);

create index if not exists membership_terms_member_created_idx on public.membership_terms(member_id,created_at desc);
create unique index if not exists membership_terms_one_active_per_member on public.membership_terms(member_id) where status='active';
alter table public.membership_terms enable row level security;
revoke all on table public.membership_terms from public,anon,authenticated;

-- Preserve the founding identity already shown to existing numbered members.
update public.profiles
set founding_member_sequence=(substring(member_number from '(\d+)$'))::integer,
    membership_plan='founding_lifetime',membership_started_at=coalesce(membership_started_at,created_at),membership_expires_at=null
where app_role::text='member' and member_number ~ '\d+$'
  and (substring(member_number from '(\d+)$'))::integer between 1 and 500
  and founding_member_sequence is null;

insert into public.membership_terms(member_id,plan,source,status,starts_at,expires_at,amount_paise,reason)
select p.id,'founding_lifetime','legacy',case when p.membership_state::text='cancelled' then 'cancelled' when p.membership_state::text='expired' then 'expired' else 'active' end,
  coalesce(p.membership_started_at,p.created_at),null,null,'Migrated from the pre-ledger membership record'
from public.profiles p
where p.app_role::text='member' and p.founding_member_sequence is not null
  and p.membership_state::text in ('active','suspended','cancelled','expired')
  and not exists(select 1 from public.membership_terms t where t.member_id=p.id);

create or replace function public.prepare_membership_activation()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_plan text; v_sequence integer; v_member_sequence integer;
begin
  if new.app_role::text<>'member' or new.membership_state::text<>'active' or old.membership_state::text in ('active','suspended') then return new; end if;
  perform pg_advisory_xact_lock(hashtext('oneclub-founding-member-allocation'));
  v_plan:=new.pending_membership_plan;
  if v_plan is null then v_plan:=case when (select count(*) from public.profiles where founding_member_sequence is not null)<500 then 'founding_lifetime' else 'annual' end; end if;
  if v_plan='founding_lifetime' and new.founding_member_sequence is null then
    select slot into v_sequence from generate_series(1,500) slot
    where not exists(select 1 from public.profiles p where p.founding_member_sequence=slot) order by slot limit 1;
    if v_sequence is null then raise exception 'All 500 Founding Membership places have been allocated'; end if;
    new.founding_member_sequence:=v_sequence;
  end if;
  if v_plan='founding_lifetime' then
    new.member_number:='OC-F-'||lpad(new.founding_member_sequence::text,6,'0');
  elsif new.member_number is null or new.member_number like 'OC-F-%' then
    select coalesce(max((substring(p.member_number from '(\d+)$'))::integer),0)+1 into v_member_sequence
    from public.profiles p where p.member_number like 'OC-M-%';
    new.member_number:='OC-M-'||lpad(v_member_sequence::text,6,'0');
  end if;
  new.membership_plan:=v_plan;
  new.membership_started_at:=now();
  new.membership_expires_at:=case when v_plan='annual' then now()+interval '1 year' else null end;
  return new;
end;
$$;

create or replace function public.record_membership_activation()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_source text; v_amount integer; v_reference text;
begin
  if new.app_role::text='member' and new.membership_state::text='active' and old.membership_state::text not in ('active','suspended') then
    v_source:=new.pending_membership_source;
    if v_source is null then
      select 'razorpay',a.amount_paise,a.razorpay_payment_id into v_source,v_amount,v_reference
      from public.payment_attempts a where a.user_id=new.id and a.purpose::text='membership' and a.status::text='paid'
      order by a.paid_at desc nulls last,a.created_at desc limit 1;
    end if;
    v_source:=coalesce(v_source,'legacy');
    update public.membership_terms set status='superseded',updated_at=now() where member_id=new.id and status='active';
    insert into public.membership_terms(member_id,plan,source,status,starts_at,expires_at,amount_paise,payment_method,transaction_reference,reason,created_by)
    values(new.id,new.membership_plan,v_source,'active',new.membership_started_at,new.membership_expires_at,v_amount,
      case when v_source='razorpay' then 'razorpay' end,v_reference,case when v_source='legacy' then 'Activated by the pre-ledger workflow' end,auth.uid());
    insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'membership.term_activated','member',new.id::text,jsonb_build_object('plan',new.membership_plan,'source',v_source,'starts_at',new.membership_started_at,'expires_at',new.membership_expires_at,'founding_sequence',new.founding_member_sequence));
    update public.profiles set pending_membership_plan=null,pending_membership_source=null where id=new.id;
  elsif new.membership_state::text in ('cancelled','expired') and old.membership_state::text<>new.membership_state::text then
    update public.membership_terms set status=new.membership_state::text,updated_at=now(),cancelled_at=case when new.membership_state::text='cancelled' then now() else cancelled_at end
    where member_id=new.id and status='active';
  end if;
  return null;
end;
$$;

drop trigger if exists prepare_membership_activation_trigger on public.profiles;
create trigger prepare_membership_activation_trigger before update of membership_state on public.profiles for each row execute function public.prepare_membership_activation();
drop trigger if exists record_membership_activation_trigger on public.profiles;
create trigger record_membership_activation_trigger after update of membership_state on public.profiles for each row execute function public.record_membership_activation();
revoke all on function public.prepare_membership_activation() from public,anon,authenticated;
revoke all on function public.record_membership_activation() from public,anon,authenticated;

commit;
