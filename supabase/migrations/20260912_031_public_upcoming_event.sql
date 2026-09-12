begin;

-- Public teaser only; booking, pricing and member records remain private.
create or replace function public.get_public_upcoming_event()
returns table(title text, venue text, description text)
language sql stable security definer
set search_path = public, pg_temp
as $$
  select e.title::text, e.venue::text, e.description::text
  from public.events e
  where e.status::text = 'published' and e.starts_at > now()
  order by e.starts_at asc, e.id asc
  limit 1;
$$;
revoke all on function public.get_public_upcoming_event() from public;
grant execute on function public.get_public_upcoming_event() to anon, authenticated;
commit;

