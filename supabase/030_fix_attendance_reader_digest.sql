-- 030_fix_attendance_reader_digest.sql
-- Hotfix para resolver pgcrypto.digest() en Asistencia V2.1 lector QR.
-- Ejecutar despues de 029_attendance_reader_v2.sql.
-- No cambia tablas, datos, RLS ni policies; solo recrea funciones afectadas.

create extension if not exists pgcrypto with schema extensions;

create or replace function public.attendance_reader_v2_context(p_reader_token text)
returns table(
  reader_id uuid,
  business_id uuid,
  business_name text
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_hash text := encode(extensions.digest(trim(coalesce(p_reader_token, '')), 'sha256'), 'hex');
begin
  if length(trim(coalesce(p_reader_token, ''))) < 24 then
    raise exception 'Lector no valido';
  end if;

  return query
  select
    rt.id,
    rt.business_id,
    b.name
  from public.attendance_reader_tokens_v2 rt
  join public.businesses b on b.id = rt.business_id and b.status = 'active'
  join public.attendance_settings s
    on s.business_id = rt.business_id
   and s.attendance_mode = 'employee_qr_v2'
  where rt.token_hash = v_hash
    and rt.active
    and rt.revoked_at is null
  limit 1;

  if not found then
    raise exception 'Lector no valido o inactivo';
  end if;
end;
$$;

create or replace function public.attendance_reader_v2_create_token(p_business_id uuid, p_token text)
returns table(
  reader_id uuid,
  business_id uuid,
  active boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor public.profiles%rowtype;
  v_hash text := encode(extensions.digest(trim(coalesce(p_token, '')), 'sha256'), 'hex');
begin
  if length(trim(coalesce(p_token, ''))) < 24 then
    raise exception 'Token invalido';
  end if;

  select *
  into v_actor
  from public.attendance_reader_v2_actor(p_business_id);

  if not exists (select 1 from public.businesses b where b.id = p_business_id and b.status = 'active') then
    raise exception 'Empresa no encontrada o inactiva';
  end if;

  if not exists (
    select 1
    from public.attendance_settings s
    where s.business_id = p_business_id
      and s.attendance_mode = 'employee_qr_v2'
  ) then
    raise exception 'La empresa no esta configurada para Asistencia QR V2';
  end if;

  update public.attendance_reader_tokens_v2 rt
  set active = false,
      revoked_at = now()
  where rt.business_id = p_business_id
    and rt.active;

  return query
  insert into public.attendance_reader_tokens_v2(business_id, token_hash)
  values(p_business_id, v_hash)
  returning id, attendance_reader_tokens_v2.business_id, attendance_reader_tokens_v2.active, attendance_reader_tokens_v2.created_at;
end;
$$;

grant execute on function public.attendance_reader_v2_context(text) to authenticated, service_role;
grant execute on function public.attendance_reader_v2_create_token(uuid,text) to authenticated, service_role;

select pg_notify('pgrst','reload schema');
