begin;

create or replace function public.get_member_admin_record(p_member_id uuid)
returns jsonb
language plpgsql security definer set search_path=public,pg_temp
as $$
declare
  v_result jsonb;
  v_support_counts jsonb := jsonb_build_object('total',0,'open',0);
  v_support_table text;
  v_support_member_column text;
begin
  if not public.can_manage_members() then raise exception 'Member management permission required'; end if;

  if to_regclass('public.member_support_requests') is not null then
    v_support_table := 'member_support_requests';
  elsif to_regclass('public.support_requests') is not null then
    v_support_table := 'support_requests';
  end if;

  if v_support_table is not null then
    select c.column_name into v_support_member_column
    from information_schema.columns c
    where c.table_schema='public' and c.table_name=v_support_table
      and c.column_name in ('member_id','user_id','profile_id')
    order by array_position(array['member_id','user_id','profile_id'],c.column_name)
    limit 1;
    if v_support_member_column is not null then
      execute format(
        'select jsonb_build_object(''total'',count(*),''open'',count(*) filter(where status::text in (''open'',''in_progress''))) from public.%I where %I=$1',
        v_support_table,v_support_member_column
      ) into v_support_counts using p_member_id;
    end if;
  end if;

  select jsonb_build_object(
    'id',p.id,
    'full_name',p.full_name,
    'email',u.email,
    'phone',p.phone,
    'birthday',p.birthday,
    'locality',p.locality,
    'profession',p.profession,
    'industry',p.industry,
    'member_number',p.member_number,
    'membership_state',p.membership_state,
    'account_created_at',u.created_at,
    'last_sign_in_at',u.last_sign_in_at,
    'profile_updated_at',p.updated_at,
    'bookings',jsonb_build_object(
      'total',(select count(*) from public.event_bookings b where b.member_id=p.id),
      'confirmed',(select count(*) from public.event_bookings b where b.member_id=p.id and b.status::text='confirmed'),
      'pending',(select count(*) from public.event_bookings b where b.member_id=p.id and b.status::text='pending_payment'),
      'cancelled',(select count(*) from public.event_bookings b where b.member_id=p.id and b.status::text='cancelled')
    ),
    'payments',jsonb_build_object(
      'paid',(select count(*) from public.payment_attempts a where a.user_id=p.id and a.status::text='paid'),
      'created',(select count(*) from public.payment_attempts a where a.user_id=p.id and a.status::text='created'),
      'failed',(select count(*) from public.payment_attempts a where a.user_id=p.id and a.status::text='failed')
    ),
    'refunds',jsonb_build_object(
      'pending',(select count(*) from public.refund_requests r join public.event_bookings b on b.id=r.booking_id where b.member_id=p.id and r.status in ('requested','processing')),
      'processed',(select count(*) from public.refund_requests r join public.event_bookings b on b.id=r.booking_id where b.member_id=p.id and r.status='processed')
    ),
    'support',v_support_counts,
    'notes',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',n.id,'note',n.note,'created_at',n.created_at,
        'author_name',coalesce(a.full_name,'Former staff account')
      ) order by n.created_at desc)
      from public.member_admin_notes n left join public.profiles a on a.id=n.author_id
      where n.member_id=p.id
    ),'[]'::jsonb),
    'recent_actions',coalesce((
      select jsonb_agg(item order by action_time desc) from (
        select jsonb_build_object('action',l.action,'created_at',l.created_at,'details',l.details) item,l.created_at action_time
        from public.audit_log l
        where l.entity_id=p.id::text or l.details->>'member_id'=p.id::text
        order by l.created_at desc limit 10
      ) actions
    ),'[]'::jsonb)
  ) into v_result
  from public.profiles p join auth.users u on u.id=p.id
  where p.id=p_member_id and p.app_role::text='member';

  if v_result is null then raise exception 'Member account not found'; end if;
  return v_result;
end;
$$;

revoke all on function public.get_member_admin_record(uuid) from public,anon;
grant execute on function public.get_member_admin_record(uuid) to authenticated;

commit;
