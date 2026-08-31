begin;

alter table public.partner_properties add column if not exists reservation_email text;
alter table public.partner_properties add column if not exists reservation_phone text;

create table public.partner_itineraries (
  id uuid primary key default gen_random_uuid(), member_id uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'awaiting_coordination' check(status in ('awaiting_coordination','partially_confirmed','confirmed','change_in_progress','cancellation_in_progress','partially_cancelled','declined','cancelled','completed')),
  is_multi_property boolean not null default false, contact_phone text not null check(char_length(trim(contact_phone)) between 7 and 30),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index partner_itineraries_one_open_per_member on public.partner_itineraries(member_id)
where status not in ('declined','cancelled','completed');
create index partner_itineraries_status_created_idx on public.partner_itineraries(status,created_at);

create table public.partner_itinerary_stops (
  id uuid primary key default gen_random_uuid(), itinerary_id uuid not null references public.partner_itineraries(id) on delete cascade,
  position smallint not null check(position between 1 and 3), status text not null default 'awaiting_coordination'
    check(status in ('awaiting_coordination','contacting_property','confirmed','awaiting_alternative','declined','change_requested','cancellation_requested','cancelled','completed')),
  arrival_date date not null, departure_date date not null, arrival_time time, departure_time time,
  adults integer not null check(adults between 1 and 50), children integer not null default 0 check(children between 0 and 50),
  rooms integer not null default 1 check(rooms between 1 and 25), special_requests text check(special_requests is null or char_length(special_requests)<=1000),
  member_message text check(member_message is null or char_length(member_message)<=1000), property_reference text check(property_reference is null or char_length(property_reference)<=160),
  updated_at timestamptz not null default now(), unique(itinerary_id,position), check(departure_date>=arrival_date),
  check((arrival_time is null and departure_time is null) or (arrival_time is not null and departure_time is not null))
);

create table public.partner_itinerary_choices (
  id uuid primary key default gen_random_uuid(), stop_id uuid not null references public.partner_itinerary_stops(id) on delete cascade,
  rank smallint not null check(rank between 1 and 3), property_id uuid not null references public.partner_properties(id) on delete restrict,
  benefit_id uuid not null references public.benefits(id) on delete restrict, status text not null default 'queued'
    check(status in ('queued','current','contacting','confirmed','declined','cancelled')),
  contacted_at timestamptz, decided_at timestamptz, unique(stop_id,rank), unique(stop_id,property_id)
);
create unique index partner_itinerary_choices_one_live_choice on public.partner_itinerary_choices(stop_id)
where status in ('current','contacting','confirmed');

create table public.partner_itinerary_change_requests (
  id uuid primary key default gen_random_uuid(), itinerary_id uuid not null references public.partner_itineraries(id) on delete cascade,
  stop_id uuid references public.partner_itinerary_stops(id) on delete cascade, request_type text not null check(request_type in ('cancel_stop','cancel_itinerary')),
  reason text not null check(char_length(trim(reason)) between 5 and 1000), status text not null default 'requested' check(status in ('requested','awaiting_property','approved','declined')),
  previous_state jsonb not null default '{}'::jsonb, staff_note text, created_at timestamptz not null default now(), resolved_at timestamptz, resolved_by uuid references public.profiles(id) on delete set null
);

create table public.reservation_notifications (
  id uuid primary key default gen_random_uuid(), itinerary_id uuid not null references public.partner_itineraries(id) on delete cascade,
  stop_id uuid references public.partner_itinerary_stops(id) on delete cascade, choice_id uuid references public.partner_itinerary_choices(id) on delete cascade,
  event_name text not null, channel text not null check(channel in ('email','whatsapp')), audience text not null check(audience in ('member','property','one_club')),
  recipient_address text, status text not null default 'pending' check(status in ('pending','processing','sent','failed','awaiting_configuration')),
  payload jsonb not null default '{}'::jsonb, attempts integer not null default 0, provider_message_id text, last_error text,
  created_at timestamptz not null default now(), processed_at timestamptz,
  unique(itinerary_id,event_name,channel,audience,stop_id,choice_id)
);
create index reservation_notifications_delivery_idx on public.reservation_notifications(status,channel,created_at);

alter table public.partner_itineraries enable row level security;
alter table public.partner_itinerary_stops enable row level security;
alter table public.partner_itinerary_choices enable row level security;
alter table public.partner_itinerary_change_requests enable row level security;
alter table public.reservation_notifications enable row level security;
revoke all on table public.partner_itineraries,public.partner_itinerary_stops,public.partner_itinerary_choices,public.partner_itinerary_change_requests,public.reservation_notifications from public,anon,authenticated;

create or replace function public.can_manage_partner_reservations() returns boolean language sql stable security definer set search_path=public,pg_temp as $$
select exists(select 1 from public.profiles where id=auth.uid() and (app_role::text='admin' or (app_role::text='staff' and staff_role::text='general')));
$$;

create or replace function public.save_partner_property_contact(p_property_id uuid,p_email text,p_phone text) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.can_manage_partner_content() then raise exception 'Partner and benefit management permission required'; end if;
  if nullif(trim(coalesce(p_email,'')),'') is not null and trim(p_email) !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Enter a valid reservation email address'; end if;
  update public.partner_properties set reservation_email=nullif(lower(trim(p_email)),''),reservation_phone=nullif(trim(p_phone),''),updated_at=now() where id=p_property_id;
  if not found then raise exception 'Partner location not found'; end if;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'partner_property.contact_updated','partner_property',p_property_id::text,jsonb_build_object('has_email',nullif(trim(coalesce(p_email,'')),'') is not null));
