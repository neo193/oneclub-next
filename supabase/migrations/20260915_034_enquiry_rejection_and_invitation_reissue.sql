begin;

create or replace function public.reject_enquiry(p_enquiry_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_enquiry public.enquiries%rowtype;
begin
  if not public.is_staff_or_admin() then
    raise exception 'Not authorised';
  end if;

  select * into v_enquiry
  from public.enquiries
  where id = p_enquiry_id
  for update;

  if v_enquiry.id is null then
    raise exception 'Enquiry not found';
  end if;

  if v_enquiry.status not in ('new', 'contacted') then
    raise exception 'Only pending enquiries can be rejected';
  end if;

  update public.enquiries
  set status = 'rejected',
      reviewed_at = now(),
      reviewed_by = auth.uid(),
      updated_at = now()
  where id = p_enquiry_id;

  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values (
    auth.uid(),
    'enquiry.rejected',
    'enquiry',
    p_enquiry_id::text,
    jsonb_build_object('email', lower(v_enquiry.email), 'previous_status', v_enquiry.status)
  );
end;
$$;

revoke all on function public.reject_enquiry(uuid) from public;
grant execute on function public.reject_enquiry(uuid) to authenticated;

create or replace function public.reissue_enquiry_invitation(p_enquiry_id uuid)
returns text
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_enquiry public.enquiries%rowtype;
  v_token text := encode(gen_random_bytes(32), 'hex');
  v_invitation_id uuid;
begin
  if not public.is_staff_or_admin() then
    raise exception 'Not authorised';
  end if;

  select * into v_enquiry
  from public.enquiries
  where id = p_enquiry_id
  for update;

  if v_enquiry.id is null then
    raise exception 'Enquiry not found';
  end if;

  if v_enquiry.status <> 'approved' then
    raise exception 'Only approved enquiries can receive an approval link';
  end if;

  if exists (
    select 1
    from public.membership_invitations
    where enquiry_id = p_enquiry_id
      and status = 'used'
  ) then
    raise exception 'This invitation has already been accepted';
  end if;

  update public.membership_invitations
  set status = 'revoked'
  where enquiry_id = p_enquiry_id
    and status = 'active';

  insert into public.membership_invitations(enquiry_id, email, token_hash, expires_at, created_by)
  values (
    p_enquiry_id,
    lower(v_enquiry.email),
    encode(digest(v_token, 'sha256'), 'hex'),
    now() + interval '30 days',
    auth.uid()
  )
  returning id into v_invitation_id;

  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values (
    auth.uid(),
    'invitation.reissued',
    'membership_invitation',
    v_invitation_id::text,
    jsonb_build_object('email', lower(v_enquiry.email), 'enquiry_id', p_enquiry_id, 'expires_in_days', 30)
  );

  return v_token;
end;
$$;

revoke all on function public.reissue_enquiry_invitation(uuid) from public;
grant execute on function public.reissue_enquiry_invitation(uuid) to authenticated;

commit;

