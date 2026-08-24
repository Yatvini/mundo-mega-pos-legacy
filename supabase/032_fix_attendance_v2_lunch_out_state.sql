-- 032_fix_attendance_v2_lunch_out_state.sql
-- Hotfix para alinear las acciones permitidas de Asistencia QR V2 con la validacion transaccional.
-- Ejecutar despues de 031_fix_attendance_qr_v2_digest.sql.
-- No cambia tablas, datos, RLS, policies, tokens ni digest; solo recrea funciones de resolve/record.

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
  elsif v_ctx.daily_status = 'open' then
    v_actions := array['check_out'];
    if v_ctx.uses_lunch then v_actions := array_prepend('lunch_out', v_actions); end if;
    if v_ctx.allows_half_day then v_actions := array_append(v_actions, 'half_day_out'); end if;
    if v_ctx.allows_continuous_day then v_actions := array_append(v_actions, 'continuous_day_out'); end if;
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
  v_allowed text[] := '{}';
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

  insert into public.attendance_daily_records_v2(
    business_id,
    branch_id,
    person_id,
    attendance_date,
    status,
    workday_type
  )
  values(v_ctx.business_id, v_ctx.branch_id, v_ctx.person_id, v_today, 'open', 'full_day')
  on conflict (business_id, person_id, attendance_date) do nothing;

  select *
  into v_daily
  from public.attendance_daily_records_v2 d
  where d.business_id = v_ctx.business_id
    and d.person_id = v_ctx.person_id
    and d.attendance_date = v_today
  for update;

  v_logical_status := case
    when v_daily.id is null or v_daily.check_in_at is null then 'sin_registro'
    when v_daily.check_out_at is not null or v_daily.status = 'closed' then 'closed'
    when v_daily.status = 'incomplete' then 'incomplete'
    when v_daily.lunch_out_at is not null and v_daily.lunch_in_at is null then 'in_lunch'
    when v_daily.lunch_in_at is not null and v_daily.check_out_at is null then 'regreso_de_almuerzo'
    else 'open'
  end;

  if v_logical_status = 'sin_registro' then
    v_allowed := array['check_in'];
  elsif v_logical_status = 'open' then
    v_allowed := array['check_out'];
    if v_ctx.uses_lunch then v_allowed := array_prepend('lunch_out', v_allowed); end if;
    if v_ctx.allows_half_day then v_allowed := array_append(v_allowed, 'half_day_out'); end if;
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

  insert into public.attendance_events_v2(
    business_id,
    branch_id,
    person_id,
    token_id,
    event_type,
    occurred_at,
    attendance_date,
    source,
    flags
  )
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

grant execute on function public.attendance_qr_v2_resolve(text) to authenticated;
grant execute on function public.attendance_qr_v2_record(text,text) to authenticated;

select pg_notify('pgrst','reload schema');
