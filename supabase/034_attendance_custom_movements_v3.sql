-- 034_attendance_custom_movements_v3.sql
-- Asistencia V3: movimientos personalizados por empresa.
-- Ejecutar despues de 033_fix_attendance_reader_lunch_out_allowed_actions.sql.
-- No modifica Asistencia legacy ni Asistencia V2; crea tablas y RPCs V3 separadas.

begin;

create table if not exists public.attendance_v3_settings (
  business_id uuid primary key references public.businesses(id),
  active boolean not null default false,
  duplicate_window_minutes integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendance_v3_settings_duplicate_window_check check (duplicate_window_minutes >= 0)
);

create table if not exists public.attendance_movement_types_v3 (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  name text not null,
  category text null,
  description text null,
  active boolean not null default true,
  sort_order integer not null default 100,
  color text null,
  icon text null,
  requires_note boolean not null default false,
  created_by uuid null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendance_movement_types_v3_name_check check (length(trim(name)) > 0)
);

create table if not exists public.attendance_events_v3 (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  branch_id uuid null references public.branches(id),
  person_id uuid not null references public.attendance_people_v2(id),
  movement_id uuid not null references public.attendance_movement_types_v3(id),
  movement_name_snapshot text not null,
  movement_category_snapshot text null,
  occurred_at timestamptz not null default now(),
  source text not null default 'reader_qr',
  reader_token_id uuid null references public.attendance_reader_tokens_v2(id),
  note text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint attendance_events_v3_movement_name_check check (length(trim(movement_name_snapshot)) > 0),
  constraint attendance_events_v3_source_check check (source in ('reader_qr','admin','system'))
);

create index if not exists attendance_v3_settings_active_idx on public.attendance_v3_settings(business_id, active);
create index if not exists attendance_movement_types_v3_business_active_idx on public.attendance_movement_types_v3(business_id, active, sort_order);
create unique index if not exists attendance_movement_types_v3_business_name_active_uidx
  on public.attendance_movement_types_v3(business_id, lower(trim(name)))
  where active;
create index if not exists attendance_events_v3_business_date_idx on public.attendance_events_v3(business_id, occurred_at desc);
create index if not exists attendance_events_v3_person_date_idx on public.attendance_events_v3(person_id, occurred_at desc);
create index if not exists attendance_events_v3_movement_date_idx on public.attendance_events_v3(movement_id, occurred_at desc);
create index if not exists attendance_events_v3_branch_date_idx on public.attendance_events_v3(branch_id, occurred_at desc);

alter table public.attendance_v3_settings enable row level security;
alter table public.attendance_movement_types_v3 enable row level security;
alter table public.attendance_events_v3 enable row level security;

drop policy if exists "attendance_v3_settings_business_read" on public.attendance_v3_settings;
create policy "attendance_v3_settings_business_read" on public.attendance_v3_settings
for select using (
  exists (
    select 1 from public.profiles pr
    where pr.id = auth.uid()
      and pr.active
      and pr.business_id = attendance_v3_settings.business_id
      and pr.role in ('admin','supervisor')
  )
);

drop policy if exists "attendance_v3_settings_no_direct_insert" on public.attendance_v3_settings;
create policy "attendance_v3_settings_no_direct_insert" on public.attendance_v3_settings
for insert with check (false);

drop policy if exists "attendance_v3_settings_no_direct_update" on public.attendance_v3_settings;
create policy "attendance_v3_settings_no_direct_update" on public.attendance_v3_settings
for update using (false);

drop policy if exists "attendance_movement_types_v3_business_read" on public.attendance_movement_types_v3;
create policy "attendance_movement_types_v3_business_read" on public.attendance_movement_types_v3
for select using (
  exists (
    select 1 from public.profiles pr
    where pr.id = auth.uid()
      and pr.active
      and pr.business_id = attendance_movement_types_v3.business_id
      and pr.role in ('admin','supervisor')
  )
);

drop policy if exists "attendance_movement_types_v3_no_direct_insert" on public.attendance_movement_types_v3;
create policy "attendance_movement_types_v3_no_direct_insert" on public.attendance_movement_types_v3
for insert with check (false);

