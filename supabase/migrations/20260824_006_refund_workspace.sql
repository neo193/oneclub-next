begin;

create table if not exists public.refund_requests (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.event_bookings(id) on delete restrict,
  payment_attempt_id uuid not null references public.payment_attempts(id) on delete restrict,
  amount_paise integer not null check (amount_paise > 0),
  razorpay_payment_id text not null,
  razorpay_refund_id text unique,
  status text not null default 'requested' check (status in ('requested','processing','processed','failed')),
  source text not null default 'workspace' check (source in ('workspace','manual_reconciliation','webhook')),
  initiated_by uuid references public.profiles(id) on delete set null,
  failure_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  processed_at timestamptz
);

alter table public.refund_requests enable row level security;
revoke all on table public.refund_requests from anon, authenticated;

create or replace function public.list_refunds_for_admin()
returns table(
  booking_id uuid,
  event_title text,
  member_name text,
  member_email text,
  member_number text,
  amount_paise integer,
  cancelled_at timestamptz,
  payment_status text,
  razorpay_payment_id text,
  razorpay_refund_id text,
  refund_status text,
  refund_source text,
  refund_updated_at timestamptz
)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then
    raise exception 'Administrator permission required';
  end if;
  return query
  select b.id,e.title,p.full_name,u.email::text,p.member_number,b.amount_paise,b.cancelled_at,b.payment_status,
    pa.razorpay_payment_id,rr.razorpay_refund_id,
    coalesce(rr.status,case when b.payment_status='refunded' then 'processed' else 'requested' end),
    rr.source,rr.updated_at
  from public.event_bookings b
  join public.events e on e.id=b.event_id
  join public.profiles p on p.id=b.member_id
  join auth.users u on u.id=b.member_id
  join lateral (
    select x.id,x.razorpay_payment_id from public.payment_attempts x
    where x.booking_id=b.id and x.status='paid' and x.razorpay_payment_id is not null
    order by x.paid_at desc nulls last limit 1
  ) pa on true
  left join public.refund_requests rr on rr.booking_id=b.id
  where b.status='cancelled' and b.payment_status in ('refund_pending','refunded')
  order by coalesce(rr.updated_at,b.cancelled_at) desc;
end; $$;

create or replace function public.get_refund_context(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare result jsonb;
begin
  select jsonb_build_object(
    'booking_id',b.id,'amount_paise',b.amount_paise,'payment_status',b.payment_status,
    'payment_attempt_id',pa.id,'razorpay_payment_id',pa.razorpay_payment_id,
    'razorpay_refund_id',rr.razorpay_refund_id,'refund_status',rr.status
  ) into result
  from public.event_bookings b
  join lateral (
    select x.* from public.payment_attempts x
    where x.booking_id=b.id and x.status='paid' and x.razorpay_payment_id is not null
    order by x.paid_at desc nulls last limit 1
  ) pa on true
  left join public.refund_requests rr on rr.booking_id=b.id
  where b.id=p_booking_id and b.status='cancelled' and b.payment_status in ('refund_pending','refunded');
  if result is null then raise exception 'Eligible cancelled booking not found'; end if;
  return result;
end; $$;

create or replace function public.record_razorpay_refund(
  p_booking_id uuid,p_refund_id text,p_status text,p_source text,
  p_actor_id uuid default null,p_failure_reason text default null
)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare context_record record;
begin
  if p_status not in ('requested','processing','processed','failed') then raise exception 'Invalid refund status'; end if;
  if p_source not in ('workspace','manual_reconciliation','webhook') then raise exception 'Invalid refund source'; end if;
  select b.amount_paise,pa.id payment_attempt_id,pa.razorpay_payment_id
  into context_record
  from public.event_bookings b
  join lateral (
    select x.id,x.razorpay_payment_id from public.payment_attempts x
    where x.booking_id=b.id and x.status='paid' and x.razorpay_payment_id is not null
    order by x.paid_at desc nulls last limit 1
  ) pa on true
  where b.id=p_booking_id and b.status='cancelled' for update of b;
  if not found then raise exception 'Refund booking not found'; end if;

  insert into public.refund_requests(booking_id,payment_attempt_id,amount_paise,razorpay_payment_id,razorpay_refund_id,status,source,initiated_by,failure_reason,processed_at)
  values(p_booking_id,context_record.payment_attempt_id,context_record.amount_paise,context_record.razorpay_payment_id,p_refund_id,p_status,p_source,p_actor_id,p_failure_reason,case when p_status='processed' then now() end)
  on conflict(booking_id) do update set
    razorpay_refund_id=coalesce(excluded.razorpay_refund_id,refund_requests.razorpay_refund_id),
    status=excluded.status,source=excluded.source,
    initiated_by=coalesce(refund_requests.initiated_by,excluded.initiated_by),
    failure_reason=excluded.failure_reason,updated_at=now(),
    processed_at=case when excluded.status='processed' then coalesce(refund_requests.processed_at,now()) else refund_requests.processed_at end;

  update public.event_bookings set payment_status=case when p_status='processed' then 'refunded' else 'refund_pending' end,updated_at=now() where id=p_booking_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(p_actor_id,'event.refund_'||p_status,'event_booking',p_booking_id::text,jsonb_build_object('refund_id',p_refund_id,'source',p_source,'failure_reason',p_failure_reason));
end; $$;

revoke all on function public.list_refunds_for_admin() from public,anon;
revoke all on function public.get_refund_context(uuid) from public,anon,authenticated;
revoke all on function public.record_razorpay_refund(uuid,text,text,text,uuid,text) from public,anon,authenticated;
grant execute on function public.list_refunds_for_admin() to authenticated;
grant execute on function public.get_refund_context(uuid) to service_role;
grant execute on function public.record_razorpay_refund(uuid,text,text,text,uuid,text) to service_role;

commit;
