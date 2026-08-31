begin;

create or replace function public.get_member_reservation_options()
returns jsonb
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_result jsonb;
begin
  if not exists(
    select 1 from public.profiles
    where id=auth.uid()
      and app_role::text='member'
      and membership_state::text='active'
  ) then
    raise exception 'Active membership is required to create a reservation';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'property_id',pp.id,
    'partner_id',p.id,
    'partner_name',p.name,
    'property_name',pp.name,
    'address',pp.address,
    'is_primary',pp.is_primary
  ) order by p.name,pp.is_primary desc,pp.name),'[]'::jsonb)
  into v_result
  from public.partner_properties pp
  join public.partners p on p.id=pp.partner_id
  where nullif(trim(pp.reservation_email),'') is not null
    and nullif(trim(pp.reservation_phone),'') is not null;

  return v_result;
end;
$$;

-- Keep reservation submission aligned with the selector. A property's eligibility
-- depends only on having both reservation contact fields configured. The partner's
-- single benefit is attached to the reservation as descriptive context, not used as
-- an availability filter.
create or replace function public.create_partner_itinerary(p_stops jsonb,p_contact_phone text,p_is_multi_property boolean)
returns uuid
language plpgsql security definer set search_path=public,auth,pg_temp
as $$
declare v_id uuid;v_stop jsonb;v_stop_id uuid;v_property_text text;v_property_id uuid;v_benefit_id uuid;v_rank int;v_position int:=0;v_email text;v_payload jsonb;v_a record;v_b record;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='member' and membership_state::text='active') then raise exception 'Active membership is required to create a reservation'; end if;
  if exists(select 1 from public.partner_itineraries where member_id=auth.uid() and status not in ('declined','cancelled','completed')) then raise exception 'You already have an active or upcoming reservation'; end if;
  if jsonb_typeof(p_stops)<>'array' or jsonb_array_length(p_stops) not between 1 and 3 then raise exception 'A reservation must contain between one and three properties'; end if;
  if not p_is_multi_property and jsonb_array_length(p_stops)<>1 then raise exception 'Enable itinerary mode to add more properties'; end if;
  if char_length(trim(coalesce(p_contact_phone,''))) not between 7 and 30 then raise exception 'A valid contact number is required'; end if;
  insert into public.partner_itineraries(member_id,is_multi_property,contact_phone) values(auth.uid(),p_is_multi_property,trim(p_contact_phone)) returning id into v_id;
  for v_stop in select value from jsonb_array_elements(p_stops) loop
    v_position:=v_position+1;
    if (v_stop->>'arrival_date')::date<current_date or (v_stop->>'departure_date')::date<(v_stop->>'arrival_date')::date then raise exception 'Stop % has invalid dates',v_position; end if;
    if jsonb_array_length(coalesce(v_stop->'property_ids','[]'::jsonb)) not between 1 and 3 then raise exception 'Stop % needs a first choice and no more than two alternatives',v_position; end if;
    if (select count(distinct value) from jsonb_array_elements_text(v_stop->'property_ids'))<>jsonb_array_length(v_stop->'property_ids') then raise exception 'A property cannot be repeated within the same stop'; end if;
    insert into public.partner_itinerary_stops(itinerary_id,position,arrival_date,departure_date,arrival_time,departure_time,adults,children,rooms,special_requests)
    values(v_id,v_position,(v_stop->>'arrival_date')::date,(v_stop->>'departure_date')::date,nullif(v_stop->>'arrival_time','')::time,nullif(v_stop->>'departure_time','')::time,
      (v_stop->>'adults')::int,coalesce((v_stop->>'children')::int,0),coalesce((v_stop->>'rooms')::int,1),nullif(trim(v_stop->>'special_requests'),'')) returning id into v_stop_id;
    v_rank:=0;
    for v_property_text in select value from jsonb_array_elements_text(v_stop->'property_ids') loop
      v_rank:=v_rank+1;v_property_id:=v_property_text::uuid;v_benefit_id:=null;
      select b.id into v_benefit_id
      from public.partner_properties pp
      join public.partners p on p.id=pp.partner_id
      join public.benefits b on b.partner_id=p.id
      where pp.id=v_property_id
        and nullif(trim(pp.reservation_email),'') is not null
        and nullif(trim(pp.reservation_phone),'') is not null
      order by b.id limit 1;
      if v_benefit_id is null then raise exception 'The selected partner does not have its benefit package configured'; end if;
      insert into public.partner_itinerary_choices(stop_id,rank,property_id,benefit_id,status) values(v_stop_id,v_rank,v_property_id,v_benefit_id,case when v_rank=1 then 'current' else 'queued' end);
    end loop;
  end loop;
  for v_a in select * from public.partner_itinerary_stops where itinerary_id=v_id loop for v_b in select * from public.partner_itinerary_stops where itinerary_id=v_id and position>v_a.position loop
    if v_a.departure_date>=v_b.arrival_date and v_b.departure_date>=v_a.arrival_date then
      if v_a.arrival_time is null or v_b.arrival_time is null then raise exception 'Stops % and % share or overlap dates. Add arrival and departure times to both stops.',v_a.position,v_b.position; end if;
      if (v_a.arrival_date+v_a.arrival_time)<(v_b.departure_date+v_b.departure_time) and (v_b.arrival_date+v_b.arrival_time)<(v_a.departure_date+v_a.departure_time) then raise exception 'Stops % and % still overlap after their times are considered',v_a.position,v_b.position; end if;
    end if;
  end loop;end loop;
  select email into v_email from auth.users where id=auth.uid();v_payload:=public.reservation_notification_payload(v_id);
  insert into public.reservation_notifications(itinerary_id,event_name,channel,audience,recipient_address,status,payload) values
    (v_id,'itinerary_requested','email','member',v_email,'pending',v_payload),(v_id,'itinerary_requested','email','one_club',null,'pending',v_payload),(v_id,'itinerary_requested','whatsapp','member',trim(p_contact_phone),'awaiting_configuration',v_payload);
  insert into public.reservation_notifications(itinerary_id,stop_id,choice_id,event_name,channel,audience,recipient_address,status,payload)
  select v_id,s.id,c.id,'property_request','email','property',pp.reservation_email,'pending',public.reservation_notification_payload(v_id,s.id,c.id)
  from public.partner_itinerary_stops s join public.partner_itinerary_choices c on c.stop_id=s.id and c.status='current' join public.partner_properties pp on pp.id=c.property_id where s.itinerary_id=v_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'partner_itinerary.created','partner_itinerary',v_id::text,jsonb_build_object('stops',jsonb_array_length(p_stops)));
  return v_id;
end;
$$;

revoke all on function public.get_member_reservation_options() from public,anon;
grant execute on function public.get_member_reservation_options() to authenticated;
revoke all on function public.create_partner_itinerary(jsonb,text,boolean) from public,anon;
grant execute on function public.create_partner_itinerary(jsonb,text,boolean) to authenticated;

commit;