drop policy if exists "attendance_movement_types_v3_no_direct_update" on public.attendance_movement_types_v3;
create policy "attendance_movement_types_v3_no_direct_update" on public.attendance_movement_types_v3
for update using (false);

drop policy if exists "attendance_events_v3_business_read" on public.attendance_events_v3;
create policy "attendance_events_v3_business_read" on public.attendance_events_v3
for select using (
  exists (
    select 1 from public.profiles pr
    where pr.id = auth.uid()
      and pr.active
      and pr.business_id = attendance_events_v3.business_id
      and pr.role in ('admin','supervisor')
  )
);

drop policy if exists "attendance_events_v3_no_direct_insert" on public.attendance_events_v3;
create policy "attendance_events_v3_no_direct_insert" on public.attendance_events_v3
for insert with check (false);

drop policy if exists "attendance_events_v3_no_direct_update" on public.attendance_events_v3;
create policy "attendance_events_v3_no_direct_update" on public.attendance_events_v3
for update using (false);

create or replace function public.attendance_v3_admin_actor()
returns table(user_id uuid, business_id uuid, role text)
language plpgsql
security definer
set search_path=public
as $$
begin
  if auth.uid() is null then
    raise exception 'Sesion no encontrada.';
  end if;

  return query
  select pr.id, pr.business_id, pr.role
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
declare
  v_actor record;
begin
  select * into v_actor from public.attendance_v3_admin_actor();

  insert into public.attendance_v3_settings(business_id, active, duplicate_window_minutes)
  values (v_actor.business_id, true, 1)
  on conflict (business_id) do update
    set active = true,
        duplicate_window_minutes = coalesce(public.attendance_v3_settings.duplicate_window_minutes, 1),
        updated_at = now();

  insert into public.attendance_movement_types_v3(business_id, name, category, sort_order, color, icon, created_by)
  select v_actor.business_id, seed.name, seed.category, seed.sort_order, seed.color, seed.icon, v_actor.user_id
  from (values
    ('Entrada', 'jornada', 10, '#278d57', 'log-in'),
    ('Salida a almuerzo', 'almuerzo', 20, '#f59e0b', 'utensils'),
    ('Regreso de almuerzo', 'almuerzo', 30, '#84cc16', 'rotate-ccw'),
    ('Salida final', 'jornada', 40, '#dc2626', 'log-out'),
    ('Permiso', 'permiso', 50, '#2563eb', 'file-check'),
    ('Trabajo externo', 'externo', 60, '#7c3aed', 'truck'),
    ('Descanso', 'descanso', 70, '#0891b2', 'coffee'),
    ('Otro', 'otro', 80, '#64748b', 'more-horizontal')
  ) as seed(name, category, sort_order, color, icon)
  where not exists (
    select 1
    from public.attendance_movement_types_v3 mt
    where mt.business_id = v_actor.business_id
      and mt.active
      and lower(trim(mt.name)) = lower(trim(seed.name))
  );

  return query
  select mt.id, mt.name, mt.category, mt.active, mt.sort_order
  from public.attendance_movement_types_v3 mt
  where mt.business_id = v_actor.business_id
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
declare
  v_actor record;
begin
  select * into v_actor from public.attendance_v3_admin_actor();

  return query
  select mt.id, mt.business_id, mt.name, mt.category, mt.description, mt.active,
         mt.sort_order, mt.color, mt.icon, mt.requires_note, mt.created_at, mt.updated_at
  from public.attendance_movement_types_v3 mt
  where mt.business_id = v_actor.business_id
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
declare
  v_actor record;
  v_id uuid;
