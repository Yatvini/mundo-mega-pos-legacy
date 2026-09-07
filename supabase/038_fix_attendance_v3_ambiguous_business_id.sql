-- 038_fix_attendance_v3_ambiguous_business_id.sql
-- Corrige ambiguedad de business_id en RPC Asistencia V3.
-- Causa: funciones PL/pgSQL con RETURNS TABLE declaran business_id como variable de salida;
-- algunas sentencias internas tambien usan columnas business_id, lo que puede producir:
-- column reference "business_id" is ambiguous.
-- Ejecutar despues de 037_fix_attendance_v3_rpc_return_shapes.sql.
-- No crea tablas, no altera estructura, no modifica RLS/policies y no manipula datos existentes.

begin;

create or replace function public.attendance_v3_admin_actor()
returns table(user_id uuid, business_id uuid, role text)
language plpgsql
security definer
set search_path=public
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'Sesion no encontrada.';
  end if;

  return query
  select
    pr.id,
    pr.business_id,
    pr.role::text
  from public.profiles pr
  join public.businesses b on b.id = pr.business_id and b.status = 'active'
  where pr.id = auth.uid()
    and pr.active
    and pr.role in ('admin','supervisor');

  if not found then
    raise exception 'No autorizado para administrar Asistencia V3.';
  end if;
end;
$$;

create or replace function public.attendance_v3_admin_initialize_defaults()
returns table(movement_id uuid, name text, category text, active boolean, sort_order integer)
language plpgsql
security definer
set search_path=public
as $$
#variable_conflict use_column
declare
  v_actor_user_id uuid;
  v_actor_business_id uuid;
  v_actor_role text;
begin
  select aa.user_id, aa.business_id, aa.role
  into v_actor_user_id, v_actor_business_id, v_actor_role
  from public.attendance_v3_admin_actor() aa;

  insert into public.attendance_v3_settings(business_id, active, duplicate_window_minutes)
  values (v_actor_business_id, true, 1)
  on conflict (business_id) do update
    set active = true,
        duplicate_window_minutes = coalesce(public.attendance_v3_settings.duplicate_window_minutes, 1),
        updated_at = now();

  insert into public.attendance_movement_types_v3(business_id, name, category, sort_order, color, icon, created_by)
  select v_actor_business_id, seed.name, seed.category, seed.sort_order, seed.color, seed.icon, v_actor_user_id
  from (values
    ('Entrada'::text, 'jornada'::text, 10, '#278d57'::text, 'log-in'::text),
    ('Salida a almuerzo'::text, 'almuerzo'::text, 20, '#f59e0b'::text, 'utensils'::text),
    ('Regreso de almuerzo'::text, 'almuerzo'::text, 30, '#84cc16'::text, 'rotate-ccw'::text),
    ('Salida final'::text, 'jornada'::text, 40, '#dc2626'::text, 'log-out'::text),
    ('Permiso'::text, 'permiso'::text, 50, '#2563eb'::text, 'file-check'::text),
    ('Trabajo externo'::text, 'externo'::text, 60, '#7c3aed'::text, 'truck'::text),
    ('Descanso'::text, 'descanso'::text, 70, '#0891b2'::text, 'coffee'::text),
    ('Otro'::text, 'otro'::text, 80, '#64748b'::text, 'more-horizontal'::text)
  ) as seed(name, category, sort_order, color, icon)
  where not exists (
    select 1
    from public.attendance_movement_types_v3 mt
    where mt.business_id = v_actor_business_id
      and mt.active
      and lower(trim(mt.name)) = lower(trim(seed.name))
  );

  return query
  select
    mt.id,
    mt.name::text,
    mt.category::text,
    mt.active,
    mt.sort_order
  from public.attendance_movement_types_v3 mt
  where mt.business_id = v_actor_business_id
  order by mt.sort_order, mt.name;
end;
$$;

