begin;

create table if not exists public.membership_tiers (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z0-9_]{3,50}$'),
  name text not null check (char_length(trim(name)) between 3 and 80),
  description text not null check (char_length(trim(description)) between 10 and 1000),
  classification text not null check (classification in ('standard','premium')),
  price_paise integer not null check (price_paise>0),
  validity_months integer check (validity_months is null or validity_months between 1 and 120),
  allocation_limit integer check (allocation_limit is null or allocation_limit between 1 and 100000),
  status text not null default 'draft' check (status in ('draft','published','sold_out','retired','archived')),
  display_slot smallint check (display_slot in (1,2)),
  upgrades_enabled boolean not null default false,
  active_term_credit_enabled boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  published_at timestamptz,
  retired_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint membership_tiers_publication_check check (
    (status='published' and display_slot is not null and published_at is not null)
    or (status<>'published' and display_slot is null)
  )
);
create unique index if not exists membership_tiers_published_slot_unique on public.membership_tiers(display_slot) where status='published';

alter table public.profiles add column if not exists membership_tier_id uuid references public.membership_tiers(id) on delete restrict;
alter table public.profiles add column if not exists pending_membership_tier_id uuid references public.membership_tiers(id) on delete restrict;
alter table public.membership_terms add column if not exists tier_id uuid references public.membership_tiers(id) on delete restrict;
alter table public.payment_attempts add column if not exists membership_tier_id uuid references public.membership_tiers(id) on delete restrict;
alter table public.founding_membership_reservations add column if not exists tier_id uuid references public.membership_tiers(id) on delete cascade;

alter table public.profiles drop constraint if exists profiles_membership_plan_check;
alter table public.profiles add constraint profiles_membership_plan_check check (membership_plan is null or membership_plan ~ '^[a-z0-9_]{3,50}$');
alter table public.profiles drop constraint if exists profiles_pending_membership_plan_check;
alter table public.profiles add constraint profiles_pending_membership_plan_check check (pending_membership_plan is null or pending_membership_plan ~ '^[a-z0-9_]{3,50}$');
alter table public.membership_terms drop constraint if exists membership_terms_plan_check;
alter table public.membership_terms add constraint membership_terms_plan_check check (plan ~ '^[a-z0-9_]{3,50}$');
alter table public.payment_attempts drop constraint if exists payment_attempts_membership_plan_check;
alter table public.payment_attempts add constraint payment_attempts_membership_plan_check check ((purpose='membership' and (membership_plan is null or membership_plan ~ '^[a-z0-9_]{3,50}$')) or (purpose<>'membership' and membership_plan is null));

insert into public.membership_tiers(code,name,description,classification,price_paise,validity_months,allocation_limit,status,display_slot,upgrades_enabled,active_term_credit_enabled,published_at)
values
 ('founding_lifetime','Founding Membership','Lifetime One Club membership with access to selected Founding Member experiences.','premium',5000000,null,500,'published',1,true,true,now()),
 ('annual','Annual Membership','One year of One Club membership with all standard member benefits.','standard',1800000,12,null,'published',2,false,false,now())
on conflict(code) do update set
 name=excluded.name,classification=excluded.classification,validity_months=excluded.validity_months,
 allocation_limit=excluded.allocation_limit,upgrades_enabled=excluded.upgrades_enabled,
 active_term_credit_enabled=excluded.active_term_credit_enabled,updated_at=now();

update public.profiles p set membership_tier_id=t.id from public.membership_tiers t
where p.membership_tier_id is null and p.membership_plan=t.code;
update public.profiles p set pending_membership_tier_id=t.id from public.membership_tiers t
where p.pending_membership_tier_id is null and p.pending_membership_plan=t.code;
update public.membership_terms mt set tier_id=t.id from public.membership_tiers t
where mt.tier_id is null and mt.plan=t.code;
update public.payment_attempts pa set membership_tier_id=t.id from public.membership_tiers t
where pa.membership_tier_id is null and pa.membership_plan=t.code;
update public.founding_membership_reservations r set tier_id=t.id from public.membership_tiers t
where r.tier_id is null and t.code='founding_lifetime';

alter table public.membership_tiers enable row level security;
revoke all on table public.membership_tiers from anon,authenticated;

create or replace function public.is_membership_tier_admin()
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
select exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin')
$$;

