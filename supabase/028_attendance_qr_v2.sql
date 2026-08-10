-- 028_attendance_qr_v2.sql
-- Asistencia V2: QR personalizado por empleado.
-- Ejecutar despues de 027_user_edit_audit_and_transaction.sql.
-- No modifica ni reemplaza la asistencia legacy por kiosco/link (?attendance=<token>).

begin;

create extension if not exists pgcrypto;

create table if not exists public.attendance_settings (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  attendance_mode text not null default 'legacy',
  uses_lunch boolean not null default true,
  lunch_minutes integer not null default 60,
  allows_half_day boolean not null default true,
  allows_continuous_day boolean not null default true,
  standard_check_in time null,
  standard_check_out time null,
  late_tolerance_minutes integer not null default 10,
  duplicate_scan_window_minutes integer not null default 3,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendance_settings_mode_check check (attendance_mode in ('legacy','employee_qr_v2')),
  constraint attendance_settings_lunch_minutes_check check (lunch_minutes >= 0),
  constraint attendance_settings_late_tolerance_check check (late_tolerance_minutes >= 0),
  constraint attendance_settings_duplicate_window_check check (duplicate_scan_window_minutes >= 1)
);

insert into public.attendance_settings (business_id, attendance_mode)
select b.id, 'legacy'
from public.businesses b
where not exists (
  select 1
  from public.attendance_settings s
  where s.business_id = b.id
);

create table if not exists public.attendance_people_v2 (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid null references public.branches(id) on delete set null,
  full_name text not null,
  birth_date date not null,
  sex text not null default 'no_especificado',
  category_override text null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendance_people_v2_full_name_check check (length(trim(full_name)) > 0),
  constraint attendance_people_v2_sex_check check (sex in ('masculino','femenino','no_especificado')),
  constraint attendance_people_v2_category_check check (category_override is null or category_override in ('nino','joven','adulto'))
);

create table if not exists public.attendance_qr_tokens_v2 (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  person_id uuid not null references public.attendance_people_v2(id) on delete cascade,
  token_hash text not null unique,
  active boolean not null default true,
  revoked_at timestamptz null,
  expires_at timestamptz null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz null,
  constraint attendance_qr_tokens_v2_hash_check check (length(trim(token_hash)) >= 32)
);

create table if not exists public.attendance_events_v2 (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid null references public.branches(id) on delete set null,
  person_id uuid not null references public.attendance_people_v2(id) on delete cascade,
  token_id uuid null references public.attendance_qr_tokens_v2(id) on delete set null,
  event_type text not null,
  occurred_at timestamptz not null default now(),
  -- V2 usa fecha local de Guatemala mientras no exista timezone por empresa.
  attendance_date date not null default ((now() at time zone 'America/Guatemala')::date),
  source text not null default 'qr',
  note text null,
  flags jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint attendance_events_v2_event_type_check check (event_type in ('check_in','lunch_out','lunch_in','check_out','half_day_out','continuous_day_out','manual_adjustment')),
  constraint attendance_events_v2_source_check check (source in ('qr','admin','system'))
);

create table if not exists public.attendance_daily_records_v2 (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid null references public.branches(id) on delete set null,
  person_id uuid not null references public.attendance_people_v2(id) on delete cascade,
  attendance_date date not null,
  check_in_at timestamptz null,
  lunch_out_at timestamptz null,
  lunch_in_at timestamptz null,
  check_out_at timestamptz null,
  workday_type text not null default 'full_day',
  status text not null default 'open',
  total_worked_minutes integer not null default 0,
  lunch_minutes integer not null default 0,
  late_minutes integer not null default 0,
  flags jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendance_daily_records_v2_unique_day unique (business_id, person_id, attendance_date),
  constraint attendance_daily_records_v2_workday_type_check check (workday_type in ('full_day','half_day','continuous_day','incomplete')),
  constraint attendance_daily_records_v2_status_check check (status in ('open','in_lunch','closed','incomplete')),
  constraint attendance_daily_records_v2_minutes_check check (total_worked_minutes >= 0 and lunch_minutes >= 0 and late_minutes >= 0)
);