end; $$;

create or replace function public.get_member_reservation_options() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_result jsonb;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='member' and membership_state::text='active') then raise exception 'Active membership is required to create a reservation'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('property_id',pp.id,'partner_id',p.id,'partner_name',p.name,'property_name',pp.name,'address',pp.address,'is_primary',pp.is_primary) order by p.name,pp.is_primary desc,pp.name),'[]'::jsonb) into v_result
  from public.partner_properties pp join public.partners p on p.id=pp.partner_id
  where nullif(trim(pp.reservation_email),'') is not null
    and nullif(trim(pp.reservation_phone),'') is not null;
  return v_result;
end; $$;

create or replace function public.refresh_partner_itinerary_status(p_itinerary_id uuid) returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v_total int;v_confirmed int;v_declined int;v_cancelled int;v_cancel_pending int;v_change_pending int;v_status text;
begin
  select count(*),count(*) filter(where status='confirmed'),count(*) filter(where status='declined'),count(*) filter(where status='cancelled'),count(*) filter(where status='cancellation_requested'),count(*) filter(where status='change_requested')
  into v_total,v_confirmed,v_declined,v_cancelled,v_cancel_pending,v_change_pending from public.partner_itinerary_stops where itinerary_id=p_itinerary_id;
  v_status:=case when v_cancel_pending>0 then 'cancellation_in_progress' when v_change_pending>0 then 'change_in_progress'
    when v_cancelled=v_total then 'cancelled' when v_declined+v_cancelled=v_total and v_confirmed=0 then 'declined'
    when v_confirmed>0 and v_confirmed+v_cancelled=v_total then case when v_cancelled>0 then 'partially_cancelled' else 'confirmed' end
    when v_confirmed>0 then 'partially_confirmed' else 'awaiting_coordination' end;
  update public.partner_itineraries set status=v_status,updated_at=now() where id=p_itinerary_id; return v_status;
end; $$;