begin
  select * into v_actor from public.attendance_v3_admin_actor();
  if length(trim(coalesce(p_name, ''))) = 0 then
    raise exception 'El nombre del movimiento es obligatorio.';
  end if;

  insert into public.attendance_movement_types_v3(
    business_id, name, category, description, sort_order, color, icon, requires_note, created_by
  )
  values (
    v_actor.business_id, trim(p_name), nullif(trim(coalesce(p_category, '')), ''),
    nullif(trim(coalesce(p_description, '')), ''), coalesce(p_sort_order, 100),
    nullif(trim(coalesce(p_color, '')), ''), nullif(trim(coalesce(p_icon, '')), ''),
    coalesce(p_requires_note, false), v_actor.user_id
  )
  returning id into v_id;

  return v_id;
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
declare
  v_actor record;
begin
  select * into v_actor from public.attendance_v3_admin_actor();
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
    and mt.business_id = v_actor.business_id;

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
declare
  v_hash text := encode(extensions.digest(trim(coalesce(p_reader_token, '')), 'sha256'), 'hex');
begin
  if length(trim(coalesce(p_reader_token, ''))) < 24 then
    raise exception 'Lector no valido.';
  end if;

  return query
  select rt.id, rt.business_id, b.name
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
    p.full_name,
    p.birth_date,
    extract(year from age(current_date, p.birth_date))::integer,
    p.sex,
    coalesce(
      nullif(trim(p.category_override), ''),
      case
        when extract(year from age(current_date, p.birth_date))::integer < 13 then 'nino'
        when extract(year from age(current_date, p.birth_date))::integer < 18 then 'joven'
        else 'adulto'
      end
    ),
    coalesce(br.name, 'General')
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
declare
  v_actor record;
  v_hash text := encode(extensions.digest(trim(coalesce(p_token, '')), 'sha256'), 'hex');
begin
  select * into v_actor from public.attendance_v3_admin_actor();

  if p_business_id is null or p_business_id <> v_actor.business_id then
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
  returning id, attendance_reader_tokens_v2.business_id, attendance_reader_tokens_v2.active, attendance_reader_tokens_v2.created_at;
end;
$$;

