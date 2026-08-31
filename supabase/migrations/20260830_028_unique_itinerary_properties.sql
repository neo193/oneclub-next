begin;

create or replace function public.enforce_unique_itinerary_property()
returns trigger
language plpgsql
set search_path=public,pg_temp
as $$
declare
  v_itinerary_id uuid;
begin
  select itinerary_id into v_itinerary_id
  from public.partner_itinerary_stops
  where id=new.stop_id;

  if exists(
    select 1
    from public.partner_itinerary_choices choice
    join public.partner_itinerary_stops stop on stop.id=choice.stop_id
    where stop.itinerary_id=v_itinerary_id
      and choice.property_id=new.property_id
      and choice.id is distinct from new.id
  ) then
    raise exception 'Each property can appear only once in an itinerary';
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_unique_itinerary_property_trigger
on public.partner_itinerary_choices;

create trigger enforce_unique_itinerary_property_trigger
before insert or update of stop_id,property_id
on public.partner_itinerary_choices
for each row execute function public.enforce_unique_itinerary_property();

commit;
