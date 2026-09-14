begin;

create or replace function public.finalize_member_account_anonymization(p_member_id uuid,p_original_email text)
returns jsonb language plpgsql security definer set search_path=public,auth,oneclub_legacy,pg_temp as $$
declare v_ref uuid:=gen_random_uuid();v_tombstone text;v_legacy_active boolean:=false;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Service role required';end if;
  if not exists(select 1 from public.profiles where id=p_member_id and app_role::text='member') then raise exception 'Member account not found';end if;

  -- Re-check every blocker inside the mutation transaction using the supplied member id.
  if exists(select 1 from public.event_bookings b join public.events e on e.id=b.event_id where b.member_id=p_member_id and e.starts_at>now() and (b.status::text='confirmed' or (b.status::text='pending_payment' and b.reservation_expires_at>now()))) then raise exception 'Upcoming event bookings must be resolved first';end if;
  if exists(select 1 from public.partner_itineraries where member_id=p_member_id and status not in ('declined','cancelled','completed')) then raise exception 'Upcoming property bookings must be resolved first';end if;
  if to_regclass('oneclub_legacy.partner_reservations') is not null then
    execute 'select exists(select 1 from oneclub_legacy.partner_reservations where member_id=$1 and status::text not in (''declined'',''cancelled'',''completed''))' into v_legacy_active using p_member_id;
    if v_legacy_active then raise exception 'Upcoming legacy property bookings must be resolved first';end if;
  end if;
  if exists(select 1 from public.event_bookings b left join public.refund_requests r on r.booking_id=b.id where b.member_id=p_member_id and (b.payment_status::text='refund_pending' or r.status in ('requested','processing','failed'))) then raise exception 'Pending refunds must be resolved first';end if;

  v_tombstone:='removed+'||replace(p_member_id::text,'-','')||'@deleted.invalid';
  update public.booking_guests g set guest_name='Removed guest' from public.event_bookings b where g.booking_id=b.id and b.member_id=p_member_id;
  update public.event_bookings set guest_name=null where member_id=p_member_id;
  update public.member_admin_notes set note='Account record removed by member request.' where member_id=p_member_id;
  update public.member_support_requests set message='Content removed following account deletion.' where user_id=p_member_id;
  update public.partner_itineraries set contact_phone='Removed' where member_id=p_member_id;
  update public.partner_itinerary_stops s set special_requests=null,member_message=null
    from public.partner_itineraries i where s.itinerary_id=i.id and i.member_id=p_member_id;
  update public.reservation_notifications n set recipient_address=case when audience='member' then null else recipient_address end,
    payload=payload-'member_name'-'member_email'-'contact_phone'-'special_requests'-'member_message'
    from public.partner_itineraries i where n.itinerary_id=i.id and i.member_id=p_member_id;
  update public.membership_invitations set created_by=null where created_by=p_member_id;
  update public.membership_invitations set used_by=null where used_by=p_member_id;
  update public.membership_invitations set email=v_tombstone,expires_at=least(expires_at,now()) where lower(email)=lower(trim(p_original_email));
  update public.enquiries set full_name='Removed user',email=v_tombstone,phone='00000000',marketing_consent=false,internal_notes=null,status='archived',updated_at=now()
    where lower(email)=lower(trim(p_original_email));
  delete from public.account_deletion_support_contexts where member_id=p_member_id;
  update public.profiles set full_name='Removed user',phone=null,birthday=null,locality=null,interests='{}',profession=null,industry=null,avatar_url=null,
    membership_state='cancelled',member_number=null,founding_member_sequence=null,membership_plan=null,membership_started_at=null,membership_expires_at=null,
    pending_membership_plan=null,pending_membership_source=null,membership_status_context=null,payment_offer_expires_at=null,
    deleted_at=now(),deletion_reference=v_ref,updated_at=now() where id=p_member_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
    values(null,'member.account_deleted','member',p_member_id::text,jsonb_build_object('deletion_reference',v_ref));
  delete from auth.users where id=p_member_id;
  if not found then raise exception 'Authentication account was not removed';end if;
  return jsonb_build_object('deletion_reference',v_ref,'tombstone_email',v_tombstone);
end;$$;

revoke all on function public.finalize_member_account_anonymization(uuid,text) from public,anon,authenticated;
grant execute on function public.finalize_member_account_anonymization(uuid,text) to service_role;

commit;