create index if not exists attendance_people_v2_business_active_idx on public.attendance_people_v2(business_id, active);
create index if not exists attendance_people_v2_branch_idx on public.attendance_people_v2(branch_id);
create index if not exists attendance_qr_tokens_v2_hash_idx on public.attendance_qr_tokens_v2(token_hash);
create index if not exists attendance_qr_tokens_v2_person_active_idx on public.attendance_qr_tokens_v2(person_id, active);
create index if not exists attendance_events_v2_business_date_idx on public.attendance_events_v2(business_id, attendance_date, occurred_at desc);
create index if not exists attendance_events_v2_person_date_idx on public.attendance_events_v2(person_id, attendance_date, occurred_at desc);
create index if not exists attendance_daily_records_v2_business_date_idx on public.attendance_daily_records_v2(business_id, attendance_date);
create index if not exists attendance_daily_records_v2_person_date_idx on public.attendance_daily_records_v2(person_id, attendance_date);

alter table public.attendance_settings enable row level security;
alter table public.attendance_people_v2 enable row level security;
alter table public.attendance_qr_tokens_v2 enable row level security;
alter table public.attendance_events_v2 enable row level security;
alter table public.attendance_daily_records_v2 enable row level security;

drop policy if exists "attendance_settings_business_read" on public.attendance_settings;
create policy "attendance_settings_business_read" on public.attendance_settings
for select using (
  business_id = public.current_business_id()
  and public.has_any_role(array['admin','supervisor']::public.user_role[])
);

drop policy if exists "attendance_settings_admin_write" on public.attendance_settings;
drop policy if exists "attendance_settings_admin_insert" on public.attendance_settings;
create policy "attendance_settings_admin_insert" on public.attendance_settings
for insert with check (
  business_id = public.current_business_id()
  and public.has_any_role(array['admin']::public.user_role[])
);

drop policy if exists "attendance_settings_admin_update" on public.attendance_settings;
create policy "attendance_settings_admin_update" on public.attendance_settings
for update using (
  business_id = public.current_business_id()
  and public.has_any_role(array['admin']::public.user_role[])
)
with check (
  business_id = public.current_business_id()
  and public.has_any_role(array['admin']::public.user_role[])
);

drop policy if exists "attendance_people_v2_business_read" on public.attendance_people_v2;
create policy "attendance_people_v2_business_read" on public.attendance_people_v2
for select using (
  business_id = public.current_business_id()
  and public.has_any_role(array['admin','supervisor']::public.user_role[])
);

drop policy if exists "attendance_people_v2_admin_write" on public.attendance_people_v2;
drop policy if exists "attendance_people_v2_admin_insert" on public.attendance_people_v2;
create policy "attendance_people_v2_admin_insert" on public.attendance_people_v2
for insert with check (
  business_id = public.current_business_id()
  and public.has_any_role(array['admin']::public.user_role[])
);

drop policy if exists "attendance_people_v2_admin_update" on public.attendance_people_v2;
create policy "attendance_people_v2_admin_update" on public.attendance_people_v2
for update using (
  business_id = public.current_business_id()
  and public.has_any_role(array['admin']::public.user_role[])
)
with check (
  business_id = public.current_business_id()
  and public.has_any_role(array['admin']::public.user_role[])
);

drop policy if exists "attendance_qr_tokens_v2_admin_read" on public.attendance_qr_tokens_v2;
create policy "attendance_qr_tokens_v2_admin_read" on public.attendance_qr_tokens_v2
for select using (
  business_id = public.current_business_id()
  and public.has_any_role(array['admin','supervisor']::public.user_role[])
);

drop policy if exists "attendance_qr_tokens_v2_no_direct_write" on public.attendance_qr_tokens_v2;
create policy "attendance_qr_tokens_v2_no_direct_insert" on public.attendance_qr_tokens_v2
for insert with check (false);

drop policy if exists "attendance_qr_tokens_v2_no_direct_update" on public.attendance_qr_tokens_v2;
create policy "attendance_qr_tokens_v2_no_direct_update" on public.attendance_qr_tokens_v2
for update using (false) with check (false);

drop policy if exists "attendance_events_v2_business_read" on public.attendance_events_v2;
create policy "attendance_events_v2_business_read" on public.attendance_events_v2
for select using (
  business_id = public.current_business_id()
  and public.has_any_role(array['admin','supervisor']::public.user_role[])
);

drop policy if exists "attendance_events_v2_no_direct_write" on public.attendance_events_v2;
create policy "attendance_events_v2_no_direct_insert" on public.attendance_events_v2
for insert with check (false);

