-- 041_user_permanent_delete_controls.sql
-- Eliminacion permanente segura de usuarios sin historial operativo.
-- Ejecutar despues de 040_attendance_qr_personalizado_force_delete.sql.
-- No borra auth.users desde SQL; Supabase Auth se elimina desde Netlify Function server-side.

begin;

create table if not exists public.user_delete_audit_logs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid null references public.businesses(id),
  actor_user_id uuid null,
  actor_name text null,
  actor_role text null,
  target_user_id uuid not null,
  target_name_snapshot text not null,
  target_email_snapshot text null,
  target_username_snapshot text null,
  target_role_snapshot text null,
  action text not null,
  allowed boolean not null,
  reason text not null,
  block_reasons text[] not null default '{}',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint user_delete_audit_logs_action_check
    check (action in ('delete_prepared','permanent_delete','delete_blocked','auth_delete_failed')),
  constraint user_delete_audit_logs_reason_check
    check (length(trim(reason)) > 0)
);

alter table public.user_delete_audit_logs enable row level security;

alter table public.user_delete_audit_logs
  drop constraint if exists user_delete_audit_logs_action_check;

alter table public.user_delete_audit_logs
  add constraint user_delete_audit_logs_action_check
  check (action in ('delete_prepared','permanent_delete','delete_blocked','auth_delete_failed'));

drop policy if exists "user_delete_audit_logs_admin_supervisor_read" on public.user_delete_audit_logs;
drop policy if exists "user_delete_audit_logs_admin_read" on public.user_delete_audit_logs;
create policy "user_delete_audit_logs_admin_read" on public.user_delete_audit_logs
for select
using (
  business_id = public.current_business_id()
  and public.has_any_role(array['admin']::public.user_role[])
);

drop policy if exists "user_delete_audit_logs_no_direct_insert" on public.user_delete_audit_logs;
create policy "user_delete_audit_logs_no_direct_insert" on public.user_delete_audit_logs
for insert
with check (false);

create index if not exists user_delete_audit_logs_business_created_idx
  on public.user_delete_audit_logs(business_id, created_at desc);

create index if not exists user_delete_audit_logs_target_created_idx
  on public.user_delete_audit_logs(target_user_id, created_at desc);

