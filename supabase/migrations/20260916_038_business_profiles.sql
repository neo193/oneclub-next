begin;

create table if not exists public.business_profiles (
  member_id uuid primary key references public.profiles(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 2 and 100),
  business_name text not null check (char_length(trim(business_name)) between 2 and 120),
  role_title text not null check (char_length(trim(role_title)) between 2 and 100),
  industry text not null check (char_length(trim(industry)) between 2 and 100),
  city text check (city is null or char_length(trim(city)) between 2 and 100),
  summary text not null check (char_length(trim(summary)) between 20 and 1000),
  interests text[] not null default '{}',
  website_url text check (website_url is null or website_url ~* '^https://'),
  linkedin_url text check (linkedin_url is null or linkedin_url ~* '^https://(www\.)?linkedin\.com/'),
  status text not null default 'draft' check (status in ('draft','published')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status='published' and published_at is not null) or status='draft')
);

create index if not exists business_profiles_directory_idx on public.business_profiles(status,industry,role_title);
alter table public.business_profiles enable row level security;
revoke all on table public.business_profiles from anon,authenticated;

create or replace function public.get_my_business_profile()
returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
  select coalesce((select to_jsonb(b) from public.business_profiles b where b.member_id=auth.uid()),'null'::jsonb)
$$;

create or replace function public.save_my_business_profile(
  p_display_name text,p_business_name text,p_role_title text,p_industry text,p_city text,p_summary text,
  p_interests text[],p_website_url text,p_linkedin_url text,p_publish boolean
) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_interests text[];
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='member' and membership_state::text='active') then
    raise exception 'An active membership is required';
  end if;
  if char_length(trim(p_display_name)) not between 2 and 100 or char_length(trim(p_business_name)) not between 2 and 120 or char_length(trim(p_role_title)) not between 2 and 100 or char_length(trim(p_industry)) not between 2 and 100 then
    raise exception 'Complete your display name, business name, role and industry';
  end if;
  if char_length(trim(p_summary)) not between 20 and 1000 then raise exception 'Business summary must be between 20 and 1,000 characters'; end if;
  select coalesce(array_agg(value order by position),'{}') into v_interests from (
    select distinct on (lower(trim(value))) trim(value) value,position
    from unnest(coalesce(p_interests,'{}')) with ordinality item(value,position)
    where trim(value)<>'' order by lower(trim(value)),position limit 20
  ) cleaned;
  insert into public.business_profiles(member_id,display_name,business_name,role_title,industry,city,summary,interests,website_url,linkedin_url,status,published_at)
  values(auth.uid(),trim(p_display_name),trim(p_business_name),trim(p_role_title),trim(p_industry),nullif(trim(p_city),''),trim(p_summary),v_interests,nullif(trim(p_website_url),''),nullif(trim(p_linkedin_url),''),case when p_publish then 'published' else 'draft' end,case when p_publish then now() end)
  on conflict(member_id) do update set display_name=excluded.display_name,business_name=excluded.business_name,role_title=excluded.role_title,industry=excluded.industry,city=excluded.city,summary=excluded.summary,interests=excluded.interests,website_url=excluded.website_url,linkedin_url=excluded.linkedin_url,status=excluded.status,published_at=case when excluded.status='published' then coalesce(business_profiles.published_at,now()) else null end,updated_at=now();
end $$;

create or replace function public.search_business_directory(
  p_query text default null,p_industry text default null,p_role text default null,p_interest text default null,p_limit integer default 30
) returns table(member_id uuid,member_name text,business_name text,role_title text,industry text,city text,summary text,interests text[],website_url text,linkedin_url text)
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if not exists(
    select 1 from public.profiles p join public.business_profiles mine on mine.member_id=p.id
    where p.id=auth.uid() and p.app_role::text='member' and p.membership_state::text='active' and mine.status='published'
  ) then raise exception 'Publish your business profile to access the directory'; end if;
  return query
  select b.member_id,b.display_name,b.business_name,b.role_title,b.industry,b.city,b.summary,b.interests,b.website_url,b.linkedin_url
  from public.business_profiles b join public.profiles p on p.id=b.member_id
  where b.status='published' and p.membership_state::text='active' and p.deleted_at is null
    and (nullif(trim(p_query),'') is null or concat_ws(' ',b.display_name,b.business_name,b.role_title,b.industry,b.city,b.summary,array_to_string(b.interests,' ')) ilike '%'||trim(p_query)||'%')
    and (nullif(trim(p_industry),'') is null or b.industry ilike '%'||trim(p_industry)||'%')
    and (nullif(trim(p_role),'') is null or b.role_title ilike '%'||trim(p_role)||'%')
    and (nullif(trim(p_interest),'') is null or exists(select 1 from unnest(b.interests) value where value ilike '%'||trim(p_interest)||'%'))
  order by b.business_name,p.full_name limit least(greatest(coalesce(p_limit,30),1),50);
end $$;

revoke all on function public.get_my_business_profile(),public.save_my_business_profile(text,text,text,text,text,text,text[],text,text,boolean),public.search_business_directory(text,text,text,text,integer) from public,anon;
grant execute on function public.get_my_business_profile(),public.save_my_business_profile(text,text,text,text,text,text,text[],text,text,boolean),public.search_business_directory(text,text,text,text,integer) to authenticated;

commit;
