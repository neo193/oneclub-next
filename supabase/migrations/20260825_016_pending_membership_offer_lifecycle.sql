begin;

alter table public.profiles add column if not exists membership_status_context text;
alter table public.profiles drop constraint if exists profiles_membership_status_context_check;
alter table public.profiles add constraint profiles_membership_status_context_check
  check (membership_status_context is null or membership_status_context in ('pending_offer_revoked','membership_cancelled'));

create or replace function public.track_membership_status_context()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if new.membership_state::text='cancelled' and old.membership_state::text='payment_pending' then new.membership_status_context:='pending_offer_revoked';
  elsif new.membership_state::text='cancelled' and old.membership_state::text in ('active','suspended') then new.membership_status_context:='membership_cancelled';
  elsif new.membership_state::text in ('active','payment_pending') then new.membership_status_context:=null;
  end if;
  return new;
end;
$$;

drop trigger if exists track_membership_status_context_trigger on public.profiles;
create trigger track_membership_status_context_trigger before update of membership_state on public.profiles
for each row execute function public.track_membership_status_context();

create or replace function public.admin_cancel_membership(p_member_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_previous text;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then raise exception 'Administrator permission required'; end if;
  if char_length(trim(coalesce(p_reason,'')))<3 then raise exception 'Cancellation reason is required'; end if;
  select membership_state::text into v_previous from public.profiles where id=p_member_id and app_role::text='member' for update;
  if v_previous not in ('active','suspended') then raise exception 'Only an active or suspended membership can be cancelled'; end if;
  update public.profiles set membership_state='cancelled',updated_at=now() where id=p_member_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'membership.cancelled','member',p_member_id::text,jsonb_build_object('previous_state',v_previous,'reason',trim(p_reason)));
end;
$$;

create or replace function public.admin_revoke_pending_membership_offer(p_member_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then raise exception 'Administrator permission required'; end if;
  if char_length(trim(coalesce(p_reason,'')))<3 then raise exception 'Revocation reason is required'; end if;
  if not exists(select 1 from public.profiles where id=p_member_id and app_role::text='member' and membership_state::text='payment_pending' for update) then
    raise exception 'Only a payment-pending membership offer can be revoked';
  end if;
  update public.profiles set membership_state='cancelled',pending_membership_plan=null,pending_membership_source=null,updated_at=now() where id=p_member_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'membership.pending_offer_revoked','member',p_member_id::text,jsonb_build_object('reason',trim(p_reason)));
end;
$$;

create or replace function public.admin_restore_pending_membership_offer(p_member_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then raise exception 'Administrator permission required'; end if;
  if char_length(trim(coalesce(p_reason,'')))<3 then raise exception 'Restoration reason is required'; end if;
  if not exists(select 1 from public.profiles p where p.id=p_member_id and p.app_role::text='member'
    and p.membership_state::text='cancelled' and p.membership_status_context='pending_offer_revoked' for update)
  then raise exception 'This account is not a revoked pending membership offer'; end if;
  update public.profiles set membership_state='payment_pending',updated_at=now() where id=p_member_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'membership.pending_offer_restored','member',p_member_id::text,jsonb_build_object('reason',trim(p_reason)));
end;
$$;

create or replace function public.admin_restore_membership(p_member_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_state text; v_plan text; v_context text;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and app_role::text='admin') then raise exception 'Administrator permission required'; end if;
  if char_length(trim(coalesce(p_reason,'')))<3 then raise exception 'Reason is required'; end if;
  select membership_state::text,case when founding_member_sequence is not null then 'founding_lifetime' else 'annual' end,membership_status_context into v_state,v_plan,v_context
  from public.profiles where id=p_member_id and app_role::text='member' for update;
  if v_state not in ('cancelled','expired') then raise exception 'Only a cancelled or expired membership can be restored'; end if;
  if v_context='pending_offer_revoked' then raise exception 'This is a revoked pending offer. Restore the offer instead.'; end if;
  if not exists(select 1 from public.membership_terms where member_id=p_member_id) then raise exception 'Membership history is required before restoration'; end if;
  update public.profiles set pending_membership_plan=v_plan,pending_membership_source='complimentary',membership_state='active',updated_at=now() where id=p_member_id;
  update public.membership_terms set reason=trim(p_reason),amount_paise=0 where member_id=p_member_id and status='active';
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'membership.restored','member',p_member_id::text,jsonb_build_object('previous_state',v_state,'plan',v_plan,'reason',trim(p_reason)));
end;
$$;

revoke all on function public.admin_cancel_membership(uuid,text) from public,anon;
revoke all on function public.admin_revoke_pending_membership_offer(uuid,text) from public,anon;
revoke all on function public.admin_restore_pending_membership_offer(uuid,text) from public,anon;
revoke all on function public.admin_restore_membership(uuid,text) from public,anon;
revoke all on function public.track_membership_status_context() from public,anon,authenticated;
grant execute on function public.admin_cancel_membership(uuid,text) to authenticated;
grant execute on function public.admin_revoke_pending_membership_offer(uuid,text) to authenticated;
grant execute on function public.admin_restore_pending_membership_offer(uuid,text) to authenticated;
grant execute on function public.admin_restore_membership(uuid,text) to authenticated;

commit;