create or replace function public.reservation_notification_payload(p_itinerary_id uuid,p_stop_id uuid default null,p_choice_id uuid default null) returns jsonb language sql stable security definer set search_path=public,auth,pg_temp as $$
select jsonb_build_object('reservation_id',i.id,'member_name',coalesce(pr.full_name,u.email),'member_email',u.email,'contact_phone',i.contact_phone,'itinerary_status',i.status,
  'stop_id',s.id,'stop_position',s.position,'stop_status',s.status,'arrival_date',s.arrival_date,'departure_date',s.departure_date,'arrival_time',s.arrival_time,'departure_time',s.departure_time,
  'adults',s.adults,'children',s.children,'rooms',s.rooms,'special_requests',s.special_requests,'member_message',s.member_message,'property_reference',s.property_reference,
  'partner_name',p.name,'property_name',pp.name,'benefit_title',b.title)
from public.partner_itineraries i join public.profiles pr on pr.id=i.member_id join auth.users u on u.id=i.member_id
left join public.partner_itinerary_stops s on s.itinerary_id=i.id and (p_stop_id is null or s.id=p_stop_id)
left join public.partner_itinerary_choices c on c.stop_id=s.id and (p_choice_id is null and c.status in ('current','contacting','confirmed') or c.id=p_choice_id)
left join public.partner_properties pp on pp.id=c.property_id left join public.partners p on p.id=pp.partner_id left join public.benefits b on b.id=c.benefit_id
where i.id=p_itinerary_id order by s.position limit 1;
$$;

create or replace function public.create_partner_itinerary(p_stops jsonb,p_contact_phone text,p_is_multi_property boolean) returns uuid language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_id uuid;v_stop jsonb;v_stop_id uuid;v_property_text text;v_property_id uuid;v_benefit_id uuid;v_rank int;v_position int:=0;v_count int;v_email text;v_payload jsonb;v_a record;v_b record;
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
      v_rank:=v_rank+1;v_property_id:=v_property_text::uuid;
      select b.id into v_benefit_id from public.partner_properties pp join public.partners p on p.id=pp.partner_id join public.benefits b on b.partner_id=p.id
      where pp.id=v_property_id and nullif(trim(pp.reservation_email),'') is not null and nullif(trim(pp.reservation_phone),'') is not null order by b.id limit 1;
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
end; $$;

create or replace function public.get_my_partner_itineraries() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_result jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'status',i.status,'is_multi_property',i.is_multi_property,'contact_phone',i.contact_phone,'created_at',i.created_at,
    'open_change_request',cr.request,'stops',(select jsonb_agg(jsonb_build_object('id',s.id,'position',s.position,'status',s.status,'arrival_date',s.arrival_date,'departure_date',s.departure_date,'arrival_time',s.arrival_time,'departure_time',s.departure_time,'adults',s.adults,'children',s.children,'rooms',s.rooms,'special_requests',s.special_requests,'member_message',s.member_message,'property_reference',s.property_reference,
      'choices',(select jsonb_agg(jsonb_build_object('id',c.id,'rank',c.rank,'status',c.status,'partner_name',p.name,'property_name',pp.name,'address',pp.address,'benefit_title',b.title) order by c.rank) from public.partner_itinerary_choices c join public.partner_properties pp on pp.id=c.property_id join public.partners p on p.id=pp.partner_id join public.benefits b on b.id=c.benefit_id where c.stop_id=s.id)) order by s.position) from public.partner_itinerary_stops s where s.itinerary_id=i.id)) order by i.created_at desc),'[]'::jsonb) into v_result
  from public.partner_itineraries i left join lateral(select jsonb_build_object('id',x.id,'type',x.request_type,'stop_id',x.stop_id,'status',x.status) request from public.partner_itinerary_change_requests x where x.itinerary_id=i.id and x.status in ('requested','awaiting_property') order by x.created_at desc limit 1) cr on true where i.member_id=auth.uid();return v_result;
end; $$;