create or replace function public.admin_check_user_delete_eligibility(
  p_target_user_id uuid
)
returns table(
  can_delete boolean,
  reason text,
  target_user_id uuid,
  block_reasons text[],
  metadata jsonb
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor public.profiles%rowtype;
  v_target public.profiles%rowtype;
  v_account public.employee_accounts%rowtype;
  v_blocks text[] := '{}';
  v_counts jsonb := '{}'::jsonb;
  v_count integer := 0;
  v_other_admins integer := 0;
begin
  if auth.uid() is null then
    raise exception 'No autorizado';
  end if;

  select pr.id, pr.business_id, pr.branch_id, pr.full_name, pr.role, pr.active
  into v_actor
  from public.profiles pr
  where pr.id = auth.uid()
    and pr.active
    and pr.role = 'admin';

  if v_actor.id is null or v_actor.business_id is null then
    raise exception 'No autorizado';
  end if;

  if p_target_user_id is null then
    raise exception 'Usuario no encontrado';
  end if;

  select pr.id, pr.business_id, pr.branch_id, pr.full_name, pr.role, pr.active
  into v_target
  from public.profiles pr
  where pr.id = p_target_user_id;

  if v_target.id is null then
    raise exception 'Usuario no encontrado';
  end if;

  if v_target.business_id <> v_actor.business_id then
    raise exception 'Usuario no autorizado';
  end if;

  select
    ea.user_id, ea.business_id, ea.username, ea.auth_email, ea.employee_email,
    ea.first_name, ea.last_name, ea.phone, ea.avatar_url, ea.force_password_change,
    ea.dark_mode, ea.permission_template, ea.permissions, ea.created_by,
    ea.created_at, ea.updated_at
  into v_account
  from public.employee_accounts ea
  where ea.user_id = p_target_user_id;

  if p_target_user_id = auth.uid() then
    v_blocks := array_append(v_blocks, 'self_delete');
  end if;

  select count(*) into v_count from public.platform_admins pa where pa.user_id = p_target_user_id and pa.active;
  if v_count > 0 then v_blocks := array_append(v_blocks, 'platform_admin'); end if;
  v_counts := v_counts || jsonb_build_object('platform_admins', v_count);

  if v_target.role = 'admin' and v_target.active then
    select count(*)
    into v_other_admins
    from public.profiles pr
    where pr.business_id = v_actor.business_id
      and pr.id <> p_target_user_id
      and pr.role = 'admin'
      and pr.active;

    if v_other_admins = 0 then
      v_blocks := array_append(v_blocks, 'last_active_admin');
    end if;
  end if;
  v_counts := v_counts || jsonb_build_object('other_active_admins', v_other_admins);

  select count(*) into v_count from public.cash_sessions cs where cs.user_id = p_target_user_id;
  if v_count > 0 then v_blocks := array_append(v_blocks, 'cash_sessions'); end if;
  v_counts := v_counts || jsonb_build_object('cash_sessions', v_count);

  select count(*) into v_count from public.cash_movements cm where cm.user_id = p_target_user_id;
  if v_count > 0 then v_blocks := array_append(v_blocks, 'cash_movements'); end if;
  v_counts := v_counts || jsonb_build_object('cash_movements', v_count);

  select count(*) into v_count from public.cash_movements cm where cm.updated_by = p_target_user_id;
  if v_count > 0 then v_blocks := array_append(v_blocks, 'cash_movements.updated_by'); end if;
  v_counts := v_counts || jsonb_build_object('cash_movements.updated_by', v_count);

  select count(*) into v_count from public.cash_movements cm where cm.voided_by = p_target_user_id;
  if v_count > 0 then v_blocks := array_append(v_blocks, 'cash_movements.voided_by'); end if;
  v_counts := v_counts || jsonb_build_object('cash_movements.voided_by', v_count);

  select count(*) into v_count from public.sales s where s.cashier_id = p_target_user_id;
  if v_count > 0 then v_blocks := array_append(v_blocks, 'sales'); end if;
  v_counts := v_counts || jsonb_build_object('sales', v_count);

  select count(*) into v_count from public.purchases pu where pu.user_id = p_target_user_id;
  if v_count > 0 then v_blocks := array_append(v_blocks, 'purchases'); end if;
  v_counts := v_counts || jsonb_build_object('purchases', v_count);

  select count(*) into v_count from public.inventory_movements im where im.user_id = p_target_user_id;
  if v_count > 0 then v_blocks := array_append(v_blocks, 'inventory_movements'); end if;
  v_counts := v_counts || jsonb_build_object('inventory_movements', v_count);

  select count(*) into v_count from public.sale_returns sr where sr.user_id = p_target_user_id;
  if v_count > 0 then v_blocks := array_append(v_blocks, 'sale_returns'); end if;
  v_counts := v_counts || jsonb_build_object('sale_returns', v_count);

  select count(*) into v_count from public.sale_cancellations sc where sc.user_id = p_target_user_id;
  if v_count > 0 then v_blocks := array_append(v_blocks, 'sale_cancellations'); end if;
  v_counts := v_counts || jsonb_build_object('sale_cancellations', v_count);

  select count(*) into v_count from public.user_edit_audit_logs ual where ual.actor_user_id = p_target_user_id;
  if v_count > 0 then v_blocks := array_append(v_blocks, 'user_edit_audit_actor'); end if;
  v_counts := v_counts || jsonb_build_object('user_edit_audit_actor', v_count);

  select count(*) into v_count from public.user_edit_audit_logs ual where ual.target_user_id = p_target_user_id;
  if v_count > 0 then v_blocks := array_append(v_blocks, 'user_edit_audit_target'); end if;
  v_counts := v_counts || jsonb_build_object('user_edit_audit_target', v_count);

  select count(*) into v_count from public.cash_movement_audit_logs cma where cma.performed_by = p_target_user_id;
  if v_count > 0 then v_blocks := array_append(v_blocks, 'cash_movement_audit_logs'); end if;
  v_counts := v_counts || jsonb_build_object('cash_movement_audit_logs', v_count);

  select count(*) into v_count from public.team_invitations ti where ti.invited_by = p_target_user_id;
  if v_count > 0 then v_blocks := array_append(v_blocks, 'team_invitations_invited_by'); end if;
  v_counts := v_counts || jsonb_build_object('team_invitations_invited_by', v_count);

  select count(*) into v_count from public.employee_accounts ea where ea.created_by = p_target_user_id;
  if v_count > 0 then v_blocks := array_append(v_blocks, 'employee_accounts_created_by'); end if;
  v_counts := v_counts || jsonb_build_object('employee_accounts_created_by', v_count);

  select count(*) into v_count from public.employee_account_provisioning eap where eap.created_by = p_target_user_id;
  if v_count > 0 then v_blocks := array_append(v_blocks, 'employee_account_provisioning_created_by'); end if;
  v_counts := v_counts || jsonb_build_object('employee_account_provisioning_created_by', v_count);

  select count(*) into v_count from public.attendance_movement_types_v3 amt where amt.created_by = p_target_user_id;
  if v_count > 0 then v_blocks := array_append(v_blocks, 'attendance_movement_types_v3_created_by'); end if;
  v_counts := v_counts || jsonb_build_object('attendance_movement_types_v3_created_by', v_count);

  select count(*) into v_count from public.business_admin_invitations bai where bai.invited_by = p_target_user_id;
  if v_count > 0 then v_blocks := array_append(v_blocks, 'business_admin_invitations_invited_by'); end if;
  v_counts := v_counts || jsonb_build_object('business_admin_invitations_invited_by', v_count);

  return query
  select
    array_length(v_blocks, 1) is null,
    case
      when array_length(v_blocks, 1) is null then 'Usuario elegible para eliminacion permanente.'
      when 'self_delete' = any(v_blocks) then 'No puedes eliminar tu propio usuario.'
      when 'last_active_admin' = any(v_blocks) then 'No se puede eliminar el ultimo administrador activo.'
      when 'platform_admin' = any(v_blocks) then 'No se puede eliminar un administrador de plataforma desde esta pantalla.'
      else 'No se puede eliminar permanentemente porque este usuario tiene registros historicos. Puede inactivarlo.'
    end,
    v_target.id,
    v_blocks,
    jsonb_build_object(
      'counts', v_counts,
      'target', jsonb_build_object(
        'business_id', v_target.business_id,
        'full_name', v_target.full_name,
        'role', v_target.role,
        'active', v_target.active,
        'username', v_account.username,
        'auth_email', v_account.auth_email,
        'employee_email', v_account.employee_email
      )
    );
end $$;

create or replace function public.admin_prepare_user_permanent_delete(
  p_target_user_id uuid,
  p_reason text
)
returns table(
  prepared boolean,
  audit_id uuid,
  reason text,
  target_user_id uuid,
  auth_user_id uuid,
  metadata jsonb
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor public.profiles%rowtype;
  v_target public.profiles%rowtype;
  v_account public.employee_accounts%rowtype;
  v_can_delete boolean := false;
  v_eligibility_reason text := '';
  v_blocks text[] := '{}';
  v_metadata jsonb := '{}'::jsonb;
  v_reason text := trim(coalesce(p_reason, ''));
  v_audit_id uuid;
begin
  if length(v_reason) < 10 then
    raise exception 'Motivo obligatorio de al menos 10 caracteres';
  end if;

  if auth.uid() is null then
    raise exception 'No autorizado';
  end if;

  select pr.id, pr.business_id, pr.branch_id, pr.full_name, pr.role, pr.active
  into v_actor
  from public.profiles pr
  where pr.id = auth.uid()
    and pr.active
    and pr.role = 'admin';

  if v_actor.id is null or v_actor.business_id is null then
    raise exception 'No autorizado';
  end if;

  select pr.id, pr.business_id, pr.branch_id, pr.full_name, pr.role, pr.active
  into v_target
  from public.profiles pr
  where pr.id = p_target_user_id
  for update;

  if v_target.id is null then
    raise exception 'Usuario no encontrado';
  end if;

  if v_target.business_id <> v_actor.business_id then
    raise exception 'Usuario no autorizado';
  end if;

  select
    ea.user_id, ea.business_id, ea.username, ea.auth_email, ea.employee_email,
    ea.first_name, ea.last_name, ea.phone, ea.avatar_url, ea.force_password_change,
    ea.dark_mode, ea.permission_template, ea.permissions, ea.created_by,
    ea.created_at, ea.updated_at
  into v_account
  from public.employee_accounts ea
  where ea.user_id = p_target_user_id
  for update;

  select e.can_delete, e.reason, e.block_reasons, e.metadata
  into v_can_delete, v_eligibility_reason, v_blocks, v_metadata
  from public.admin_check_user_delete_eligibility(p_target_user_id) e;

  if not coalesce(v_can_delete, false) then
    insert into public.user_delete_audit_logs(
      business_id, actor_user_id, actor_name, actor_role, target_user_id,
      target_name_snapshot, target_email_snapshot, target_username_snapshot,
      target_role_snapshot, action, allowed, reason, block_reasons, metadata
    )
    values(
      v_actor.business_id, v_actor.id, v_actor.full_name, v_actor.role::text, v_target.id,
      v_target.full_name, v_account.employee_email, v_account.username, v_target.role::text,
      'delete_blocked', false, v_eligibility_reason, coalesce(v_blocks, '{}'),
      coalesce(v_metadata, '{}'::jsonb) || jsonb_build_object('requested_reason', v_reason)
    )
    returning id into v_audit_id;

    return query
    select false, v_audit_id, v_eligibility_reason, v_target.id, v_target.id, coalesce(v_metadata, '{}'::jsonb);
    return;
  end if;

  insert into public.user_delete_audit_logs(
    business_id, actor_user_id, actor_name, actor_role, target_user_id,
    target_name_snapshot, target_email_snapshot, target_username_snapshot,
    target_role_snapshot, action, allowed, reason, block_reasons, metadata
  )
  values(
    v_actor.business_id, v_actor.id, v_actor.full_name, v_actor.role::text, v_target.id,
    v_target.full_name, v_account.employee_email, v_account.username, v_target.role::text,
    'delete_prepared', true, v_reason, '{}',
    coalesce(v_metadata, '{}'::jsonb) || jsonb_build_object(
      'auth_email', v_account.auth_email,
      'employee_email', v_account.employee_email,
      'target_username', v_account.username
    )
  )
  returning id into v_audit_id;

  return query
  select true, v_audit_id, 'Usuario preparado para eliminacion permanente.', v_target.id, v_target.id,
    coalesce(v_metadata, '{}'::jsonb) || jsonb_build_object(
      'audit_id', v_audit_id,
      'auth_email', v_account.auth_email,
      'employee_email', v_account.employee_email,
      'target_username', v_account.username
    );
end $$;

create or replace function public.admin_delete_user_public_records(
  p_target_user_id uuid,
  p_reason text
)
returns table(
  deleted boolean,
  reason text,
  target_user_id uuid,
  auth_user_id uuid,
  metadata jsonb
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor public.profiles%rowtype;
  v_target public.profiles%rowtype;
  v_audit public.user_delete_audit_logs%rowtype;
  v_reason text := trim(coalesce(p_reason, ''));
  v_target_email text;
  v_target_username text;
  v_auth_email text;
begin
  if length(v_reason) < 10 then
    raise exception 'Motivo obligatorio de al menos 10 caracteres';
  end if;

  if auth.uid() is null then
    raise exception 'No autorizado';
  end if;

  select pr.id, pr.business_id, pr.branch_id, pr.full_name, pr.role, pr.active
  into v_actor
  from public.profiles pr
  where pr.id = auth.uid()
    and pr.active
    and pr.role = 'admin';

  if v_actor.id is null or v_actor.business_id is null then
    raise exception 'No autorizado';
  end if;

  select ud.id, ud.business_id, ud.actor_user_id, ud.actor_name, ud.actor_role,
    ud.target_user_id, ud.target_name_snapshot, ud.target_email_snapshot,
    ud.target_username_snapshot, ud.target_role_snapshot, ud.action, ud.allowed,
    ud.reason, ud.block_reasons, ud.metadata, ud.created_at
  into v_audit
  from public.user_delete_audit_logs ud
  where ud.target_user_id = p_target_user_id
    and ud.actor_user_id = v_actor.id
    and ud.business_id = v_actor.business_id
    and ud.action = 'delete_prepared'
    and ud.allowed
  order by ud.created_at desc
  limit 1
  for update;

  if v_audit.id is null then
    raise exception 'El usuario no tiene una eliminacion preparada vigente';
  end if;

  select pr.id, pr.business_id, pr.branch_id, pr.full_name, pr.role, pr.active
  into v_target
  from public.profiles pr
  where pr.id = p_target_user_id
  for update;

  if v_target.id is not null and v_target.business_id <> v_actor.business_id then
    raise exception 'Usuario no autorizado';
  end if;

  v_target_email := v_audit.target_email_snapshot;
  v_target_username := v_audit.target_username_snapshot;
  v_auth_email := v_audit.metadata->>'auth_email';

  if v_auth_email is not null then
    delete from public.employee_account_provisioning eap
    where eap.auth_email = v_auth_email;
  end if;

  delete from public.employee_accounts ea
  where ea.user_id = p_target_user_id
    and ea.business_id = v_actor.business_id;

  delete from public.team_invitations ti
  where ti.business_id = v_actor.business_id
    and ti.accepted_at is null
    and v_target_email is not null
    and lower(ti.email) = lower(v_target_email);

  delete from public.profiles pr
  where pr.id = p_target_user_id
    and pr.business_id = v_actor.business_id;

  update public.user_delete_audit_logs ud
  set action = 'permanent_delete',
      reason = v_reason,
      metadata = coalesce(ud.metadata, '{}'::jsonb) || jsonb_build_object('auth_deleted_first', true)
  where ud.id = v_audit.id;

  return query
  select true, 'Usuario eliminado permanentemente.', p_target_user_id, p_target_user_id,
    coalesce(v_audit.metadata, '{}'::jsonb) || jsonb_build_object(
      'target_username', v_target_username,
      'target_email', v_target_email,
      'auth_deleted_first', true
    );
end $$;

create or replace function public.admin_mark_user_auth_delete_failed(
  p_target_user_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor public.profiles%rowtype;
  v_audit_id uuid;
begin
  if auth.uid() is null then
    raise exception 'No autorizado';
  end if;

  select pr.id, pr.business_id, pr.branch_id, pr.full_name, pr.role, pr.active
  into v_actor
  from public.profiles pr
  where pr.id = auth.uid()
    and pr.active
    and pr.role = 'admin';

  if v_actor.id is null or v_actor.business_id is null then
    raise exception 'No autorizado';
  end if;

  select ud.id
  into v_audit_id
  from public.user_delete_audit_logs ud
  where ud.target_user_id = p_target_user_id
    and ud.actor_user_id = v_actor.id
    and ud.business_id = v_actor.business_id
    and ud.action = 'delete_prepared'
    and ud.allowed
  order by ud.created_at desc
  limit 1
  for update;

  if v_audit_id is not null then
    update public.user_delete_audit_logs ud
    set action = 'auth_delete_failed',
        reason = 'No fue posible eliminar el acceso de autenticacion.',
        metadata = coalesce(ud.metadata, '{}'::jsonb) || jsonb_build_object('auth_error', left(coalesce(p_reason, ''), 180))
    where ud.id = v_audit_id;
  end if;
end $$;

revoke execute on function public.admin_check_user_delete_eligibility(uuid) from public, anon;
revoke execute on function public.admin_prepare_user_permanent_delete(uuid,text) from public, anon;
revoke execute on function public.admin_delete_user_public_records(uuid,text) from public, anon;
revoke execute on function public.admin_mark_user_auth_delete_failed(uuid,text) from public, anon;

grant execute on function public.admin_check_user_delete_eligibility(uuid) to authenticated, service_role;
grant execute on function public.admin_prepare_user_permanent_delete(uuid,text) to authenticated, service_role;
grant execute on function public.admin_delete_user_public_records(uuid,text) to authenticated, service_role;
grant execute on function public.admin_mark_user_auth_delete_failed(uuid,text) to authenticated, service_role;

select pg_notify('pgrst','reload schema');

commit;