drop policy if exists "attendance_events_v2_no_direct_update" on public.attendance_events_v2;
create policy "attendance_events_v2_no_direct_update" on public.attendance_events_v2
for update using (false) with check (false);

drop policy if exists "attendance_daily_records_v2_business_read" on public.attendance_daily_records_v2;
create policy "attendance_daily_records_v2_business_read" on public.attendance_daily_records_v2
for select using (
  business_id = public.current_business_id()
  and public.has_any_role(array['admin','supervisor']::public.user_role[])
);

drop policy if exists "attendance_daily_records_v2_no_direct_write" on public.attendance_daily_records_v2;
create policy "attendance_daily_records_v2_no_direct_insert" on public.attendance_daily_records_v2
for insert with check (false);

drop policy if exists "attendance_daily_records_v2_no_direct_update" on public.attendance_daily_records_v2;
create policy "attendance_daily_records_v2_no_direct_update" on public.attendance_daily_records_v2
for update using (false) with check (false);

create or replace function public.attendance_qr_v2_category(p_birth_date date, p_override text default null)
returns text
language sql
stable
set search_path=public
as $$
  select coalesce(
    p_override,
    case
      when extract(year from age((now() at time zone 'America/Guatemala')::date, p_birth_date)) <= 12 then 'nino'
      when extract(year from age((now() at time zone 'America/Guatemala')::date, p_birth_date)) <= 17 then 'joven'
      else 'adulto'
    end
  );
$$;