create or replace function public.list_partner_itineraries_for_staff(p_status text default null) returns jsonb language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_result jsonb;
begin
  if not public.can_manage_partner_reservations() then raise exception 'Reservation operations permission required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'status',i.status,'is_multi_property',i.is_multi_property,'contact_phone',i.contact_phone,'created_at',i.created_at,'member_name',pr.full_name,'member_email',u.email,'member_number',pr.member_number,
    'change_requests',(select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'type',x.request_type,'stop_id',x.stop_id,'reason',x.reason,'status',x.status,'created_at',x.created_at)),'[]'::jsonb) from public.partner_itinerary_change_requests x where x.itinerary_id=i.id and x.status in ('requested','awaiting_property')),
    'stops',(select jsonb_agg(jsonb_build_object('id',s.id,'position',s.position,'status',s.status,'arrival_date',s.arrival_date,'departure_date',s.departure_date,'arrival_time',s.arrival_time,'departure_time',s.departure_time,'adults',s.adults,'children',s.children,'rooms',s.rooms,'special_requests',s.special_requests,'member_message',s.member_message,'property_reference',s.property_reference,
      'choices',(select jsonb_agg(jsonb_build_object('id',c.id,'rank',c.rank,'status',c.status,'partner_name',p.name,'property_name',pp.name,'address',pp.address,'reservation_email',pp.reservation_email,'reservation_phone',pp.reservation_phone,'benefit_title',b.title) order by c.rank) from public.partner_itinerary_choices c join public.partner_properties pp on pp.id=c.property_id join public.partners p on p.id=pp.partner_id join public.benefits b on b.id=c.benefit_id where c.stop_id=s.id)) order by s.position) from public.partner_itinerary_stops s where s.itinerary_id=i.id)) order by i.created_at),'[]'::jsonb) into v_result
  from public.partner_itineraries i join public.profiles pr on pr.id=i.member_id join auth.users u on u.id=i.member_id where p_status is null or i.status=p_status;return v_result;
end; $$;

create or replace function public.update_partner_itinerary_stop(p_stop_id uuid,p_status text,p_member_message text,p_property_reference text default null) returns uuid language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_itinerary uuid;v_choice uuid;v_member uuid;v_email text;v_phone text;v_next int;v_event text;v_payload jsonb;
begin
  if not public.can_manage_partner_reservations() then raise exception 'Reservation operations permission required'; end if;
  if p_status not in ('contacting_property','confirmed','declined') then raise exception 'Invalid stop status'; end if;
  if p_status in ('confirmed','declined') and char_length(trim(coalesce(p_member_message,'')))<5 then raise exception 'Add a clear update for the member'; end if;
  select s.itinerary_id,c.id,i.member_id,i.contact_phone into v_itinerary,v_choice,v_member,v_phone from public.partner_itinerary_stops s join public.partner_itineraries i on i.id=s.itinerary_id join public.partner_itinerary_choices c on c.stop_id=s.id and c.status in ('current','contacting') where s.id=p_stop_id for update of s;
  if v_itinerary is null then raise exception 'This stop has no active property choice'; end if;
  if p_status='contacting_property' then update public.partner_itinerary_stops set status=p_status,updated_at=now() where id=p_stop_id;update public.partner_itinerary_choices set status='contacting',contacted_at=coalesce(contacted_at,now()) where id=v_choice;
  elsif p_status='confirmed' then update public.partner_itinerary_stops set status='confirmed',member_message=trim(p_member_message),property_reference=nullif(trim(p_property_reference),''),updated_at=now() where id=p_stop_id;update public.partner_itinerary_choices set status='confirmed',decided_at=now() where id=v_choice;
  else update public.partner_itinerary_choices set status='declined',decided_at=now() where id=v_choice;select count(*) into v_next from public.partner_itinerary_choices where stop_id=p_stop_id and status='queued';update public.partner_itinerary_stops set status=case when v_next>0 then 'awaiting_alternative' else 'declined' end,member_message=trim(p_member_message),updated_at=now() where id=p_stop_id;end if;
  perform public.refresh_partner_itinerary_status(v_itinerary);select email into v_email from auth.users where id=v_member;v_event:='stop_'||p_status;v_payload:=public.reservation_notification_payload(v_itinerary,p_stop_id,v_choice);
  if p_status in ('confirmed','declined') then insert into public.reservation_notifications(itinerary_id,stop_id,choice_id,event_name,channel,audience,recipient_address,status,payload) values
    (v_itinerary,p_stop_id,v_choice,v_event,'email','member',v_email,'pending',v_payload),(v_itinerary,p_stop_id,v_choice,v_event,'whatsapp','member',v_phone,'awaiting_configuration',v_payload);end if;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'partner_itinerary_stop.'||p_status,'partner_itinerary_stop',p_stop_id::text,jsonb_build_object('itinerary_id',v_itinerary,'choice_id',v_choice));return v_itinerary;
