# Supabase Legacy Bootstrap Admin

## Objetivo

Crear el primer administrador de Mundo Mega POS Legacy Produccion en el nuevo Supabase `mundo-mega-pos-legacy-prod`, sin usar correos hardcodeados y sin modificar `auth.users` directamente salvo caso excepcional.

## Procedimiento seguro

1. Entrar a Supabase Dashboard del proyecto legacy.
2. Ir a Authentication > Users.
3. Crear el usuario administrador con el correo autorizado.
4. Confirmar el correo desde el panel o enviar invitacion/reset, segun la politica definida.
5. Copiar el UUID real del usuario.
6. Crear o confirmar el negocio principal Mundo Mega.
7. Crear o confirmar la sucursal principal.
8. Crear `profiles` para el usuario admin.
9. Crear `platform_admins` para el mismo UUID.
10. Validar acceso con consultas de solo lectura.

No usar:

- correo hardcodeado de migraciones antiguas;
- `SUPABASE_SERVICE_ROLE_KEY` en frontend;
- valores reales en archivos versionados;
- placeholders sin reemplazar.

## Datos que se deben tener antes del SQL

- `ADMIN_USER_ID_AQUI`: UUID real de Authentication > Users.
- `ADMIN_EMAIL_AQUI`: correo del administrador.
- `ADMIN_FULL_NAME_AQUI`: nombre visible del administrador.
- `BUSINESS_ID_AQUI`: UUID del negocio Mundo Mega, si ya existe.
- `BRANCH_ID_AQUI`: UUID de la sucursal principal, si ya existe.

## Plantilla SQL

NO EJECUTAR SIN REEMPLAZAR PLACEHOLDERS.

Esta plantilla es para SQL Editor, despues de instalar el schema y migraciones aplicables.

```sql
-- NO EJECUTAR SIN REEMPLAZAR PLACEHOLDERS.
-- Reemplazar:
-- ADMIN_USER_ID_AQUI
-- ADMIN_EMAIL_AQUI
-- ADMIN_FULL_NAME_AQUI
-- BUSINESS_ID_AQUI
-- BRANCH_ID_AQUI

begin;

-- 1. Confirmar que el usuario Auth existe.
select id, email
from auth.users
where id = 'ADMIN_USER_ID_AQUI'::uuid
  and lower(email) = lower('ADMIN_EMAIL_AQUI');

-- 2. Crear negocio principal si aun no existe.
insert into public.businesses (
  id,
  name,
  legal_name,
  currency,
  timezone,
  slug,
  industry,
  slogan,
  primary_color,
  accent_color,
  plan,
  status,
  modules,
  max_branches,
  max_users
)
values (
  'BUSINESS_ID_AQUI'::uuid,
  'Mundo Mega',
  'Grupo Multimarkets S.A.',
  'GTQ',
  'America/Guatemala',
  'mundo-mega',
  'minimarket',
  'Minimarket mas cercano.',
  '#155b3d',
  '#c9f45c',
  'enterprise',
  'active',
  '{"pos":true,"inventory":true,"purchases":true,"customers":true,"cash":true,"reports":true,"branches":true,"returns":true,"corporate":true}'::jsonb,
  100,
  500
)
on conflict (id) do update set
  name = excluded.name,
  legal_name = excluded.legal_name,
  industry = excluded.industry,
  plan = excluded.plan,
  status = excluded.status,
  modules = excluded.modules,
  max_branches = excluded.max_branches,
  max_users = excluded.max_users,
  updated_at = now();

-- 3. Crear sucursal principal si aun no existe.
insert into public.branches (
  id,
  business_id,
  name,
  active
)
values (
  'BRANCH_ID_AQUI'::uuid,
  'BUSINESS_ID_AQUI'::uuid,
  'Sucursal Central',
  true
)
on conflict (id) do update set
  business_id = excluded.business_id,
  name = excluded.name,
  active = true;

-- 4. Crear o actualizar profile administrador.
insert into public.profiles (
  id,
  business_id,
  branch_id,
  full_name,
  role,
  active
)
values (
  'ADMIN_USER_ID_AQUI'::uuid,
  'BUSINESS_ID_AQUI'::uuid,
  'BRANCH_ID_AQUI'::uuid,
  'ADMIN_FULL_NAME_AQUI',
  'admin',
  true
)
on conflict (id) do update set
  business_id = excluded.business_id,
  branch_id = excluded.branch_id,
  full_name = excluded.full_name,
  role = 'admin',
  active = true;

-- 5. Crear platform admin.
insert into public.platform_admins (
  user_id,
  full_name,
  active
)
values (
  'ADMIN_USER_ID_AQUI'::uuid,
  'ADMIN_FULL_NAME_AQUI',
  true
)
on conflict (user_id) do update set
  full_name = excluded.full_name,
  active = true;

-- 6. Sembrar categorias de asistencia para el negocio.
select public.attendance_seed_defaults('BUSINESS_ID_AQUI'::uuid);

commit;
```

## Validaciones posteriores

```sql
select u.id, u.email, p.full_name, p.role, p.active
from auth.users u
join public.profiles p on p.id = u.id
where u.id = 'ADMIN_USER_ID_AQUI'::uuid;
```

```sql
select pa.user_id, pa.full_name, pa.active
from public.platform_admins pa
where pa.user_id = 'ADMIN_USER_ID_AQUI'::uuid;
```

```sql
select b.id, b.name, b.status, br.id as branch_id, br.name as branch_name
from public.businesses b
join public.branches br on br.business_id = b.id
where b.id = 'BUSINESS_ID_AQUI'::uuid;
```

```sql
select business_id, name, kind, active
from public.attendance_categories
where business_id = 'BUSINESS_ID_AQUI'::uuid
order by sort_order, name;
```

## Validar RLS desde la aplicacion

1. Configurar `.env` local con URL y anon key del Supabase legacy.
2. Iniciar sesion con el usuario administrador.
3. Confirmar que carga perfil, negocio y sucursal.
4. Confirmar que aparece acceso al panel multiempresa.
5. Confirmar que puede listar empresas y entrar a Mundo Mega.
6. Confirmar que puede crear producto, abrir caja y generar QR de asistencia.

## Casos excepcionales

Modificar `auth.users` directamente solo debe considerarse si el correo del administrador no fue confirmado y Supabase Auth no permite resolverlo desde el panel. En ese caso, hacer una consulta limitada al UUID real del usuario y dejar registro operativo de la razon.

No usar el archivo `003_confirm_first_admin.sql` sin adaptarlo: contiene un correo hardcodeado historico y no representa el procedimiento seguro para el Supabase legacy nuevo.
