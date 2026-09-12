-- 042_cash_movement_categories.sql
-- Catalogo corporativo V1 para clasificar movimientos manuales de caja por empresa.
-- El tipo de movimiento es opcional, informativo y no afecta saldos, cierres ni calculos contables.

begin;

create table if not exists public.cash_movement_categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  name text not null,
  normalized_name text not null,
  description text null,
  is_active boolean not null default true,
  created_by uuid null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_by uuid null references public.profiles(id),
  updated_at timestamptz null,
  constraint cash_movement_categories_name_length check (char_length(btrim(name)) between 2 and 60),
  constraint cash_movement_categories_normalized_name_length check (char_length(btrim(normalized_name)) between 2 and 60)
);

create unique index if not exists cash_movement_categories_active_name_idx
  on public.cash_movement_categories(business_id, normalized_name)
  where is_active;

create index if not exists cash_movement_categories_business_active_name_idx
  on public.cash_movement_categories(business_id, is_active desc, name asc);

alter table public.cash_movement_categories enable row level security;

drop policy if exists "cash_movement_categories_same_business_read" on public.cash_movement_categories;
create policy "cash_movement_categories_same_business_read" on public.cash_movement_categories
for select
using (
  business_id = current_business_id()
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.active
      and p.business_id = public.cash_movement_categories.business_id
  )
);

alter table public.cash_movements
  add column if not exists movement_category_id uuid null references public.cash_movement_categories(id),
  add column if not exists movement_category_name_snapshot text null;

create index if not exists cash_movements_category_idx
  on public.cash_movements(movement_category_id);