create or replace function public.list_membership_tiers_for_admin()
returns table(id uuid,code text,name text,description text,classification text,price_paise integer,validity_months integer,allocation_limit integer,allocated integer,status text,display_slot smallint,upgrades_enabled boolean,active_term_credit_enabled boolean,published_at timestamptz,retired_at timestamptz,created_at timestamptz)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not public.is_membership_tier_admin() then raise exception 'Administrator permission required'; end if;
 return query select t.id,t.code,t.name,t.description,t.classification,t.price_paise,t.validity_months,t.allocation_limit,
   count(p.id)::integer,t.status,t.display_slot,t.upgrades_enabled,t.active_term_credit_enabled,t.published_at,t.retired_at,t.created_at
 from public.membership_tiers t left join public.profiles p on p.membership_tier_id=t.id
 group by t.id order by case t.status when 'published' then 1 when 'draft' then 2 else 3 end,t.display_slot nulls last,t.created_at desc;
end $$;

create or replace function public.get_published_membership_slots_for_admin()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare result jsonb;
begin
 if not public.is_membership_tier_admin() then raise exception 'Administrator permission required'; end if;
 select jsonb_agg(coalesce(tier,jsonb_build_object('display_slot',slot,'empty',true)) order by slot) into result
 from generate_series(1,2) slot left join lateral (
   select jsonb_build_object('id',t.id,'display_slot',slot,'name',t.name,'price_paise',t.price_paise,'validity_months',t.validity_months,'allocation_limit',t.allocation_limit,'allocated',(select count(*) from public.profiles p where p.membership_tier_id=t.id),'empty',false) tier
   from public.membership_tiers t where t.status='published' and t.display_slot=slot
 ) current on true;
 return coalesce(result,'[]'::jsonb);
end $$;

create or replace function public.save_membership_tier(
 p_id uuid,p_name text,p_description text,p_classification text,p_price_paise integer,
 p_validity_months integer,p_allocation_limit integer,p_upgrades_enabled boolean,p_active_term_credit_enabled boolean
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;v_status text;v_code text;
begin
 if not public.is_membership_tier_admin() then raise exception 'Administrator permission required'; end if;
 if char_length(trim(p_name)) not between 3 and 80 or char_length(trim(p_description)) not between 10 and 1000 then raise exception 'Complete the tier name and description'; end if;
 if p_classification not in ('standard','premium') then raise exception 'Select a valid internal classification'; end if;
 if p_price_paise<=0 then raise exception 'Price must be greater than zero'; end if;
 if p_validity_months is not null and p_validity_months not between 1 and 120 then raise exception 'Validity must be between 1 and 120 months'; end if;
 if p_allocation_limit is not null and p_allocation_limit not between 1 and 100000 then raise exception 'Allocation limit is invalid'; end if;
 if p_classification='standard' and p_upgrades_enabled then raise exception 'Only premium tiers can be upgrade targets'; end if;
 if p_id is null then
   v_code:=regexp_replace(lower(trim(p_name)),'[^a-z0-9]+','_','g')||'_'||substr(replace(gen_random_uuid()::text,'-',''),1,8);
   insert into public.membership_tiers(code,name,description,classification,price_paise,validity_months,allocation_limit,upgrades_enabled,active_term_credit_enabled,created_by)
   values(v_code,trim(p_name),trim(p_description),p_classification,p_price_paise,p_validity_months,p_allocation_limit,p_upgrades_enabled,p_active_term_credit_enabled,auth.uid()) returning id into v_id;
 else
   select status into v_status from public.membership_tiers where id=p_id for update;
   if not found or v_status in ('sold_out','retired','archived') then raise exception 'This tier can no longer be edited'; end if;
   if exists(select 1 from public.membership_tiers where id=p_id and code='founding_lifetime') and p_allocation_limit is distinct from 500 then raise exception 'The original Founding Membership allocation is fixed at 500'; end if;
   if exists(select 1 from public.profiles where membership_tier_id=p_id) and (select validity_months from public.membership_tiers where id=p_id) is distinct from p_validity_months then raise exception 'Validity cannot change after memberships have been allocated'; end if;
   if p_allocation_limit is not null and p_allocation_limit<(select count(*) from public.profiles where membership_tier_id=p_id) then raise exception 'Allocation limit cannot be lower than memberships already allocated'; end if;
   update public.membership_tiers set name=trim(p_name),description=trim(p_description),classification=p_classification,price_paise=p_price_paise,validity_months=p_validity_months,allocation_limit=p_allocation_limit,upgrades_enabled=p_upgrades_enabled,active_term_credit_enabled=p_active_term_credit_enabled,updated_at=now() where id=p_id returning id into v_id;
 end if;
 insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'membership_tier.saved','membership_tier',v_id::text,jsonb_build_object('name',trim(p_name),'price_paise',p_price_paise,'classification',p_classification));
 return v_id;