end; $$;

create or replace function public.promote_partner_itinerary_choice(p_stop_id uuid,p_choice_id uuid) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_itinerary uuid;v_email text;v_payload jsonb;
begin
  if not public.can_manage_partner_reservations() then raise exception 'Reservation operations permission required'; end if;
  select itinerary_id into v_itinerary from public.partner_itinerary_stops where id=p_stop_id and status='awaiting_alternative' for update;if v_itinerary is null then raise exception 'This stop is not awaiting an alternative';end if;
  update public.partner_itinerary_choices set status='current' where id=p_choice_id and stop_id=p_stop_id and status='queued';if not found then raise exception 'Alternative property is unavailable';end if;
  update public.partner_itinerary_stops set status='awaiting_coordination',member_message=null,updated_at=now() where id=p_stop_id;
  select pp.reservation_email into v_email from public.partner_itinerary_choices c join public.partner_properties pp on pp.id=c.property_id where c.id=p_choice_id;v_payload:=public.reservation_notification_payload(v_itinerary,p_stop_id,p_choice_id);
  insert into public.reservation_notifications(itinerary_id,stop_id,choice_id,event_name,channel,audience,recipient_address,status,payload) values(v_itinerary,p_stop_id,p_choice_id,'property_request','email','property',v_email,'pending',v_payload);
  perform public.refresh_partner_itinerary_status(v_itinerary);insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'partner_itinerary_choice.promoted','partner_itinerary_choice',p_choice_id::text,jsonb_build_object('itinerary_id',v_itinerary));return v_itinerary;
end; $$;

create or replace function public.request_partner_itinerary_cancellation(p_itinerary_id uuid,p_stop_id uuid,p_reason text) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_request uuid;v_previous jsonb;v_phone text;
begin
  if char_length(trim(coalesce(p_reason,'')))<5 then raise exception 'Please explain why you need to cancel';end if;
  select contact_phone into v_phone from public.partner_itineraries where id=p_itinerary_id and member_id=auth.uid() and status not in ('declined','cancelled','completed') for update;if v_phone is null then raise exception 'Active itinerary not found';end if;
  if exists(select 1 from public.partner_itinerary_change_requests where itinerary_id=p_itinerary_id and status in ('requested','awaiting_property')) then raise exception 'A reservation request is already being reviewed';end if;
  if p_stop_id is null then select jsonb_object_agg(id::text,status) into v_previous from public.partner_itinerary_stops where itinerary_id=p_itinerary_id and status not in ('cancelled','declined');update public.partner_itinerary_stops set status='cancellation_requested',updated_at=now() where itinerary_id=p_itinerary_id and status not in ('cancelled','declined');
  else select jsonb_build_object(p_stop_id::text,status) into v_previous from public.partner_itinerary_stops where id=p_stop_id and itinerary_id=p_itinerary_id and status not in ('cancelled','declined');if v_previous is null then raise exception 'Active itinerary stop not found';end if;update public.partner_itinerary_stops set status='cancellation_requested',updated_at=now() where id=p_stop_id;end if;
  insert into public.partner_itinerary_change_requests(itinerary_id,stop_id,request_type,reason,previous_state) values(p_itinerary_id,p_stop_id,case when p_stop_id is null then 'cancel_itinerary' else 'cancel_stop' end,trim(p_reason),v_previous) returning id into v_request;
  perform public.refresh_partner_itinerary_status(p_itinerary_id);insert into public.reservation_notifications(itinerary_id,stop_id,event_name,channel,audience,recipient_address,status,payload) values(p_itinerary_id,p_stop_id,'cancellation_requested','email','one_club',null,'pending',public.reservation_notification_payload(p_itinerary_id,p_stop_id)),(p_itinerary_id,p_stop_id,'cancellation_requested','whatsapp','member',v_phone,'awaiting_configuration',public.reservation_notification_payload(p_itinerary_id,p_stop_id));return v_request;
