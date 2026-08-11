-- 029_attendance_reader_v2.sql
-- Asistencia V2.1: lector QR por link de empresa.
-- Ejecutar despues de 028_attendance_qr_v2.sql.
-- No guarda tokens planos; solo token_hash sha256.

create extension if not exists pgcrypto;

create table if not exists public.attendance_reader_tokens_v2 (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid null references public.branches(id) on delete set null,
  token_hash text not null unique,
  active boolean not null default true,
  revoked_at timestamptz null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz null,
  constraint attendance_reader_tokens_v2_hash_check check (length(trim(token_hash)) >= 32)
);

create index if not exists attendance_reader_tokens_v2_business_active_idx
  on public.attendance_reader_tokens_v2(business_id, active);

create index if not exists attendance_reader_tokens_v2_hash_idx
  on public.attendance_reader_tokens_v2(token_hash);

alter table public.attendance_reader_tokens_v2 enable row level security;

drop policy if exists "attendance_reader_tokens_v2_business_read" on public.attendance_reader_tokens_v2;
create policy "attendance_reader_tokens_v2_business_read" on public.attendance_reader_tokens_v2
for select using (
  business_id = public.current_business_id()
  and exists (
    select 1 from public.profiles pr
    where pr.id = auth.uid()
      and pr.active
      and pr.role in ('admin','supervisor')
      and pr.business_id = attendance_reader_tokens_v2.business_id
  )
);

drop policy if exists "attendance_reader_tokens_v2_no_direct_insert" on public.attendance_reader_tokens_v2;
create policy "attendance_reader_tokens_v2_no_direct_insert" on public.attendance_reader_tokens_v2
for insert with check (false);

drop policy if exists "attendance_reader_tokens_v2_no_direct_update" on public.attendance_reader_tokens_v2;
create policy "attendance_reader_tokens_v2_no_direct_update" on public.attendance_reader_tokens_v2
for update using (false) with check (false);

create or replace function public.attendance_reader_v2_actor(p_business_id uuid)
returns public.profiles
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor public.profiles%rowtype;
begin
  if auth.uid() is null then
    raise exception 'No autorizado';
  end if;

  select *
  into v_actor
  from public.profiles pr
  where pr.id = auth.uid()
    and pr.active
    and pr.role in ('admin','supervisor');

  if v_actor.id is null and not public.is_platform_admin() then
    raise exception 'No autorizado';
  end if;

  if v_actor.id is not null and v_actor.business_id <> p_business_id then
    raise exception 'No autorizado para esta empresa';
  end if;

  return v_actor;
end;
$$;

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
  v_hash text := encode(digest(trim(coalesce(p_reader_token, '')), 'sha256'), 'hex');
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
  v_hash text := encode(digest(trim(coalesce(p_token, '')), 'sha256'), 'hex');
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
    raise exception 'La empresa no está configurada para Asistencia QR V2';
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

create or replace function public.attendance_reader_v2_revoke_token(p_reader_token_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_reader public.attendance_reader_tokens_v2%rowtype;
  v_actor public.profiles%rowtype;
begin
  select *
  into v_reader
  from public.attendance_reader_tokens_v2 rt
  where rt.id = p_reader_token_id;

  if v_reader.id is null then
    raise exception 'Lector no encontrado';
  end if;

  select *
  into v_actor
  from public.attendance_reader_v2_actor(v_reader.business_id);

  update public.attendance_reader_tokens_v2 rt
  set active = false,
      revoked_at = now()
  where rt.id = p_reader_token_id;
end;
$$;

create or replace function public.attendance_reader_v2_resolve(p_reader_token text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_reader record;
begin
  select * into v_reader from public.attendance_reader_v2_context(p_reader_token);

  update public.attendance_reader_tokens_v2 rt
  set last_used_at = now()
  where rt.id = v_reader.reader_id;

  return jsonb_build_object(
    'ok', true,
    'readerId', v_reader.reader_id,
    'businessId', v_reader.business_id,
    'businessName', v_reader.business_name,
    'message', 'Lector QR activo.'
  );
end;
$$;

create or replace function public.attendance_reader_v2_validate_employee_token(p_reader_token text, p_employee_token text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_reader record;
  v_employee record;
  v_resolved jsonb;
begin
  select * into v_reader from public.attendance_reader_v2_context(p_reader_token);
  select * into v_employee from public.attendance_qr_v2_context(p_employee_token);

  if v_employee.business_id <> v_reader.business_id then
    raise exception 'El QR pertenece a otra empresa';
  end if;

  v_resolved := public.attendance_qr_v2_resolve(p_employee_token);

  return jsonb_build_object(
    'ok', true,
    'readerId', v_reader.reader_id,
    'businessId', v_reader.business_id,
    'businessName', v_reader.business_name,
    'person', v_resolved -> 'person',
    'daily', v_resolved -> 'daily',
    'allowedActions', v_resolved -> 'allowedActions',
    'message', coalesce(v_resolved -> 'daily' ->> 'message', 'Empleado validado.')
  );
end;
$$;

create or replace function public.attendance_reader_v2_record(p_reader_token text, p_employee_token text, p_action text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_reader record;
  v_employee record;
begin
  select * into v_reader from public.attendance_reader_v2_context(p_reader_token);
  select * into v_employee from public.attendance_qr_v2_context(p_employee_token);

  if v_employee.business_id <> v_reader.business_id then
    raise exception 'El QR pertenece a otra empresa';
  end if;

  update public.attendance_reader_tokens_v2 rt
  set last_used_at = now()
  where rt.id = v_reader.reader_id;

  return public.attendance_qr_v2_record(p_employee_token, p_action);
end;
$$;

grant execute on function public.attendance_reader_v2_actor(uuid) to authenticated, service_role;
grant execute on function public.attendance_reader_v2_context(text) to authenticated, service_role;
grant execute on function public.attendance_reader_v2_create_token(uuid,text) to authenticated, service_role;
grant execute on function public.attendance_reader_v2_revoke_token(uuid) to authenticated, service_role;
grant execute on function public.attendance_reader_v2_resolve(text) to authenticated, service_role;
grant execute on function public.attendance_reader_v2_validate_employee_token(text,text) to authenticated, service_role;
grant execute on function public.attendance_reader_v2_record(text,text,text) to authenticated, service_role;

select pg_notify('pgrst','reload schema');
