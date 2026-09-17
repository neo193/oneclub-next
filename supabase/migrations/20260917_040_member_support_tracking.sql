-- Member-visible support progress and duplicate active-ticket prevention.

create or replace function public.list_my_support_requests()
returns table(
  id uuid,
  category text,
  message text,
  status text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select r.id,r.category,r.message,r.status,r.created_at,r.updated_at
  from public.member_support_requests r
  where r.user_id=auth.uid()
    and r.status<>'closed'
  order by
    case r.status when 'in_progress' then 1 when 'open' then 2 when 'resolved' then 3 else 4 end,
    r.updated_at desc;
$$;

create or replace function public.submit_member_support_request(p_category text,p_message text)
returns uuid
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_id uuid;
begin
  if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid()) then
    raise exception 'Sign in required';
  end if;
  if p_category not in ('membership_access','payment','event_booking','reservation_change','profile','other') then
    raise exception 'Invalid support category';
  end if;
  if char_length(trim(coalesce(p_message,''))) not between 10 and 2000 then
    raise exception 'Message must contain between 10 and 2000 characters';
  end if;

  -- Serialize submissions for this member/category so concurrent requests cannot create duplicates.
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':'||p_category,0));
  if exists(
    select 1 from public.member_support_requests
    where user_id=auth.uid() and category=p_category and status in ('open','in_progress')
  ) then
    raise exception 'You already have an active support request for this category.';
  end if;

  insert into public.member_support_requests(user_id,category,message)
  values(auth.uid(),p_category,trim(p_message))
  returning id into v_id;

  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'member.support_requested','member_support_request',v_id::text,jsonb_build_object('category',p_category));
  return v_id;
end;
$$;

revoke all on function public.list_my_support_requests() from public,anon;
revoke all on function public.submit_member_support_request(text,text) from public,anon;
grant execute on function public.list_my_support_requests() to authenticated;
grant execute on function public.submit_member_support_request(text,text) to authenticated;
