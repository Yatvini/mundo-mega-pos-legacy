-- 031_fix_attendance_qr_v2_digest.sql
-- Hotfix para resolver pgcrypto.digest() en Asistencia QR V2 personal/empleado.
-- Ejecutar despues de 028_attendance_qr_v2.sql y 030_fix_attendance_reader_digest.sql.
-- No cambia tablas, datos, RLS ni policies; solo recrea funciones afectadas.

create extension if not exists pgcrypto with schema extensions;

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
  v_hash text := encode(extensions.digest(trim(coalesce(p_token, '')), 'sha256'), 'hex');
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

create or replace function public.attendance_qr_v2_create_token(p_person_id uuid, p_token text)
returns table(token_id uuid)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor public.profiles%rowtype;
  v_person public.attendance_people_v2%rowtype;
  v_hash text := encode(extensions.digest(trim(coalesce(p_token, '')), 'sha256'), 'hex');
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

grant execute on function public.attendance_qr_v2_create_token(uuid,text) to authenticated;

select pg_notify('pgrst','reload schema');