create or replace function public.attendance_v3_admin_list_movements()
returns table(
  movement_id uuid,
  business_id uuid,
  name text,
  category text,
  description text,
  active boolean,
  sort_order integer,
  color text,
  icon text,
  requires_note boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
#variable_conflict use_column
declare
  v_actor_user_id uuid;
  v_actor_business_id uuid;
  v_actor_role text;
begin
  select aa.user_id, aa.business_id, aa.role
  into v_actor_user_id, v_actor_business_id, v_actor_role
  from public.attendance_v3_admin_actor() aa;

  return query
  select
    mt.id,
    mt.business_id,
    mt.name::text,
    mt.category::text,
    mt.description::text,
    mt.active,
    mt.sort_order,
    mt.color::text,
    mt.icon::text,
    mt.requires_note,
    mt.created_at,
    mt.updated_at
  from public.attendance_movement_types_v3 mt
  where mt.business_id = v_actor_business_id
  order by mt.sort_order, mt.name;
end;
$$;

create or replace function public.attendance_v3_admin_create_movement(
  p_name text,
  p_category text default null,
  p_description text default null,
  p_sort_order integer default 100,
  p_color text default null,
  p_icon text default null,
  p_requires_note boolean default false
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
#variable_conflict use_column
declare
  v_actor_user_id uuid;
  v_actor_business_id uuid;
  v_actor_role text;
  v_movement_id uuid;
begin
  select aa.user_id, aa.business_id, aa.role
  into v_actor_user_id, v_actor_business_id, v_actor_role
  from public.attendance_v3_admin_actor() aa;

  if length(trim(coalesce(p_name, ''))) = 0 then
    raise exception 'El nombre del movimiento es obligatorio.';
  end if;

  insert into public.attendance_movement_types_v3(
    business_id, name, category, description, sort_order, color, icon, requires_note, created_by
  )
  values (
    v_actor_business_id,
    trim(p_name),
    nullif(trim(coalesce(p_category, '')), ''),
    nullif(trim(coalesce(p_description, '')), ''),
    coalesce(p_sort_order, 100),
    nullif(trim(coalesce(p_color, '')), ''),
    nullif(trim(coalesce(p_icon, '')), ''),
    coalesce(p_requires_note, false),
    v_actor_user_id
  )
  returning attendance_movement_types_v3.id into v_movement_id;

  return v_movement_id;
end;
$$;

create or replace function public.attendance_v3_admin_update_movement(
  p_movement_id uuid,
  p_name text,
  p_category text default null,
  p_description text default null,
  p_active boolean default true,
  p_sort_order integer default 100,
  p_color text default null,
  p_icon text default null,
  p_requires_note boolean default false
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
#variable_conflict use_column
declare
  v_actor_user_id uuid;
  v_actor_business_id uuid;
  v_actor_role text;
begin
  select aa.user_id, aa.business_id, aa.role
  into v_actor_user_id, v_actor_business_id, v_actor_role
  from public.attendance_v3_admin_actor() aa;

  if length(trim(coalesce(p_name, ''))) = 0 then
    raise exception 'El nombre del movimiento es obligatorio.';
  end if;

  update public.attendance_movement_types_v3 mt
  set name = trim(p_name),
      category = nullif(trim(coalesce(p_category, '')), ''),
      description = nullif(trim(coalesce(p_description, '')), ''),
      active = coalesce(p_active, true),
      sort_order = coalesce(p_sort_order, 100),
      color = nullif(trim(coalesce(p_color, '')), ''),
      icon = nullif(trim(coalesce(p_icon, '')), ''),
      requires_note = coalesce(p_requires_note, false),
      updated_at = now()
  where mt.id = p_movement_id
    and mt.business_id = v_actor_business_id;

  if not found then
    raise exception 'Movimiento no encontrado.';
  end if;

  return true;
end;
$$;

create or replace function public.attendance_v3_reader_context(p_reader_token text)
returns table(reader_id uuid, business_id uuid, business_name text)
language plpgsql
security definer
set search_path=public
as $$
#variable_conflict use_column
declare
  v_hash text := encode(extensions.digest(trim(coalesce(p_reader_token, '')), 'sha256'), 'hex');
begin
  if length(trim(coalesce(p_reader_token, ''))) < 24 then
    raise exception 'Lector no valido.';
  end if;

  return query
  select
    rt.id,
    rt.business_id,
    b.name::text
  from public.attendance_reader_tokens_v2 rt
  join public.businesses b on b.id = rt.business_id and b.status = 'active'
  join public.attendance_v3_settings s on s.business_id = rt.business_id and s.active
  where rt.token_hash = v_hash
    and rt.active
    and rt.revoked_at is null
  limit 1;

  if not found then
    raise exception 'Lector V3 no valido o inactivo.';
  end if;
end;
$$;

create or replace function public.attendance_v3_employee_token_context(p_employee_token text)
returns table(
  token_id uuid,
  business_id uuid,
  branch_id uuid,
  person_id uuid,
  full_name text,
  birth_date date,
  age integer,
  sex text,
  category text,
  branch_name text
)
language plpgsql
security definer
set search_path=public
as $$
#variable_conflict use_column
declare
  v_hash text := encode(extensions.digest(trim(coalesce(p_employee_token, '')), 'sha256'), 'hex');
begin
  if length(trim(coalesce(p_employee_token, ''))) < 24 then
    raise exception 'QR de empleado no valido.';
  end if;

  return query
  select
    qt.id,
    p.business_id,
    p.branch_id,
    p.id,
    p.full_name::text,
    p.birth_date,
    extract(year from age(current_date, p.birth_date))::integer,
    p.sex::text,
    coalesce(
      nullif(trim(p.category_override), ''),
      case
        when extract(year from age(current_date, p.birth_date))::integer < 13 then 'nino'
        when extract(year from age(current_date, p.birth_date))::integer < 18 then 'joven'
        else 'adulto'
      end
    )::text,
    coalesce(br.name, 'General')::text
  from public.attendance_qr_tokens_v2 qt
  join public.attendance_people_v2 p on p.id = qt.person_id and p.business_id = qt.business_id and p.active
  join public.businesses b on b.id = p.business_id and b.status = 'active'
  join public.attendance_v3_settings s on s.business_id = p.business_id and s.active
  left join public.branches br on br.id = p.branch_id and br.business_id = p.business_id
  where qt.token_hash = v_hash
    and qt.active
    and qt.revoked_at is null
    and (qt.expires_at is null or qt.expires_at > now())
  limit 1;

  if not found then
    raise exception 'QR de empleado V3 no valido o inactivo.';
  end if;
end;
$$;

create or replace function public.attendance_v3_create_reader_token(p_business_id uuid, p_token text)
returns table(reader_id uuid, business_id uuid, active boolean, created_at timestamptz)
language plpgsql
security definer
set search_path=public
as $$
#variable_conflict use_column
declare
  v_actor_user_id uuid;
  v_actor_business_id uuid;
  v_actor_role text;
  v_hash text := encode(extensions.digest(trim(coalesce(p_token, '')), 'sha256'), 'hex');
begin
  select aa.user_id, aa.business_id, aa.role
  into v_actor_user_id, v_actor_business_id, v_actor_role
  from public.attendance_v3_admin_actor() aa;

  if p_business_id is null or p_business_id <> v_actor_business_id then
    raise exception 'Empresa no autorizada.';
  end if;

  if length(trim(coalesce(p_token, ''))) < 24 then
    raise exception 'Token de lector no valido.';
  end if;

  if not exists (
    select 1
    from public.businesses b
    where b.id = p_business_id
      and b.status = 'active'
  ) then
    raise exception 'Empresa no activa.';
  end if;

  insert into public.attendance_v3_settings(business_id, active, duplicate_window_minutes)
  values (p_business_id, true, 1)
  on conflict (business_id) do update
    set active = true,
        updated_at = now();

  update public.attendance_reader_tokens_v2 rt
  set active = false,
      revoked_at = now()
  where rt.business_id = p_business_id
    and rt.active
    and rt.revoked_at is null;

  return query
  insert into public.attendance_reader_tokens_v2(business_id, token_hash)
  values (p_business_id, v_hash)
  returning
    attendance_reader_tokens_v2.id,
    attendance_reader_tokens_v2.business_id,
    attendance_reader_tokens_v2.active,
    attendance_reader_tokens_v2.created_at;
end;
$$;

create or replace function public.attendance_v3_validate_employee(p_reader_token text, p_employee_token text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
#variable_conflict use_column
declare
  v_reader_id uuid;
  v_reader_business_id uuid;
  v_reader_business_name text;
  v_token_id uuid;
  v_employee_business_id uuid;
  v_employee_branch_id uuid;
  v_employee_person_id uuid;
  v_employee_full_name text;
  v_employee_birth_date date;
  v_employee_age integer;
  v_employee_sex text;
  v_employee_category text;
  v_employee_branch_name text;
  v_settings_active boolean;
  v_duplicate_window_minutes integer;
  v_movements jsonb;
begin
  select rc.reader_id, rc.business_id, rc.business_name
  into v_reader_id, v_reader_business_id, v_reader_business_name
  from public.attendance_v3_reader_context(p_reader_token) rc;

  select ec.token_id, ec.business_id, ec.branch_id, ec.person_id, ec.full_name,
         ec.birth_date, ec.age, ec.sex, ec.category, ec.branch_name
  into v_token_id, v_employee_business_id, v_employee_branch_id, v_employee_person_id,
       v_employee_full_name, v_employee_birth_date, v_employee_age, v_employee_sex,
       v_employee_category, v_employee_branch_name
  from public.attendance_v3_employee_token_context(p_employee_token) ec;

  if v_employee_business_id <> v_reader_business_id then
    raise exception 'QR de empleado no pertenece a esta empresa.';
  end if;

  select s.active, s.duplicate_window_minutes
  into v_settings_active, v_duplicate_window_minutes
  from public.attendance_v3_settings s
  where s.business_id = v_reader_business_id
    and s.active;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', mt.id,
    'businessId', mt.business_id,
    'name', mt.name,
    'category', mt.category,
    'description', mt.description,
    'active', mt.active,
    'sortOrder', mt.sort_order,
    'color', mt.color,
    'icon', mt.icon,
    'requiresNote', mt.requires_note,
    'createdAt', mt.created_at,
    'updatedAt', mt.updated_at
  ) order by mt.sort_order, mt.name), '[]'::jsonb)
  into v_movements
  from public.attendance_movement_types_v3 mt
  where mt.business_id = v_reader_business_id
    and mt.active;

  return jsonb_build_object(
    'ok', true,
    'readerId', v_reader_id,
    'businessId', v_reader_business_id,
    'businessName', v_reader_business_name,
    'person', jsonb_build_object(
      'id', v_employee_person_id,
      'fullName', v_employee_full_name,
      'age', v_employee_age,
      'sex', v_employee_sex,
      'category', v_employee_category,
      'branchId', v_employee_branch_id,
      'branchName', v_employee_branch_name
    ),
    'settings', jsonb_build_object(
      'active', v_settings_active,
      'duplicateWindowMinutes', v_duplicate_window_minutes
    ),
    'movements', v_movements,
    'message', 'Empleado validado. Selecciona el movimiento a registrar.'
  );
end;
$$;

create or replace function public.attendance_v3_record_movement(
  p_reader_token text,
  p_employee_token text,
  p_movement_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
#variable_conflict use_column
declare
  v_reader_id uuid;
  v_reader_business_id uuid;
  v_reader_business_name text;
  v_token_id uuid;
  v_employee_business_id uuid;
  v_employee_branch_id uuid;
  v_employee_person_id uuid;
  v_employee_full_name text;
  v_employee_birth_date date;
  v_employee_age integer;
  v_employee_sex text;
  v_employee_category text;
  v_employee_branch_name text;
  v_movement_id uuid;
  v_movement_name text;
  v_movement_category text;
  v_movement_requires_note boolean;
  v_duplicate_window_minutes integer;
  v_now timestamptz := now();
  v_event_id uuid;
begin
  select rc.reader_id, rc.business_id, rc.business_name
  into v_reader_id, v_reader_business_id, v_reader_business_name
  from public.attendance_v3_reader_context(p_reader_token) rc;

  select ec.token_id, ec.business_id, ec.branch_id, ec.person_id, ec.full_name,
         ec.birth_date, ec.age, ec.sex, ec.category, ec.branch_name
  into v_token_id, v_employee_business_id, v_employee_branch_id, v_employee_person_id,
       v_employee_full_name, v_employee_birth_date, v_employee_age, v_employee_sex,
       v_employee_category, v_employee_branch_name
  from public.attendance_v3_employee_token_context(p_employee_token) ec;

  if v_employee_business_id <> v_reader_business_id then
    raise exception 'QR de empleado no pertenece a esta empresa.';
  end if;

  select mt.id, mt.name, mt.category, mt.requires_note
  into v_movement_id, v_movement_name, v_movement_category, v_movement_requires_note
  from public.attendance_movement_types_v3 mt
  where mt.id = p_movement_id
    and mt.business_id = v_reader_business_id
    and mt.active;

  if v_movement_id is null then
    raise exception 'Movimiento no disponible.';
  end if;

  if v_movement_requires_note and length(trim(coalesce(p_note, ''))) = 0 then
    raise exception 'Este movimiento requiere nota.';
  end if;

  select s.duplicate_window_minutes
  into v_duplicate_window_minutes
  from public.attendance_v3_settings s
  where s.business_id = v_reader_business_id
    and s.active;

  if coalesce(v_duplicate_window_minutes, 1) > 0 and exists (
    select 1
    from public.attendance_events_v3 ev
    where ev.business_id = v_reader_business_id
      and ev.person_id = v_employee_person_id
      and ev.movement_id = v_movement_id
      and ev.occurred_at >= v_now - make_interval(mins => v_duplicate_window_minutes)
  ) then
    raise exception 'Movimiento duplicado recientemente.';
  end if;

  insert into public.attendance_events_v3(
    business_id, branch_id, person_id, movement_id, movement_name_snapshot,
    movement_category_snapshot, occurred_at, source, reader_token_id, note, metadata
  )
  values (
    v_reader_business_id,
    v_employee_branch_id,
    v_employee_person_id,
    v_movement_id,
    v_movement_name,
    v_movement_category,
    v_now,
    'reader_qr',
    v_reader_id,
    nullif(trim(coalesce(p_note, '')), ''),
    jsonb_build_object('v', 3, 'reader', 'attendance_reader_tokens_v2', 'employeeQr', 'attendance_qr_tokens_v2')
  )
  returning attendance_events_v3.id into v_event_id;

  update public.attendance_reader_tokens_v2 rt
  set last_used_at = v_now
  where rt.id = v_reader_id;

  return jsonb_build_object(
    'ok', true,
    'eventId', v_event_id,
    'personId', v_employee_person_id,
    'personName', v_employee_full_name,
    'movementId', v_movement_id,
    'movementName', v_movement_name,
    'occurredAt', v_now,
    'message', v_movement_name || ' registrado correctamente.'
  );
end;
$$;

create or replace function public.attendance_v3_report(p_from date, p_to date, p_branch_id uuid default null)
returns table(
  event_id uuid,
  business_id uuid,
  branch_id uuid,
  branch_name text,
  person_id uuid,
  person_name text,
  movement_id uuid,
  movement_name text,
  movement_category text,
  occurred_at timestamptz,
  source text,
  note text
)
language plpgsql
security definer
set search_path=public
as $$
#variable_conflict use_column
declare
  v_actor_user_id uuid;
  v_actor_business_id uuid;
  v_actor_role text;
begin
  select aa.user_id, aa.business_id, aa.role
  into v_actor_user_id, v_actor_business_id, v_actor_role
  from public.attendance_v3_admin_actor() aa;

  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'Rango de fechas invalido.';
  end if;

  return query
  select
    ev.id,
    ev.business_id,
    ev.branch_id,
    coalesce(br.name, 'General')::text,
    ev.person_id,
    p.full_name::text,
    ev.movement_id,
    ev.movement_name_snapshot::text,
    ev.movement_category_snapshot::text,
    ev.occurred_at,
    ev.source::text,
    ev.note::text
  from public.attendance_events_v3 ev
  join public.attendance_people_v2 p on p.id = ev.person_id and p.business_id = v_actor_business_id
  left join public.branches br on br.id = ev.branch_id and br.business_id = v_actor_business_id
  where ev.business_id = v_actor_business_id
    and ev.occurred_at >= p_from::timestamptz
    and ev.occurred_at < (p_to + 1)::timestamptz
    and (p_branch_id is null or ev.branch_id = p_branch_id)
  order by ev.occurred_at desc;
end;
$$;

revoke all on function public.attendance_v3_admin_actor() from public, anon;
revoke all on function public.attendance_v3_admin_initialize_defaults() from public, anon;
revoke all on function public.attendance_v3_admin_list_movements() from public, anon;
revoke all on function public.attendance_v3_admin_create_movement(text,text,text,integer,text,text,boolean) from public, anon;
revoke all on function public.attendance_v3_admin_update_movement(uuid,text,text,text,boolean,integer,text,text,boolean) from public, anon;
revoke all on function public.attendance_v3_create_reader_token(uuid,text) from public, anon;
revoke all on function public.attendance_v3_employee_token_context(text) from public, anon, authenticated;
revoke all on function public.attendance_v3_reader_context(text) from public, anon, authenticated;
revoke all on function public.attendance_v3_validate_employee(text,text) from public, anon, authenticated;
revoke all on function public.attendance_v3_record_movement(text,text,uuid,text) from public, anon, authenticated;
revoke all on function public.attendance_v3_report(date,date,uuid) from public, anon;

grant execute on function public.attendance_v3_admin_actor() to authenticated, service_role;
grant execute on function public.attendance_v3_admin_initialize_defaults() to authenticated, service_role;
grant execute on function public.attendance_v3_admin_list_movements() to authenticated, service_role;
grant execute on function public.attendance_v3_admin_create_movement(text,text,text,integer,text,text,boolean) to authenticated, service_role;
grant execute on function public.attendance_v3_admin_update_movement(uuid,text,text,text,boolean,integer,text,text,boolean) to authenticated, service_role;
grant execute on function public.attendance_v3_create_reader_token(uuid,text) to authenticated, service_role;
grant execute on function public.attendance_v3_report(date,date,uuid) to authenticated, service_role;

grant execute on function public.attendance_v3_employee_token_context(text) to service_role;
grant execute on function public.attendance_v3_reader_context(text) to service_role;
grant execute on function public.attendance_v3_validate_employee(text,text) to service_role;
grant execute on function public.attendance_v3_record_movement(text,text,uuid,text) to service_role;

select pg_notify('pgrst','reload schema');

commit;
