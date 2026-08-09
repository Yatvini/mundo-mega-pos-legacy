-- 027_user_edit_audit_and_transaction.sql
-- Usuarios V2: auditoria formal y edicion transaccional de usuarios/empleados.
-- Ejecutar despues de 026_employee_direct_login_accounts.sql.
-- No toca auth.users, username, auth_email ni contrasenas.

begin;

create table if not exists public.user_edit_audit_logs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  target_user_id uuid not null references auth.users(id) on delete restrict,
  action text not null,
  reason text not null,
  changed_fields text[] not null default '{}',
  old_values jsonb not null default '{}'::jsonb,
  new_values jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint user_edit_audit_logs_action_check check (length(trim(action)) > 0),
  constraint user_edit_audit_logs_reason_check check (length(trim(reason)) > 0),
  constraint user_edit_audit_logs_changed_fields_check check (array_length(changed_fields, 1) > 0)
);

alter table public.user_edit_audit_logs enable row level security;

drop policy if exists "user_edit_audit_logs_admin_read" on public.user_edit_audit_logs;
create policy "user_edit_audit_logs_admin_read" on public.user_edit_audit_logs
for select
using (
  business_id = public.current_business_id()
  and public.has_any_role(array['admin']::public.user_role[])
);

drop policy if exists "user_edit_audit_logs_no_direct_insert" on public.user_edit_audit_logs;
create policy "user_edit_audit_logs_no_direct_insert" on public.user_edit_audit_logs
for insert
with check (false);

create index if not exists user_edit_audit_logs_business_created_idx
  on public.user_edit_audit_logs(business_id, created_at desc);
create index if not exists user_edit_audit_logs_target_created_idx
  on public.user_edit_audit_logs(target_user_id, created_at desc);
create index if not exists user_edit_audit_logs_actor_created_idx
  on public.user_edit_audit_logs(actor_user_id, created_at desc);