end $$;

create or replace function public.publish_membership_tier(p_tier_id uuid,p_display_slot smallint)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_tier public.membership_tiers;v_allocated integer;
begin
 if not public.is_membership_tier_admin() then raise exception 'Administrator permission required'; end if;
 if p_display_slot not in (1,2) then raise exception 'Select a valid display slot'; end if;
 if exists(select 1 from public.membership_tiers where status='published' and display_slot=p_display_slot and id<>p_tier_id) then raise exception 'That published slot is occupied'; end if;
 select * into v_tier from public.membership_tiers where id=p_tier_id for update;
 if not found or v_tier.status not in ('draft','retired') then raise exception 'Only a draft or retired tier can be published'; end if;
 select count(*) into v_allocated from public.profiles where membership_tier_id=p_tier_id;
 if v_tier.allocation_limit is not null and v_allocated>=v_tier.allocation_limit then raise exception 'This tier has sold out'; end if;
 update public.membership_tiers set status='published',display_slot=p_display_slot,published_at=coalesce(published_at,now()),retired_at=null,updated_at=now() where id=p_tier_id;
 insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'membership_tier.published','membership_tier',p_tier_id::text,jsonb_build_object('display_slot',p_display_slot));
end $$;

create or replace function public.retire_membership_tier(p_tier_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not public.is_membership_tier_admin() then raise exception 'Administrator permission required'; end if;
 if not exists(select 1 from public.membership_tiers where id=p_tier_id and status='published' for update) then raise exception 'Only a published tier can be retired'; end if;
 if (select count(*) from public.membership_tiers where status='published')<=1 then raise exception 'At least one membership tier must remain published'; end if;
 update public.membership_tiers set status='retired',display_slot=null,retired_at=now(),updated_at=now() where id=p_tier_id;
 insert into public.audit_log(actor_id,action,entity_type,entity_id) values(auth.uid(),'membership_tier.retired','membership_tier',p_tier_id::text);
end $$;

create or replace function public.get_available_membership_tiers()
returns table(id uuid,name text,description text,price_paise integer,validity_months integer,places_remaining integer)
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from public.profiles where profiles.id=auth.uid() and app_role::text='member' and membership_state::text='payment_pending') then raise exception 'Membership is not awaiting payment'; end if;
 return query select t.id,t.name,t.description,t.price_paise,t.validity_months,
   case when t.allocation_limit is null then null else greatest(0,t.allocation_limit-(select count(*) from public.profiles p where p.membership_tier_id=t.id)-(select count(*) from public.founding_membership_reservations r where r.tier_id=t.id and r.expires_at>now()))::integer end
 from public.membership_tiers t where t.status='published' order by t.display_slot;
end $$;

create or replace function public.get_eligible_membership_upgrades()
returns table(id uuid,name text,description text,price_paise integer,validity_months integer,credit_paise integer,payable_paise integer,places_remaining integer)
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_profile public.profiles;v_source_class text;v_credit integer:=0;
begin
 select * into v_profile from public.profiles where profiles.id=auth.uid() and app_role::text='member' and membership_state::text='active';
 if not found or v_profile.membership_tier_id is null then return; end if;
 select classification into v_source_class from public.membership_tiers where membership_tiers.id=v_profile.membership_tier_id;
 if v_source_class<>'standard' then return; end if;
 select coalesce(amount_paise,0) into v_credit from public.membership_terms where member_id=auth.uid() and tier_id=v_profile.membership_tier_id and status='active' and starts_at<=now() and (expires_at is null or expires_at>now()) order by starts_at desc limit 1;
 return query select t.id,t.name,t.description,t.price_paise,t.validity_months,
   case when t.active_term_credit_enabled then least(v_credit,t.price_paise) else 0 end,
   greatest(0,t.price_paise-case when t.active_term_credit_enabled then least(v_credit,t.price_paise) else 0 end),
   case when t.allocation_limit is null then null else greatest(0,t.allocation_limit-(select count(*) from public.profiles p where p.membership_tier_id=t.id)-(select count(*) from public.founding_membership_reservations r where r.tier_id=t.id and r.expires_at>now()))::integer end
 from public.membership_tiers t where t.status='published' and t.classification='premium' and t.upgrades_enabled
   and (t.allocation_limit is null or (select count(*) from public.profiles p where p.membership_tier_id=t.id)+(select count(*) from public.founding_membership_reservations r where r.tier_id=t.id and r.member_id<>auth.uid() and r.expires_at>now())<t.allocation_limit)
 order by t.display_slot;