create or replace function public.attendance_v3_validate_employee(p_reader_token text, p_employee_token text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_reader record;
  v_employee record;
  v_settings record;
  v_movements jsonb;
begin
  select * into v_reader from public.attendance_v3_reader_context(p_reader_token);
  select * into v_employee from public.attendance_v3_employee_token_context(p_employee_token);

  if v_employee.business_id <> v_reader.business_id then
    raise exception 'QR de empleado no pertenece a esta empresa.';
  end if;

  select * into v_settings
  from public.attendance_v3_settings s
  where s.business_id = v_reader.business_id
    and s.active;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', mt.id,
    'name', mt.name,
    'category', mt.category,
    'description', mt.description,
    'sortOrder', mt.sort_order,
    'color', mt.color,
    'icon', mt.icon,
    'requiresNote', mt.requires_note
  ) order by mt.sort_order, mt.name), '[]'::jsonb)
  into v_movements
  from public.attendance_movement_types_v3 mt
  where mt.business_id = v_reader.business_id
    and mt.active;

  return jsonb_build_object(
    'ok', true,
    'readerId', v_reader.reader_id,
    'businessId', v_reader.business_id,
    'businessName', v_reader.business_name,
    'person', jsonb_build_object(
      'id', v_employee.person_id,
      'fullName', v_employee.full_name,
      'age', v_employee.age,
      'sex', v_employee.sex,
      'category', v_employee.category,
      'branchId', v_employee.branch_id,
      'branchName', v_employee.branch_name
    ),
    'settings', jsonb_build_object(
      'active', v_settings.active,
      'duplicateWindowMinutes', v_settings.duplicate_window_minutes
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
declare
  v_reader record;
  v_employee record;
  v_movement record;
  v_settings record;
  v_now timestamptz := now();
  v_event_id uuid;
begin
  select * into v_reader from public.attendance_v3_reader_context(p_reader_token);
  select * into v_employee from public.attendance_v3_employee_token_context(p_employee_token);

  if v_employee.business_id <> v_reader.business_id then
    raise exception 'QR de empleado no pertenece a esta empresa.';
  end if;

  select * into v_movement
  from public.attendance_movement_types_v3 mt
  where mt.id = p_movement_id
    and mt.business_id = v_reader.business_id
    and mt.active;

  if v_movement.id is null then
    raise exception 'Movimiento no disponible.';
  end if;

  if v_movement.requires_note and length(trim(coalesce(p_note, ''))) = 0 then
    raise exception 'Este movimiento requiere nota.';
  end if;

  select * into v_settings
  from public.attendance_v3_settings s
  where s.business_id = v_reader.business_id
    and s.active;

  if coalesce(v_settings.duplicate_window_minutes, 1) > 0 and exists (
    select 1
    from public.attendance_events_v3 ev
    where ev.business_id = v_reader.business_id
      and ev.person_id = v_employee.person_id
      and ev.movement_id = v_movement.id
      and ev.occurred_at >= v_now - make_interval(mins => v_settings.duplicate_window_minutes)
  ) then
    raise exception 'Movimiento duplicado recientemente.';
  end if;

  insert into public.attendance_events_v3(
    business_id, branch_id, person_id, movement_id, movement_name_snapshot,
    movement_category_snapshot, occurred_at, source, reader_token_id, note, metadata
  )
  values (
    v_reader.business_id, v_employee.branch_id, v_employee.person_id, v_movement.id,
    v_movement.name, v_movement.category, v_now, 'reader_qr', v_reader.reader_id,
    nullif(trim(coalesce(p_note, '')), ''),
    jsonb_build_object('v', 3, 'reader', 'attendance_reader_tokens_v2', 'employeeQr', 'attendance_qr_tokens_v2')
  )
  returning id into v_event_id;

  update public.attendance_reader_tokens_v2 rt
  set last_used_at = v_now
  where rt.id = v_reader.reader_id;

  return jsonb_build_object(
    'ok', true,
    'eventId', v_event_id,
    'personId', v_employee.person_id,
    'personName', v_employee.full_name,
    'movementId', v_movement.id,
    'movementName', v_movement.name,
    'occurredAt', v_now,
    'message', v_movement.name || ' registrado correctamente.'
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
declare
  v_actor record;
begin
  select * into v_actor from public.attendance_v3_admin_actor();

  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'Rango de fechas invalido.';
  end if;

  return query
  select ev.id, ev.business_id, ev.branch_id, coalesce(br.name, 'General'),
         ev.person_id, p.full_name, ev.movement_id, ev.movement_name_snapshot,
         ev.movement_category_snapshot, ev.occurred_at, ev.source, ev.note
  from public.attendance_events_v3 ev
  join public.attendance_people_v2 p on p.id = ev.person_id and p.business_id = v_actor.business_id
  left join public.branches br on br.id = ev.branch_id and br.business_id = v_actor.business_id
  where ev.business_id = v_actor.business_id
    and ev.occurred_at >= p_from::timestamptz
    and ev.occurred_at < (p_to + 1)::timestamptz
    and (p_branch_id is null or ev.branch_id = p_branch_id)
  order by ev.occurred_at desc;
end;
$$;

grant execute on function public.attendance_v3_admin_actor() to authenticated;
grant execute on function public.attendance_v3_admin_initialize_defaults() to authenticated;
grant execute on function public.attendance_v3_admin_list_movements() to authenticated;
grant execute on function public.attendance_v3_admin_create_movement(text,text,text,integer,text,text,boolean) to authenticated;
grant execute on function public.attendance_v3_admin_update_movement(uuid,text,text,text,boolean,integer,text,text,boolean) to authenticated;
grant execute on function public.attendance_v3_reader_context(text) to authenticated, service_role;
grant execute on function public.attendance_v3_employee_token_context(text) to authenticated, service_role;
grant execute on function public.attendance_v3_create_reader_token(uuid,text) to authenticated, service_role;
grant execute on function public.attendance_v3_validate_employee(text,text) to authenticated, service_role;
grant execute on function public.attendance_v3_record_movement(text,text,uuid,text) to authenticated, service_role;
grant execute on function public.attendance_v3_report(date,date,uuid) to authenticated;

select pg_notify('pgrst','reload schema');

commit;
