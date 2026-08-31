begin;

create schema if not exists oneclub_legacy;
revoke all on schema oneclub_legacy from public,anon,authenticated;

do $$
begin
  if to_regclass('public.partner_reservations') is not null
     and to_regclass('public.partner_itineraries') is null then
    alter table public.partner_reservations set schema oneclub_legacy;
  end if;

  if to_regclass('public.reservation_notifications') is not null
     and exists(
       select 1 from information_schema.columns
       where table_schema='public' and table_name='reservation_notifications' and column_name='reservation_id'
     )
     and not exists(
       select 1 from information_schema.columns
       where table_schema='public' and table_name='reservation_notifications' and column_name='itinerary_id'
     ) then
    alter table public.reservation_notifications set schema oneclub_legacy;
  end if;
end;
$$;

drop function if exists public.create_partner_reservation(uuid,uuid,date,date,integer,integer,integer,text,text);
drop function if exists public.get_my_partner_reservations();
drop function if exists public.list_partner_reservations_for_staff(text);
drop function if exists public.update_partner_reservation_status(uuid,text,text,text);

commit;