end; $$;

create or replace function public.resolve_partner_itinerary_cancellation(p_request_id uuid,p_approved boolean,p_staff_note text) returns uuid language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_request record;v_pair record;v_email text;v_phone text;v_event text;
begin
  if not public.can_manage_partner_reservations() then raise exception 'Reservation operations permission required';end if;if char_length(trim(coalesce(p_staff_note,'')))<5 then raise exception 'Add a clear update for the member';end if;
  select * into v_request from public.partner_itinerary_change_requests where id=p_request_id and status in ('requested','awaiting_property') for update;if not found then raise exception 'Open cancellation request not found';end if;
  if p_approved then if v_request.stop_id is null then update public.partner_itinerary_stops set status='cancelled',member_message=trim(p_staff_note),updated_at=now() where itinerary_id=v_request.itinerary_id and status='cancellation_requested';else update public.partner_itinerary_stops set status='cancelled',member_message=trim(p_staff_note),updated_at=now() where id=v_request.stop_id;end if;update public.partner_itinerary_choices c set status='cancelled',decided_at=now() from public.partner_itinerary_stops s where c.stop_id=s.id and s.itinerary_id=v_request.itinerary_id and (v_request.stop_id is null or s.id=v_request.stop_id) and c.status in ('current','contacting','confirmed');
  else for v_pair in select key,value from jsonb_each_text(v_request.previous_state) loop update public.partner_itinerary_stops set status=v_pair.value,member_message=trim(p_staff_note),updated_at=now() where id=v_pair.key::uuid;end loop;end if;
  update public.partner_itinerary_change_requests set status=case when p_approved then 'approved' else 'declined' end,staff_note=trim(p_staff_note),resolved_at=now(),resolved_by=auth.uid() where id=p_request_id;perform public.refresh_partner_itinerary_status(v_request.itinerary_id);if p_approved and v_request.stop_id is null then update public.partner_itineraries set status='cancelled',updated_at=now() where id=v_request.itinerary_id;end if;
  select u.email,i.contact_phone into v_email,v_phone from public.partner_itineraries i join auth.users u on u.id=i.member_id where i.id=v_request.itinerary_id;v_event:=case when p_approved then 'cancellation_approved' else 'cancellation_declined' end;
  insert into public.reservation_notifications(itinerary_id,stop_id,event_name,channel,audience,recipient_address,status,payload) values(v_request.itinerary_id,v_request.stop_id,v_event,'email','member',v_email,'pending',public.reservation_notification_payload(v_request.itinerary_id,v_request.stop_id)),(v_request.itinerary_id,v_request.stop_id,v_event,'whatsapp','member',v_phone,'awaiting_configuration',public.reservation_notification_payload(v_request.itinerary_id,v_request.stop_id));return v_request.itinerary_id;
end; $$;