end $$;

create or replace function public.prepare_membership_tier_payment(p_member_id uuid,p_tier_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_profile public.profiles;v_tier public.membership_tiers;v_source_class text;v_credit integer:=0;v_allocated integer;v_reserved integer;
begin
 perform pg_advisory_xact_lock(hashtext('oneclub-membership-tier-allocation'));
 delete from public.founding_membership_reservations where expires_at<=now();
 select * into v_profile from public.profiles where id=p_member_id and app_role::text='member' for update;
 select * into v_tier from public.membership_tiers where id=p_tier_id and status='published' for update;
 if not found then raise exception 'This membership tier is unavailable'; end if;
 if v_profile.membership_state::text='active' then
   select classification into v_source_class from public.membership_tiers where id=v_profile.membership_tier_id;
   if v_source_class<>'standard' or v_tier.classification<>'premium' or not v_tier.upgrades_enabled then raise exception 'This membership upgrade is unavailable'; end if;
   if v_tier.active_term_credit_enabled then select coalesce(amount_paise,0) into v_credit from public.membership_terms where member_id=p_member_id and tier_id=v_profile.membership_tier_id and status='active' and starts_at<=now() and (expires_at is null or expires_at>now()) order by starts_at desc limit 1;end if;
 elsif v_profile.membership_state::text<>'payment_pending' then raise exception 'Membership purchase is unavailable'; end if;
 select count(*) into v_allocated from public.profiles where membership_tier_id=p_tier_id;
 select count(*) into v_reserved from public.founding_membership_reservations where tier_id=p_tier_id and member_id<>p_member_id and expires_at>now();
 if v_tier.allocation_limit is not null and v_allocated+v_reserved>=v_tier.allocation_limit then raise exception 'This membership tier has sold out'; end if;
 insert into public.founding_membership_reservations(member_id,tier_id,expires_at) values(p_member_id,p_tier_id,now()+interval '15 minutes') on conflict(member_id) do update set tier_id=excluded.tier_id,expires_at=excluded.expires_at;
 return jsonb_build_object('tier_id',v_tier.id,'plan',v_tier.code,'amount_paise',greatest(0,v_tier.price_paise-least(v_credit,v_tier.price_paise)),'credit_paise',least(v_credit,v_tier.price_paise),'description',v_tier.name);
end $$;

create or replace function public.prepare_membership_activation()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_tier public.membership_tiers;v_sequence integer;v_member_sequence integer;
begin
 if new.app_role::text<>'member' or new.membership_state::text<>'active' or old.membership_state::text in ('active','suspended') then return new;end if;
 select * into v_tier from public.membership_tiers where id=new.pending_membership_tier_id;
 if not found then select * into v_tier from public.membership_tiers where code=new.pending_membership_plan;end if;
 if not found then raise exception 'Membership tier is missing';end if;
 if v_tier.code='founding_lifetime' and new.founding_member_sequence is null then select slot into v_sequence from generate_series(1,500) slot where not exists(select 1 from public.profiles p where p.founding_member_sequence=slot) order by slot limit 1;if v_sequence is null then raise exception 'All 500 Founding Membership places have been allocated';end if;new.founding_member_sequence:=v_sequence;end if;
 if v_tier.code='founding_lifetime' then new.member_number:='OC-F-'||lpad(new.founding_member_sequence::text,6,'0');elsif new.member_number is null then select coalesce(max((substring(p.member_number from '(\d+)$'))::integer),0)+1 into v_member_sequence from public.profiles p where p.member_number like 'OC-M-%';new.member_number:='OC-M-'||lpad(v_member_sequence::text,6,'0');end if;
 new.membership_tier_id:=v_tier.id;new.membership_plan:=v_tier.code;new.membership_started_at:=now();new.membership_expires_at:=case when v_tier.validity_months is null then null else now()+make_interval(months=>v_tier.validity_months) end;return new;
end $$;

create or replace function public.record_membership_activation()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_source text;v_amount integer;v_reference text;v_tier_id uuid;
begin
 if new.app_role::text='member' and new.membership_state::text='active' and old.membership_state::text not in ('active','suspended') then
   select 'razorpay',a.amount_paise,a.razorpay_payment_id,a.membership_tier_id into v_source,v_amount,v_reference,v_tier_id from public.payment_attempts a where a.user_id=new.id and a.purpose='membership' and a.status='paid' order by a.paid_at desc nulls last,a.created_at desc limit 1;
   v_source:=coalesce(new.pending_membership_source,v_source,'legacy');v_tier_id:=coalesce(new.membership_tier_id,v_tier_id);
   update public.membership_terms set status='superseded',updated_at=now() where member_id=new.id and status='active';
   insert into public.membership_terms(member_id,tier_id,plan,source,status,starts_at,expires_at,amount_paise,payment_method,transaction_reference,created_by) values(new.id,v_tier_id,new.membership_plan,v_source,'active',new.membership_started_at,new.membership_expires_at,v_amount,case when v_source='razorpay' then 'razorpay' end,v_reference,auth.uid());
   update public.profiles set pending_membership_plan=null,pending_membership_tier_id=null,pending_membership_source=null where id=new.id;
 elsif new.membership_state::text in ('cancelled','expired') and old.membership_state::text<>new.membership_state::text then update public.membership_terms set status=new.membership_state::text,updated_at=now(),cancelled_at=case when new.membership_state::text='cancelled' then now() else cancelled_at end where member_id=new.id and status='active';end if;
 return null;
end $$;

create or replace function public.finalize_razorpay_payment(p_attempt_id uuid,p_payment_id text)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.payment_attempts%rowtype;v_tier public.membership_tiers;v_profile public.profiles;v_now timestamptz:=now();v_allocated integer;
begin
 select * into v from public.payment_attempts where id=p_attempt_id for update;if not found then raise exception 'Payment attempt not found';end if;if v.status='paid' then return v.purpose;end if;
 update public.payment_attempts set status='paid',razorpay_payment_id=p_payment_id,paid_at=v_now,updated_at=v_now where id=v.id;
 if v.purpose='membership' then
   perform pg_advisory_xact_lock(hashtext('oneclub-membership-tier-allocation'));select * into v_tier from public.membership_tiers where id=v.membership_tier_id for update;if not found then raise exception 'Payment tier is missing';end if;
   select * into v_profile from public.profiles where id=v.user_id for update;
   if v_profile.membership_state::text='active' then update public.profiles set membership_state='payment_pending',pending_membership_tier_id=v_tier.id,pending_membership_plan=v_tier.code,pending_membership_source='razorpay',updated_at=v_now where id=v.user_id;end if;
   update public.profiles set pending_membership_tier_id=v_tier.id,pending_membership_plan=v_tier.code,pending_membership_source='razorpay',membership_state='active',updated_at=v_now where id=v.user_id and membership_state::text='payment_pending';if not found then raise exception 'Membership is not awaiting payment';end if;
   delete from public.founding_membership_reservations where member_id=v.user_id;
   select count(*) into v_allocated from public.profiles where membership_tier_id=v_tier.id;
   if v_tier.allocation_limit is not null and v_allocated>=v_tier.allocation_limit then update public.membership_tiers set status='sold_out',display_slot=null,updated_at=v_now where id=v_tier.id;end if;
 else update public.event_bookings set status='confirmed',payment_status='paid',reservation_expires_at=null,updated_at=v_now where id=v.booking_id and member_id=v.user_id and status='pending_payment';if not found then raise exception 'Event reservation is no longer payable';end if;end if;
 return v.purpose;
end $$;

revoke all on function public.is_membership_tier_admin(),public.list_membership_tiers_for_admin(),public.get_published_membership_slots_for_admin(),public.save_membership_tier(uuid,text,text,text,integer,integer,integer,boolean,boolean),public.publish_membership_tier(uuid,smallint),public.retire_membership_tier(uuid) from public,anon;
grant execute on function public.is_membership_tier_admin(),public.list_membership_tiers_for_admin(),public.get_published_membership_slots_for_admin(),public.save_membership_tier(uuid,text,text,text,integer,integer,integer,boolean,boolean),public.publish_membership_tier(uuid,smallint),public.retire_membership_tier(uuid) to authenticated;
revoke all on function public.get_available_membership_tiers(),public.get_eligible_membership_upgrades(),public.prepare_membership_tier_payment(uuid,uuid) from public,anon;
grant execute on function public.get_available_membership_tiers(),public.get_eligible_membership_upgrades() to authenticated;
grant execute on function public.prepare_membership_tier_payment(uuid,uuid) to service_role;

commit;