create or replace function public.attendance_qr_v2_context(p_token text)
returns table(
  token_id uuid,
  business_id uuid,
  branch_id uuid,
  person_id uuid,
  person_name text,
  birth_date date,
  sex text,
  category text,
  uses_lunch boolean,
  allows_half_day boolean,
  allows_continuous_day boolean,
  standard_check_in time,
  standard_check_out time,
  late_tolerance_minutes integer,
  duplicate_scan_window_minutes integer,
  daily_status text,
  check_in_at timestamptz,
  lunch_out_at timestamptz,
  lunch_in_at timestamptz,
  check_out_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_hash text := encode(digest(trim(coalesce(p_token, '')), 'sha256'), 'hex');
  v_today date := (now() at time zone 'America/Guatemala')::date;
begin
  if length(trim(coalesce(p_token, ''))) < 24 then
    raise exception 'QR no valido';
  end if;

  return query
  select
    qt.id,
    p.business_id,
    p.branch_id,
    p.id,
    p.full_name,
    p.birth_date,
    p.sex,
    public.attendance_qr_v2_category(p.birth_date, p.category_override),
    s.uses_lunch,
    s.allows_half_day,
    s.allows_continuous_day,
    s.standard_check_in,
    s.standard_check_out,
    s.late_tolerance_minutes,
    s.duplicate_scan_window_minutes,
    case
      when d.id is null or d.check_in_at is null then 'sin_registro'
      when d.status = 'closed' then 'closed'
      when d.status = 'incomplete' then 'incomplete'
      when d.status = 'in_lunch' then 'in_lunch'
      when d.lunch_in_at is not null and d.check_out_at is null then 'regreso_de_almuerzo'
      else d.status
    end,
    d.check_in_at,
    d.lunch_out_at,
    d.lunch_in_at,
    d.check_out_at
  from public.attendance_qr_tokens_v2 qt
  join public.attendance_people_v2 p on p.id = qt.person_id and p.business_id = qt.business_id
  join public.businesses b on b.id = p.business_id and b.status = 'active'
  join public.attendance_settings s on s.business_id = p.business_id and s.attendance_mode = 'employee_qr_v2'
  left join public.attendance_daily_records_v2 d
    on d.business_id = p.business_id
   and d.person_id = p.id
   and d.attendance_date = v_today
  where qt.token_hash = v_hash
    and qt.active
    and qt.revoked_at is null
    and (qt.expires_at is null or qt.expires_at > now())
    and p.active;

  if not found then
    raise exception 'QR no valido o inactivo';
  end if;
end;
$$;

create or replace function public.attendance_qr_v2_resolve(p_token text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_ctx record;
  v_actions text[] := '{}';
begin
  select * into v_ctx from public.attendance_qr_v2_context(p_token);

  if v_ctx.daily_status = 'sin_registro' then
    v_actions := array['check_in'];
  elsif v_ctx.daily_status = 'open' and v_ctx.uses_lunch then
    v_actions := array['lunch_out','check_out'];
    if v_ctx.allows_half_day then v_actions := array_append(v_actions, 'half_day_out'); end if;
  elsif v_ctx.daily_status = 'open' and not v_ctx.uses_lunch then
    v_actions := array['check_out'];
    if v_ctx.allows_continuous_day then v_actions := array_append(v_actions, 'continuous_day_out'); end if;
    if v_ctx.allows_half_day then v_actions := array_append(v_actions, 'half_day_out'); end if;
  elsif v_ctx.daily_status = 'in_lunch' then
    v_actions := array['lunch_in'];
  elsif v_ctx.daily_status = 'regreso_de_almuerzo' then
    v_actions := array['check_out'];
  else
    v_actions := '{}';
  end if;

  return jsonb_build_object(
    'ok', true,
    'person', jsonb_build_object(
      'id', v_ctx.person_id,
      'fullName', v_ctx.person_name,
      'age', extract(year from age((now() at time zone 'America/Guatemala')::date, v_ctx.birth_date)),
      'sex', v_ctx.sex,
      'category', v_ctx.category
    ),
    'settings', jsonb_build_object(
      'usesLunch', v_ctx.uses_lunch,
      'allowsHalfDay', v_ctx.allows_half_day,
      'allowsContinuousDay', v_ctx.allows_continuous_day
    ),
    'daily', jsonb_build_object(
      'status', v_ctx.daily_status,
      'message', case
        when v_ctx.daily_status = 'closed' then 'Jornada ya cerrada'
        when v_ctx.daily_status = 'incomplete' then 'Requiere correccion administrativa'
        else 'Acciones disponibles'
      end,
      'checkInAt', v_ctx.check_in_at,
      'lunchOutAt', v_ctx.lunch_out_at,
      'lunchInAt', v_ctx.lunch_in_at,
      'checkOutAt', v_ctx.check_out_at
    ),
    'allowedActions', v_actions
  );
end;
$$;

create or replace function public.attendance_qr_v2_record(p_token text, p_action text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_ctx record;
  v_token public.attendance_qr_tokens_v2%rowtype;
  v_person public.attendance_people_v2%rowtype;
  v_daily public.attendance_daily_records_v2%rowtype;
  v_action text := trim(coalesce(p_action, ''));
  v_now timestamptz := now();
  v_today date := (now() at time zone 'America/Guatemala')::date;
  v_last_event timestamptz;
  v_status text;
  v_logical_status text;
  v_workday_type text := 'full_day';
  v_late_minutes integer := 0;
  v_flags jsonb := '{}'::jsonb;
  v_allowed text[];
begin
  select * into v_ctx from public.attendance_qr_v2_context(p_token);

  select *
  into v_token
  from public.attendance_qr_tokens_v2 qt
  where qt.id = v_ctx.token_id
  for update;

  if v_token.id is null or not v_token.active or v_token.revoked_at is not null then
    raise exception 'QR no valido o inactivo';
  end if;

  select *
  into v_person
  from public.attendance_people_v2 p
  where p.id = v_ctx.person_id
    and p.business_id = v_ctx.business_id
  for update;

  if v_person.id is null or not v_person.active then
    raise exception 'Persona no encontrada o inactiva';
  end if;

  insert into public.attendance_daily_records_v2(business_id, branch_id, person_id, attendance_date, status, workday_type)
  values(v_ctx.business_id, v_ctx.branch_id, v_ctx.person_id, v_today, 'open', 'full_day')
  on conflict (business_id, person_id, attendance_date)
  do update set updated_at = public.attendance_daily_records_v2.updated_at
  returning * into v_daily;

  select *
  into v_daily
  from public.attendance_daily_records_v2 d
  where d.business_id = v_ctx.business_id
    and d.person_id = v_ctx.person_id
    and d.attendance_date = v_today
  for update;

  v_logical_status := case
    when v_daily.id is null or v_daily.check_in_at is null then 'sin_registro'
    when v_daily.status = 'closed' then 'closed'
    when v_daily.status = 'incomplete' then 'incomplete'
    when v_daily.status = 'in_lunch' then 'in_lunch'
    when v_daily.lunch_in_at is not null and v_daily.check_out_at is null then 'regreso_de_almuerzo'
    else v_daily.status
  end;

  if v_logical_status = 'sin_registro' then
    v_allowed := array['check_in'];
  elsif v_logical_status = 'open' and v_ctx.uses_lunch then
    v_allowed := array['lunch_out','check_out'];
    if v_ctx.allows_half_day then v_allowed := array_append(v_allowed, 'half_day_out'); end if;
  elsif v_logical_status = 'open' and not v_ctx.uses_lunch then
    v_allowed := array['check_out'];
    if v_ctx.allows_continuous_day then v_allowed := array_append(v_allowed, 'continuous_day_out'); end if;
  elsif v_logical_status = 'in_lunch' then
    v_allowed := array['lunch_in'];
  elsif v_logical_status = 'regreso_de_almuerzo' then
    v_allowed := array['check_out'];
  elsif v_logical_status = 'closed' then
    raise exception 'Jornada ya cerrada';
  else
    raise exception 'Requiere correccion administrativa';
  end if;

  if v_action <> any(v_allowed) then
    raise exception 'Accion no permitida para el estado actual';
  end if;

  select max(e.occurred_at)
  into v_last_event
  from public.attendance_events_v2 e
  where e.business_id = v_ctx.business_id
    and e.person_id = v_ctx.person_id
    and e.attendance_date = v_today;

  if v_last_event is not null and v_now < v_last_event + make_interval(mins => v_ctx.duplicate_scan_window_minutes) then
    raise exception 'Marcaje duplicado. Intenta nuevamente en unos minutos';
  end if;

  if v_ctx.standard_check_in is not null and v_action = 'check_in'
    and v_now::time > (v_ctx.standard_check_in + make_interval(mins => v_ctx.late_tolerance_minutes))::time then
    v_late_minutes := greatest(0, floor(extract(epoch from (v_now::time - v_ctx.standard_check_in)) / 60)::integer);
    v_flags := v_flags || jsonb_build_object('outsideSchedule', true, 'late', true);
  end if;

  if v_ctx.standard_check_out is not null and v_action in ('check_out','half_day_out','continuous_day_out')
    and v_now::time < v_ctx.standard_check_out then
    v_flags := v_flags || jsonb_build_object('outsideSchedule', true);
  end if;

  if v_action = 'lunch_out' then
    v_status := 'in_lunch';
  elsif v_action in ('check_out','half_day_out','continuous_day_out') then
    v_status := 'closed';
  else
    v_status := 'open';
  end if;

  if v_action = 'half_day_out' then
    v_workday_type := 'half_day';
  elsif v_action = 'continuous_day_out' then
    v_workday_type := 'continuous_day';
  else
    v_workday_type := v_daily.workday_type;
  end if;

  insert into public.attendance_events_v2(business_id, branch_id, person_id, token_id, event_type, occurred_at, attendance_date, source, flags)
  values(v_ctx.business_id, v_ctx.branch_id, v_ctx.person_id, v_ctx.token_id, v_action, v_now, v_today, 'qr', v_flags);

  update public.attendance_daily_records_v2 d
  set
    check_in_at = case when v_action = 'check_in' then coalesce(d.check_in_at, v_now) else d.check_in_at end,
    lunch_out_at = case when v_action = 'lunch_out' then coalesce(d.lunch_out_at, v_now) else d.lunch_out_at end,
    lunch_in_at = case when v_action = 'lunch_in' then coalesce(d.lunch_in_at, v_now) else d.lunch_in_at end,
    check_out_at = case when v_action in ('check_out','half_day_out','continuous_day_out') then coalesce(d.check_out_at, v_now) else d.check_out_at end,
    workday_type = v_workday_type,
    status = v_status,
    late_minutes = greatest(d.late_minutes, v_late_minutes),
    flags = d.flags || v_flags,
    updated_at = now()
  where d.id = v_daily.id
  returning * into v_daily;

  update public.attendance_daily_records_v2 d
  set
    lunch_minutes = case
      when d.lunch_out_at is not null and d.lunch_in_at is not null
        then greatest(0, floor(extract(epoch from (d.lunch_in_at - d.lunch_out_at)) / 60)::integer)
      else 0
    end,
    total_worked_minutes = case
      when d.check_in_at is not null and d.check_out_at is not null then
        greatest(0, floor(extract(epoch from (d.check_out_at - d.check_in_at)) / 60)::integer)
        - case when d.lunch_out_at is not null and d.lunch_in_at is not null then greatest(0, floor(extract(epoch from (d.lunch_in_at - d.lunch_out_at)) / 60)::integer) else 0 end
      else d.total_worked_minutes
    end,
    updated_at = now()
  where d.id = v_daily.id
  returning * into v_daily;

  update public.attendance_qr_tokens_v2
  set last_used_at = v_now
  where id = v_ctx.token_id;

  return jsonb_build_object(
    'ok', true,
    'eventType', v_action,
    'status', v_status,
    'message', case
      when v_action = 'check_in' then 'Entrada registrada.'
      when v_action = 'lunch_out' then 'Salida a almuerzo registrada.'
      when v_action = 'lunch_in' then 'Regreso de almuerzo registrado.'
      when v_action = 'half_day_out' then 'Medio dia registrado.'
      when v_action = 'continuous_day_out' then 'Jornada continua cerrada.'
      else 'Salida final registrada.'
    end,
    'daily', jsonb_build_object(
      'status', v_daily.status,
      'totalWorkedMinutes', v_daily.total_worked_minutes,
      'lunchMinutes', v_daily.lunch_minutes,
      'lateMinutes', v_daily.late_minutes
    ),
    'flags', v_flags
  );
end;
$$;
create or replace function public.attendance_qr_v2_create_token(p_person_id uuid, p_token text)
returns table(token_id uuid)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor public.profiles%rowtype;
  v_person public.attendance_people_v2%rowtype;
  v_hash text := encode(digest(trim(coalesce(p_token, '')), 'sha256'), 'hex');
begin
  if auth.uid() is null then raise exception 'No autorizado'; end if;
  if length(trim(coalesce(p_token, ''))) < 24 then raise exception 'Token invalido'; end if;

  select * into v_actor from public.profiles pr where pr.id = auth.uid() and pr.active and pr.role in ('admin','supervisor');
  if v_actor.id is null then raise exception 'No autorizado'; end if;

  select * into v_person from public.attendance_people_v2 p where p.id = p_person_id and p.business_id = v_actor.business_id and p.active;
  if v_person.id is null then raise exception 'Persona no encontrada'; end if;

  update public.attendance_qr_tokens_v2
  set active = false, revoked_at = now()
  where person_id = p_person_id
    and active;

  return query
  insert into public.attendance_qr_tokens_v2(business_id, person_id, token_hash)
  values(v_actor.business_id, p_person_id, v_hash)
  returning id;
end;
$$;

create or replace function public.attendance_qr_v2_revoke_token(p_token_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'No autorizado'; end if;
  select * into v_actor from public.profiles pr where pr.id = auth.uid() and pr.active and pr.role in ('admin','supervisor');
  if v_actor.id is null then raise exception 'No autorizado'; end if;

  update public.attendance_qr_tokens_v2 qt
  set active = false, revoked_at = now()
  where qt.id = p_token_id
    and qt.business_id = v_actor.business_id;
end;
$$;

create or replace function public.platform_set_attendance_mode(p_business_id uuid, p_attendance_mode text)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if auth.uid() is null or not public.is_platform_admin() then
    raise exception 'No autorizado';
  end if;

  if p_business_id is null or not exists (select 1 from public.businesses b where b.id = p_business_id) then
    raise exception 'Empresa no encontrada';
  end if;

  if p_attendance_mode not in ('legacy','employee_qr_v2') then
    raise exception 'Modo de asistencia invalido';
  end if;

  insert into public.attendance_settings(business_id, attendance_mode)
  values(p_business_id, p_attendance_mode)
  on conflict (business_id)
  do update set attendance_mode = excluded.attendance_mode, updated_at = now();
end;
$$;
grant execute on function public.attendance_qr_v2_category(date,text) to authenticated;
grant execute on function public.platform_set_attendance_mode(uuid,text) to authenticated;
grant execute on function public.attendance_qr_v2_resolve(text) to authenticated;
grant execute on function public.attendance_qr_v2_record(text,text) to authenticated;
grant execute on function public.attendance_qr_v2_create_token(uuid,text) to authenticated;
grant execute on function public.attendance_qr_v2_revoke_token(uuid) to authenticated;

select pg_notify('pgrst','reload schema');

commit;
