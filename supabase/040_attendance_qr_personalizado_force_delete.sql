-- 040_attendance_qr_personalizado_force_delete.sql
-- Agrega eliminacion permanente forzada para Asistencia QR personalizado.
-- Mantiene intactas las RPC seguras de SQL 039 y crea RPCs explicitas para borrar historial.
-- Ejecutar despues de 039_attendance_qr_personalizado_safe_delete.sql.

begin;

create or replace function public.attendance_v3_admin_force_delete_movement(p_movement_id uuid)
returns table(deleted boolean, reason text, movement_id uuid, metadata jsonb)
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
  v_events_count integer := 0;
  v_movement_count integer := 0;
  v_metadata jsonb;
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
      p_movement_id,
      jsonb_build_object('forced', true);
    return;
  end if;

  select count(*)::integer
  into v_events_count
  from public.attendance_events_v3 ev
  where ev.movement_id = v_movement.id
    and ev.business_id = v_actor_business_id;

  v_movement_count := 1;
  v_reason := 'Movimiento eliminado permanentemente con historial asociado.';
  v_metadata := jsonb_build_object(
    'forced', true,
    'deleted_attendance_events_v3_count', v_events_count,
    'deleted_movement_count', v_movement_count
  );

  insert into public.attendance_v3_admin_delete_audit_logs(
    business_id, actor_id, actor_name, actor_role, target_type, target_id,
    target_name_snapshot, action, allowed, reason, metadata
  )
  values (
    v_actor_business_id, v_actor_user_id, v_actor_name, v_actor_role,
    'movement', v_movement.id, v_movement.name, 'permanent_delete', true,
    v_reason, v_metadata
  );

  delete from public.attendance_events_v3 ev
  where ev.movement_id = v_movement.id
    and ev.business_id = v_actor_business_id;

  delete from public.attendance_movement_types_v3 mt
  where mt.id = v_movement.id
    and mt.business_id = v_actor_business_id;

  return query
  select true, v_reason, v_movement.id, v_metadata;
end;
$$;

create or replace function public.attendance_v3_admin_force_delete_person_qr(p_person_id uuid)
returns table(deleted boolean, reason text, person_id uuid, metadata jsonb)
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
  v_events_v3_count integer := 0;
  v_events_v2_count integer := 0;
  v_daily_records_v2_count integer := 0;
  v_qr_tokens_count integer := 0;
  v_person_count integer := 0;
  v_metadata jsonb;
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
      p_person_id,
      jsonb_build_object('forced', true);
    return;
  end if;

  select count(*)::integer
  into v_events_v3_count
  from public.attendance_events_v3 ev
  where ev.person_id = v_person.id
    and ev.business_id = v_actor_business_id;

  select count(*)::integer
  into v_events_v2_count
  from public.attendance_events_v2 ev2
  where ev2.person_id = v_person.id
    and ev2.business_id = v_actor_business_id;

  select count(*)::integer
  into v_daily_records_v2_count
  from public.attendance_daily_records_v2 dr
  where dr.person_id = v_person.id
    and dr.business_id = v_actor_business_id;

  select count(*)::integer
  into v_qr_tokens_count
  from public.attendance_qr_tokens_v2 qt
  where qt.person_id = v_person.id
    and qt.business_id = v_actor_business_id;

  v_person_count := 1;
  v_reason := 'Persona QR eliminada permanentemente con historial asociado.';
  v_metadata := jsonb_build_object(
    'forced', true,
    'deleted_attendance_events_v3_count', v_events_v3_count,
    'deleted_attendance_events_v2_count', v_events_v2_count,
    'deleted_daily_records_v2_count', v_daily_records_v2_count,
    'deleted_qr_tokens_count', v_qr_tokens_count,
    'deleted_person_count', v_person_count
  );

  insert into public.attendance_v3_admin_delete_audit_logs(
    business_id, actor_id, actor_name, actor_role, target_type, target_id,
    target_name_snapshot, action, allowed, reason, metadata
  )
  values (
    v_actor_business_id, v_actor_user_id, v_actor_name, v_actor_role,
    'person_qr', v_person.id, v_person.full_name, 'permanent_delete', true,
    v_reason, v_metadata
  );

  delete from public.attendance_events_v3 ev
  where ev.person_id = v_person.id
    and ev.business_id = v_actor_business_id;

  delete from public.attendance_events_v2 ev2
  where ev2.person_id = v_person.id
    and ev2.business_id = v_actor_business_id;

  delete from public.attendance_daily_records_v2 dr
  where dr.person_id = v_person.id
    and dr.business_id = v_actor_business_id;

  delete from public.attendance_qr_tokens_v2 qt
  where qt.person_id = v_person.id
    and qt.business_id = v_actor_business_id;

  delete from public.attendance_people_v2 p
  where p.id = v_person.id
    and p.business_id = v_actor_business_id;

  return query
  select true, v_reason, v_person.id, v_metadata;
end;
$$;

revoke all on function public.attendance_v3_admin_force_delete_movement(uuid) from public, anon;
revoke all on function public.attendance_v3_admin_force_delete_person_qr(uuid) from public, anon;

grant execute on function public.attendance_v3_admin_force_delete_movement(uuid) to authenticated, service_role;
grant execute on function public.attendance_v3_admin_force_delete_person_qr(uuid) to authenticated, service_role;

select pg_notify('pgrst','reload schema');

commit;