create or replace function public.process_partner_itinerary_lifecycle() returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_count int;
begin
  update public.partner_itinerary_stops set status='completed',updated_at=now() where status='confirmed' and ((departure_date+coalesce(departure_time,time '23:59')) at time zone 'Asia/Kolkata')<now();get diagnostics v_count=row_count;
  update public.partner_itineraries i set status='completed',updated_at=now() where status in ('confirmed','partially_cancelled') and not exists(select 1 from public.partner_itinerary_stops s where s.itinerary_id=i.id and s.status not in ('completed','cancelled','declined'));return v_count;
end; $$;

create or replace function public.claim_reservation_email_notifications(p_reservation_id uuid,p_actor_id uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_allowed boolean;v_result jsonb;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Service role required';end if;
  select exists(select 1 from public.partner_itineraries i where i.id=p_reservation_id and (i.member_id=p_actor_id or exists(select 1 from public.profiles p where p.id=p_actor_id and (p.app_role::text='admin' or (p.app_role::text='staff' and p.staff_role::text='general'))))) into v_allowed;if not v_allowed then raise exception 'Reservation access denied';end if;
  update public.reservation_notifications set status='processing',attempts=attempts+1,last_error=null where itinerary_id=p_reservation_id and channel='email' and status in ('pending','failed');
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'audience',audience,'recipient_address',recipient_address,'event_name',event_name,'payload',payload)),'[]'::jsonb) into v_result from public.reservation_notifications where itinerary_id=p_reservation_id and channel='email' and status='processing';return v_result;
end; $$;

create or replace function public.complete_reservation_notification(p_notification_id uuid,p_sent boolean,p_provider_message_id text,p_error text) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Service role required';end if;update public.reservation_notifications set status=case when p_sent then 'sent' else 'failed' end,provider_message_id=case when p_sent then p_provider_message_id else null end,last_error=case when p_sent then null else left(p_error,500) end,processed_at=case when p_sent then now() else null end where id=p_notification_id and status='processing';end; $$;

create or replace function public.list_partner_properties_for_management() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_result jsonb;begin if not public.can_manage_partner_content() then raise exception 'Partner and benefit management permission required';end if;select coalesce(jsonb_agg(jsonb_build_object('id',pp.id,'partner_id',pp.partner_id,'partner_name',p.name,'name',pp.name,'slug',pp.slug,'address',pp.address,'status',pp.status,'is_primary',pp.is_primary,'reservation_email',pp.reservation_email,'reservation_phone',pp.reservation_phone,'created_at',pp.created_at,'updated_at',pp.updated_at) order by p.name,pp.is_primary desc,pp.name),'[]'::jsonb) into v_result from public.partner_properties pp join public.partners p on p.id=pp.partner_id;return v_result;end; $$;

revoke all on function public.can_manage_partner_reservations(),public.refresh_partner_itinerary_status(uuid),public.reservation_notification_payload(uuid,uuid,uuid),public.process_partner_itinerary_lifecycle(),public.claim_reservation_email_notifications(uuid,uuid),public.complete_reservation_notification(uuid,boolean,text,text) from public,anon,authenticated;
grant execute on function public.save_partner_property_contact(uuid,text,text),public.get_member_reservation_options(),public.create_partner_itinerary(jsonb,text,boolean),public.get_my_partner_itineraries(),public.list_partner_itineraries_for_staff(text),public.update_partner_itinerary_stop(uuid,text,text,text),public.promote_partner_itinerary_choice(uuid,uuid),public.request_partner_itinerary_cancellation(uuid,uuid,text),public.resolve_partner_itinerary_cancellation(uuid,boolean,text) to authenticated;
grant execute on function public.claim_reservation_email_notifications(uuid,uuid),public.complete_reservation_notification(uuid,boolean,text,text) to service_role;

create extension if not exists pg_cron with schema extensions;
select cron.schedule('oneclub-partner-itinerary-lifecycle','35 * * * *','select public.process_partner_itinerary_lifecycle();');

commit;