create or replace function public.update_employee_user_v2(
  p_target_user_id uuid,
  p_full_name text default null,
  p_first_name text default null,
  p_last_name text default null,
  p_employee_email text default null,
  p_phone text default null,
  p_avatar_url text default null,
  p_role public.user_role default null,
  p_branch_id uuid default null,
  p_active boolean default null,
  p_force_password_change boolean default null,
  p_permission_template text default null,
  p_reason text default null
)
returns table(
  user_id uuid,
  full_name text,
  role public.user_role,
  branch_id uuid,
  active boolean,
  has_employee_account boolean,
  changed_fields text[]
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor public.profiles%rowtype;
  v_target public.profiles%rowtype;
  v_account public.employee_accounts%rowtype;
  v_has_account boolean := false;
  v_next_full_name text;
  v_first_name text := trim(coalesce(p_first_name, ''));
  v_last_name text := trim(coalesce(p_last_name, ''));
  v_employee_email text := lower(trim(coalesce(p_employee_email, '')));
  v_phone text := nullif(trim(coalesce(p_phone, '')), '');
  v_avatar_url text := nullif(trim(coalesce(p_avatar_url, '')), '');
  v_permission_template text := nullif(trim(coalesce(p_permission_template, '')), '');
  v_reason text := trim(coalesce(p_reason, ''));
  v_reason_to_store text;
  v_changed text[] := '{}';
  v_sensitive text[] := '{}';
  v_old jsonb;
  v_new jsonb;
  v_now timestamptz := now();
  v_other_admins integer := 0;
begin
  if auth.uid() is null then
    raise exception 'No autorizado';
  end if;

  select *
  into v_actor
  from public.profiles pr
  where pr.id = auth.uid()
    and pr.active
    and pr.role = 'admin';

  if v_actor.id is null or v_actor.business_id is null then
    raise exception 'No autorizado';
  end if;

  if p_target_user_id is null then
    raise exception 'Usuario no encontrado';
  end if;

  select *
  into v_target
  from public.profiles pr
  where pr.id = p_target_user_id
  for update;

  if v_target.id is null then
    raise exception 'Usuario no encontrado';
  end if;

  if v_target.business_id <> v_actor.business_id then
    raise exception 'Usuario no autorizado';
  end if;

  if exists (
    select 1
    from public.platform_admins pa
    where pa.user_id = p_target_user_id
      and pa.active
  ) then
    raise exception 'No se puede editar un administrador de plataforma desde esta pantalla';
  end if;

  if p_role is null or p_role not in ('admin','supervisor','cashier','warehouse') then
    raise exception 'Rol invalido';
  end if;

  if p_active is null then
    raise exception 'Estado invalido';
  end if;

  if p_branch_id is not null and not exists (
    select 1
    from public.branches br
    where br.id = p_branch_id
      and br.business_id = v_actor.business_id
      and br.active
  ) then
    raise exception 'Sucursal invalida';
  end if;

  select *
  into v_account
  from public.employee_accounts ea
  where ea.user_id = p_target_user_id
  for update;

  v_has_account := v_account.user_id is not null;

  if v_has_account and v_account.business_id <> v_actor.business_id then
    raise exception 'Cuenta no autorizada';
  end if;

  if v_has_account then
    if length(v_first_name) = 0 then
      raise exception 'El nombre es obligatorio';
    end if;
    if length(v_last_name) = 0 then
      raise exception 'El apellido es obligatorio';
    end if;
    if v_employee_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' then
      raise exception 'Correo del empleado invalido';
    end if;
    v_next_full_name := trim(v_first_name || ' ' || v_last_name);
  else
    v_next_full_name := trim(coalesce(p_full_name, ''));
    if length(v_next_full_name) = 0 then
      raise exception 'El nombre es obligatorio';
    end if;
  end if;

  if coalesce(v_target.full_name, '') is distinct from v_next_full_name then
    v_changed := array_append(v_changed, 'full_name');
  end if;
  if v_target.role is distinct from p_role then
    v_changed := array_append(v_changed, 'role');
    v_sensitive := array_append(v_sensitive, 'role');
    if p_role = 'admin' then
      v_sensitive := array_append(v_sensitive, 'elevation_to_admin');
    end if;
  end if;
  if v_target.branch_id is distinct from p_branch_id then
    v_changed := array_append(v_changed, 'branch_id');
    v_sensitive := array_append(v_sensitive, 'branch_id');
  end if;
  if v_target.active is distinct from p_active then
    v_changed := array_append(v_changed, 'active');
    v_sensitive := array_append(v_sensitive, 'active');
  end if;

  if v_has_account then
    if coalesce(v_account.first_name, '') is distinct from v_first_name then
      v_changed := array_append(v_changed, 'first_name');
    end if;
    if coalesce(v_account.last_name, '') is distinct from v_last_name then
      v_changed := array_append(v_changed, 'last_name');
    end if;
    if coalesce(v_account.employee_email, '') is distinct from v_employee_email then
      v_changed := array_append(v_changed, 'employee_email');
    end if;
    if v_account.phone is distinct from v_phone then
      v_changed := array_append(v_changed, 'phone');
    end if;
    if v_account.avatar_url is distinct from v_avatar_url then
      v_changed := array_append(v_changed, 'avatar_url');
    end if;
    if v_account.force_password_change is distinct from coalesce(p_force_password_change, false) then
      v_changed := array_append(v_changed, 'force_password_change');
      v_sensitive := array_append(v_sensitive, 'force_password_change');
    end if;
    if v_account.permission_template is distinct from v_permission_template then
      v_changed := array_append(v_changed, 'permission_template');
      v_sensitive := array_append(v_sensitive, 'permission_template');
    end if;
  end if;

  if array_length(v_changed, 1) is null then
    return query
    select v_target.id, v_target.full_name, v_target.role, v_target.branch_id, v_target.active, v_has_account, '{}'::text[];
    return;
  end if;

  if array_length(v_sensitive, 1) is not null and length(v_reason) < 10 then
    raise exception 'Motivo requerido para cambios sensibles';
  end if;

  v_reason_to_store := case
    when length(v_reason) > 0 then v_reason
    else 'Cambio no sensible'
  end;

  if p_target_user_id = auth.uid() then
    if v_target.active is distinct from p_active and p_active = false then
      raise exception 'No puedes inactivarte a ti mismo';
    end if;
    if v_target.role is distinct from p_role then
      raise exception 'No puedes quitarte tu propio acceso de administrador';
    end if;
    if v_target.branch_id is distinct from p_branch_id then
      raise exception 'No puedes cambiar tu propia sucursal';
    end if;
  end if;

  if v_target.role = 'admin' and v_target.active and (p_role <> 'admin' or p_active = false) then
    select count(*)
    into v_other_admins
    from public.profiles pr
    where pr.business_id = v_actor.business_id
      and pr.id <> p_target_user_id
      and pr.role = 'admin'
      and pr.active;

    if v_other_admins = 0 then
      raise exception 'No puedes inactivar o degradar el ultimo administrador activo';
    end if;
  end if;

  v_old := jsonb_build_object(
    'profiles', jsonb_build_object(
      'full_name', v_target.full_name,
      'role', v_target.role,
      'branch_id', v_target.branch_id,
      'active', v_target.active
    ),
    'employee_accounts', case when v_has_account then jsonb_build_object(
      'first_name', v_account.first_name,
      'last_name', v_account.last_name,
      'employee_email', v_account.employee_email,
      'phone', v_account.phone,
      'avatar_url', v_account.avatar_url,
      'force_password_change', v_account.force_password_change,
      'permission_template', v_account.permission_template
    ) else '{}'::jsonb end
  );

  update public.profiles pr
  set full_name = v_next_full_name,
      role = p_role,
      branch_id = p_branch_id,
      active = coalesce(p_active, false)
  where pr.id = p_target_user_id
    and pr.business_id = v_actor.business_id;

  if v_has_account then
    update public.employee_accounts ea
    set first_name = v_first_name,
        last_name = v_last_name,
        employee_email = v_employee_email,
        phone = v_phone,
        avatar_url = v_avatar_url,
        force_password_change = coalesce(p_force_password_change, false),
        permission_template = v_permission_template,
        updated_at = v_now
    where ea.user_id = p_target_user_id
      and ea.business_id = v_actor.business_id;
  end if;

  v_new := jsonb_build_object(
    'profiles', jsonb_build_object(
      'full_name', v_next_full_name,
      'role', p_role,
      'branch_id', p_branch_id,
      'active', coalesce(p_active, false)
    ),
    'employee_accounts', case when v_has_account then jsonb_build_object(
      'first_name', v_first_name,
      'last_name', v_last_name,
      'employee_email', v_employee_email,
      'phone', v_phone,
      'avatar_url', v_avatar_url,
      'force_password_change', coalesce(p_force_password_change, false),
      'permission_template', v_permission_template
    ) else '{}'::jsonb end
  );

  insert into public.user_edit_audit_logs(
    business_id, actor_user_id, target_user_id, action, reason,
    changed_fields, old_values, new_values, created_at
  )
  values(
    v_actor.business_id, auth.uid(), p_target_user_id, 'update',
    v_reason_to_store, v_changed, v_old, v_new, v_now
  );

  return query
  select pr.id, pr.full_name, pr.role, pr.branch_id, pr.active, v_has_account, v_changed
  from public.profiles pr
  where pr.id = p_target_user_id;
end $$;

grant execute on function public.update_employee_user_v2(
  uuid,text,text,text,text,text,text,public.user_role,uuid,boolean,boolean,text,text
) to authenticated;

select pg_notify('pgrst','reload schema');

commit;
