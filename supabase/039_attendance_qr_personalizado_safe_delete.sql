-- 039_attendance_qr_personalizado_safe_delete.sql
-- Agrega eliminacion permanente segura para Asistencia QR personalizado.
-- La eliminacion solo se permite si no existe historial asociado.
-- Ejecutar despues de 038_fix_attendance_v3_ambiguous_business_id.sql.

begin;

create table if not exists public.attendance_v3_admin_delete_audit_logs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  actor_id uuid null,
  actor_name text null,
  actor_role text null,
  target_type text not null,
  target_id uuid not null,
  target_name_snapshot text not null,
  action text not null default 'permanent_delete',
  allowed boolean not null,
  reason text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint attendance_v3_admin_delete_audit_target_type_check
    check (target_type in ('movement','person_qr')),
  constraint attendance_v3_admin_delete_audit_action_check
    check (action in ('permanent_delete','delete_blocked'))
);

alter table public.attendance_v3_admin_delete_audit_logs enable row level security;

drop policy if exists "attendance_v3_admin_delete_audit_logs_business_read"
  on public.attendance_v3_admin_delete_audit_logs;
create policy "attendance_v3_admin_delete_audit_logs_business_read"
on public.attendance_v3_admin_delete_audit_logs
for select
to authenticated
using (
  exists (
    select 1
    from public.profiles pr
    where pr.id = auth.uid()
      and pr.business_id = attendance_v3_admin_delete_audit_logs.business_id
      and pr.active
      and pr.role in ('admin','supervisor')
  )
);

create or replace function public.attendance_v3_admin_delete_movement(p_movement_id uuid)
returns table(deleted boolean, reason text, movement_id uuid)
language plpgsql
security definer
set search_path=public
as $$
#variable_conflict use_column
declare
  v_actor_user_id uuid;
  v_actor_business_id uuid;
  v_actor_role text;
  v_actor_name text;
  v_movement record;
  v_reason text;
begin
  select aa.user_id, aa.business_id, aa.role
  into v_actor_user_id, v_actor_business_id, v_actor_role
  from public.attendance_v3_admin_actor() aa;

  select pr.full_name
  into v_actor_name
  from public.profiles pr
  where pr.id = v_actor_user_id
    and pr.business_id = v_actor_business_id;

  select mt.id, mt.business_id, mt.name
  into v_movement
  from public.attendance_movement_types_v3 mt
  where mt.id = p_movement_id
    and mt.business_id = v_actor_business_id
  for update;

  if v_movement.id is null then
    return query
    select
      false,
      'Movimiento no encontrado.'::text,
      p_movement_id;
    return;
  end if;

  if exists (
    select 1
    from public.attendance_events_v3 ev
    where ev.movement_id = v_movement.id
      and ev.business_id = v_actor_business_id
  ) then
    v_reason := 'No se puede eliminar permanentemente porque ya tiene registros históricos. Puede inactivarlo.';

    insert into public.attendance_v3_admin_delete_audit_logs(
      business_id, actor_id, actor_name, actor_role, target_type, target_id,
      target_name_snapshot, action, allowed, reason, metadata
    )
    values (
      v_actor_business_id, v_actor_user_id, v_actor_name, v_actor_role,
      'movement', v_movement.id, v_movement.name, 'delete_blocked', false,
      v_reason, jsonb_build_object('history_table', 'attendance_events_v3')
    );

    return query
    select false, v_reason, v_movement.id;
    return;
  end if;

  v_reason := 'Movimiento eliminado permanentemente.';

  insert into public.attendance_v3_admin_delete_audit_logs(
    business_id, actor_id, actor_name, actor_role, target_type, target_id,
    target_name_snapshot, action, allowed, reason, metadata
  )
  values (
    v_actor_business_id, v_actor_user_id, v_actor_name, v_actor_role,
    'movement', v_movement.id, v_movement.name, 'permanent_delete', true,
    v_reason, jsonb_build_object('source_table', 'attendance_movement_types_v3')
  );

  delete from public.attendance_movement_types_v3 mt
  where mt.id = v_movement.id
    and mt.business_id = v_actor_business_id;

  return query
  select true, v_reason, v_movement.id;