create or replace function public.cash_movement_category_normalize(p_name text)
returns text
language sql
immutable
set search_path=public
as $$
  select lower(regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g'));
$$;

create or replace function public.cash_movement_actor_profile()
returns public.profiles
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
begin
  select
    p.id,
    p.business_id,
    p.branch_id,
    p.full_name,
    p.role,
    p.active
  into v_profile
  from public.profiles p
  where p.id = auth.uid()
    and p.active
    and p.business_id is not null;

  if v_profile.id is null then
    raise exception 'Usuario no autorizado';
  end if;

  return v_profile;
end $$;

create or replace function public.admin_list_cash_movement_categories()
returns table(
  id uuid,
  business_id uuid,
  name text,
  description text,
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
begin
  v_profile := public.cash_movement_actor_profile();

  if v_profile.role not in ('admin','supervisor') then
    raise exception 'No autorizado para administrar tipos de movimiento de caja';
  end if;

  return query
  select
    c.id,
    c.business_id,
    c.name,
    c.description,
    c.is_active,
    c.created_at,
    c.updated_at
  from public.cash_movement_categories c
  where c.business_id = v_profile.business_id
  order by c.is_active desc, c.name asc;
end $$;

create or replace function public.admin_create_cash_movement_category(
  p_name text,
  p_description text default null
)
returns table(
  id uuid,
  business_id uuid,
  name text,
  description text,
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_normalized text := public.cash_movement_category_normalize(p_name);
  v_description text := nullif(btrim(coalesce(p_description, '')), '');
  v_category_id uuid;
begin
  v_profile := public.cash_movement_actor_profile();

  if v_profile.role not in ('admin','supervisor') then
    raise exception 'No autorizado para crear tipos de movimiento de caja';
  end if;

  if char_length(v_name) < 2 or char_length(v_name) > 60 then
    raise exception 'El nombre debe tener entre 2 y 60 caracteres';
  end if;

  if exists (
    select 1
    from public.cash_movement_categories c
    where c.business_id = v_profile.business_id
      and c.normalized_name = v_normalized
      and c.is_active
  ) then
    raise exception 'Ya existe un tipo de movimiento activo con ese nombre';
  end if;

  insert into public.cash_movement_categories(
    business_id, name, normalized_name, description, is_active, created_by
  )
  values(
    v_profile.business_id, v_name, v_normalized, v_description, true, auth.uid()
  )
  returning public.cash_movement_categories.id into v_category_id;

  return query
  select c.id, c.business_id, c.name, c.description, c.is_active, c.created_at, c.updated_at
  from public.cash_movement_categories c
  where c.id = v_category_id;
end $$;

create or replace function public.admin_update_cash_movement_category(
  p_category_id uuid,
  p_name text,
  p_description text default null,
  p_is_active boolean default true
)
returns table(
  id uuid,
  business_id uuid,
  name text,
  description text,
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
  v_existing record;
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_normalized text := public.cash_movement_category_normalize(p_name);
  v_description text := nullif(btrim(coalesce(p_description, '')), '');
  v_is_active boolean := coalesce(p_is_active, true);
begin
  v_profile := public.cash_movement_actor_profile();

  if v_profile.role not in ('admin','supervisor') then
    raise exception 'No autorizado para editar tipos de movimiento de caja';
  end if;

  if char_length(v_name) < 2 or char_length(v_name) > 60 then
    raise exception 'El nombre debe tener entre 2 y 60 caracteres';
  end if;

  select
    c.id,
    c.business_id,
    c.name,
    c.normalized_name,
    c.description,
    c.is_active,
    c.created_by,
    c.created_at,
    c.updated_by,
    c.updated_at
  into v_existing
  from public.cash_movement_categories c
  where c.id = p_category_id
    and c.business_id = v_profile.business_id
  for update;

  if v_existing.id is null then
    raise exception 'Tipo de movimiento no encontrado';
  end if;

  if v_is_active and exists (
    select 1
    from public.cash_movement_categories c
    where c.business_id = v_profile.business_id
      and c.normalized_name = v_normalized
      and c.is_active
      and c.id <> p_category_id
  ) then
    raise exception 'Ya existe un tipo de movimiento activo con ese nombre';
  end if;

  update public.cash_movement_categories
  set name = v_name,
      normalized_name = v_normalized,
      description = v_description,
      is_active = v_is_active,
      updated_by = auth.uid(),
      updated_at = now()
  where id = p_category_id;

  return query
  select c.id, c.business_id, c.name, c.description, c.is_active, c.created_at, c.updated_at
  from public.cash_movement_categories c
  where c.id = p_category_id;
end $$;

create or replace function public.list_active_cash_movement_categories()
returns table(
  id uuid,
  business_id uuid,
  name text,
  description text,
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
begin
  v_profile := public.cash_movement_actor_profile();

  return query
  select
    c.id,
    c.business_id,
    c.name,
    c.description,
    c.is_active,
    c.created_at,
    c.updated_at
  from public.cash_movement_categories c
  where c.business_id = v_profile.business_id
    and c.is_active
  order by c.name asc;
end $$;

create or replace function public.record_cash_movement(
  p_session_id uuid,
  p_kind text,
  p_amount numeric,
  p_description text,
  p_movement_category_id uuid default null
)
returns table(
  movement_id uuid,
  kind text,
  amount numeric,
  description text,
  movement_category_id uuid,
  movement_category_name_snapshot text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
  v_session record;
  v_category record;
  v_kind text := btrim(coalesce(p_kind, ''));
  v_description text := btrim(coalesce(p_description, ''));
  v_movement_id uuid;
begin
  v_profile := public.cash_movement_actor_profile();

  if v_kind not in ('income','expense') then
    raise exception 'El tipo debe ser Ingreso o Retiro';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'El monto debe ser mayor a cero';
  end if;

  if char_length(v_description) = 0 then
    raise exception 'La descripcion es obligatoria';
  end if;

  select
    cs.id,
    cs.branch_id,
    cs.closed_at,
    b.business_id
  into v_session
  from public.cash_sessions cs
  join public.branches b on b.id = cs.branch_id
  where cs.id = p_session_id
  for update of cs;

  if v_session.id is null then
    raise exception 'La caja no existe';
  end if;

  if v_session.business_id <> v_profile.business_id then
    raise exception 'Caja no autorizada';
  end if;

  if v_profile.role not in ('admin','supervisor') and v_session.branch_id <> v_profile.branch_id then
    raise exception 'Caja no autorizada para esta sucursal';
  end if;

  if v_session.closed_at is not null then
    raise exception 'No se pueden registrar movimientos en una caja cerrada';
  end if;

  if p_movement_category_id is not null then
    select
      c.id,
      c.business_id,
      c.name,
      c.normalized_name,
      c.description,
      c.is_active,
      c.created_by,
      c.created_at,
      c.updated_by,
      c.updated_at
    into v_category
    from public.cash_movement_categories c
    where c.id = p_movement_category_id
      and c.business_id = v_profile.business_id
      and c.is_active;

    if v_category.id is null then
      raise exception 'Tipo de movimiento no valido o inactivo';
    end if;
  end if;

  insert into public.cash_movements(
    session_id,
    user_id,
    kind,
    amount,
    description,
    movement_category_id,
    movement_category_name_snapshot
  )
  values(
    p_session_id,
    auth.uid(),
    v_kind,
    p_amount,
    v_description,
    case when p_movement_category_id is null then null else v_category.id end,
    case when p_movement_category_id is null then null else v_category.name end
  )
  returning public.cash_movements.id into v_movement_id;

  return query
  select
    cm.id,
    cm.kind::text,
    cm.amount,
    cm.description,
    cm.movement_category_id,
    cm.movement_category_name_snapshot,
    cm.created_at
  from public.cash_movements cm
  where cm.id = v_movement_id;
end $$;

revoke all on function public.cash_movement_category_normalize(text) from public, anon, authenticated;
revoke all on function public.cash_movement_actor_profile() from public, anon, authenticated;
revoke all on function public.admin_list_cash_movement_categories() from public, anon;
revoke all on function public.admin_create_cash_movement_category(text,text) from public, anon;
revoke all on function public.admin_update_cash_movement_category(uuid,text,text,boolean) from public, anon;
revoke all on function public.list_active_cash_movement_categories() from public, anon;
revoke all on function public.record_cash_movement(uuid,text,numeric,text,uuid) from public, anon;

grant execute on function public.admin_list_cash_movement_categories() to authenticated, service_role;
grant execute on function public.admin_create_cash_movement_category(text,text) to authenticated, service_role;
grant execute on function public.admin_update_cash_movement_category(uuid,text,text,boolean) to authenticated, service_role;
grant execute on function public.list_active_cash_movement_categories() to authenticated, service_role;
grant execute on function public.record_cash_movement(uuid,text,numeric,text,uuid) to authenticated, service_role;

select pg_notify('pgrst', 'reload schema');

commit;