end;
$$;

create or replace function public.attendance_v3_admin_delete_person_qr(p_person_id uuid)
returns table(deleted boolean, reason text, person_id uuid)
language plpgsql
security definer
set search_path=public
as $$
#variable_conflict use_column
declare
  v_actor_user_id uuid;
  v_actor_business_id uuid;
  v_actor_role text;
  v_actor_name text;
  v_person record;
  v_reason text;
  v_history_table text;
begin
  select aa.user_id, aa.business_id, aa.role
  into v_actor_user_id, v_actor_business_id, v_actor_role
  from public.attendance_v3_admin_actor() aa;

  select pr.full_name
  into v_actor_name
  from public.profiles pr
  where pr.id = v_actor_user_id
    and pr.business_id = v_actor_business_id;

  select p.id, p.business_id, p.full_name
  into v_person
  from public.attendance_people_v2 p
  where p.id = p_person_id
    and p.business_id = v_actor_business_id
  for update;

  if v_person.id is null then
    return query
    select
      false,
      'Persona QR no encontrada.'::text,
      p_person_id;
    return;
  end if;

  if exists (
    select 1
    from public.attendance_events_v3 ev
    where ev.person_id = v_person.id
      and ev.business_id = v_actor_business_id
  ) then
    v_history_table := 'attendance_events_v3';
  elsif exists (
    select 1
    from public.attendance_events_v2 ev2
    where ev2.person_id = v_person.id
      and ev2.business_id = v_actor_business_id
  ) then
    v_history_table := 'attendance_events_v2';
  elsif exists (
    select 1
    from public.attendance_daily_records_v2 dr
    where dr.person_id = v_person.id
      and dr.business_id = v_actor_business_id
  ) then
    v_history_table := 'attendance_daily_records_v2';
  end if;

  if v_history_table is not null then
    v_reason := 'No se puede eliminar permanentemente porque ya tiene registros históricos. Puede inactivarlo.';

    insert into public.attendance_v3_admin_delete_audit_logs(
      business_id, actor_id, actor_name, actor_role, target_type, target_id,
      target_name_snapshot, action, allowed, reason, metadata
    )
    values (
      v_actor_business_id, v_actor_user_id, v_actor_name, v_actor_role,
      'person_qr', v_person.id, v_person.full_name, 'delete_blocked', false,
      v_reason, jsonb_build_object('history_table', v_history_table)
    );

    return query
    select false, v_reason, v_person.id;
    return;
  end if;

  v_reason := 'Persona QR eliminada permanentemente.';

  insert into public.attendance_v3_admin_delete_audit_logs(
    business_id, actor_id, actor_name, actor_role, target_type, target_id,
    target_name_snapshot, action, allowed, reason, metadata
  )
  values (
    v_actor_business_id, v_actor_user_id, v_actor_name, v_actor_role,
    'person_qr', v_person.id, v_person.full_name, 'permanent_delete', true,
    v_reason, jsonb_build_object('source_table', 'attendance_people_v2')
  );

  delete from public.attendance_qr_tokens_v2 qt
  where qt.person_id = v_person.id
    and qt.business_id = v_actor_business_id;

  delete from public.attendance_people_v2 p
  where p.id = v_person.id
    and p.business_id = v_actor_business_id;

  return query
  select true, v_reason, v_person.id;
end;
$$;

revoke all on table public.attendance_v3_admin_delete_audit_logs from public, anon, authenticated;
grant select on table public.attendance_v3_admin_delete_audit_logs to authenticated, service_role;

revoke all on function public.attendance_v3_admin_delete_movement(uuid) from public, anon;
revoke all on function public.attendance_v3_admin_delete_person_qr(uuid) from public, anon;

grant execute on function public.attendance_v3_admin_delete_movement(uuid) to authenticated, service_role;
grant execute on function public.attendance_v3_admin_delete_person_qr(uuid) to authenticated, service_role;

select pg_notify('pgrst','reload schema');

commit;
