# Supabase Legacy Install Runbook

## Objetivo

Instalar manualmente el schema de Supabase para `mundo-mega-pos-legacy-prod`, sin mezclarlo con el proyecto nuevo ni con el Supabase anterior. Esta guia no contiene claves reales y no debe ejecutarse desde CLI automatizado.

## Proyecto destino

- Nombre sugerido: `mundo-mega-pos-legacy-prod`
- Uso: Mundo Mega POS Legacy Produccion
- Estrategia: schema limpio + carga selectiva de datos operativos

## Advertencias criticas

- No ejecutar SQL contra el Supabase nuevo hasta confirmar que el proyecto seleccionado es `mundo-mega-pos-legacy-prod`.
- No ejecutar `003_confirm_first_admin.sql` en una instalacion nueva.
- No ejecutar completo `010_multi_tenant_saas.sql` sin revisar los bloques con correo hardcodeado.
- No pegar secretos en Git, README, issues, chat o archivos versionados.
- No conectar el frontend ni Vercel hasta validar schema, Auth, RLS y administrador inicial.

Nunca pegar en Git:

- `SUPABASE_SERVICE_ROLE_KEY`
- database password
- JWT secret
- tokens privados
- claves de deploy
- connection strings completas

## Orden exacto de ejecucion SQL

Ejecutar en Supabase Dashboard > SQL Editor, un archivo por vez, esperando resultado exitoso antes de continuar.

1. `supabase/schema.sql`
2. `supabase/002_auth_onboarding.sql`
3. Omitir `supabase/003_confirm_first_admin.sql`
4. `supabase/004_runtime_operations.sql`
5. `supabase/005_users_and_roles.sql`
6. `supabase/006_branches.sql`
7. `supabase/007_returns_and_cancellations.sql`
8. `supabase/008_branch_control_center.sql`
9. `supabase/009_corporate_control_hub.sql`
10. `supabase/010_multi_tenant_saas.sql`, solo por bloques seguros o adaptados
11. `supabase/011_fix_business_creation.sql`
12. `supabase/012_business_admin_and_cash_closure_reports.sql`
13. `supabase/013_cash_closure_movement_details.sql`
14. `supabase/014_attendance_payroll.sql`
15. `supabase/015_attendance_branch_kiosks.sql`
16. `supabase/016_attendance_half_shift.sql`
17. `supabase/017_restore_previous_attendance.sql`

## Por que se omite 003

`003_confirm_first_admin.sql` actualiza `auth.users` para confirmar el correo `yatdavid326@gmail.com` y luego consulta ese usuario con su profile, negocio y sucursal. No es una migracion de schema; es una operacion puntual de recuperacion para una cuenta especifica.

En el Supabase legacy nuevo, el primer administrador debe crearse manualmente desde Authentication y luego vincularse con `profiles` y `platform_admins` usando su UUID real.

## Como manejar 010

### Bloques seguros

Se pueden ejecutar cuando `schema.sql` a `009` ya terminaron bien:

- `create extension if not exists unaccent`
- `alter table public.businesses add column if not exists ...`
- `update public.businesses set slug = ... where slug is null or slug = ''`
- indices y constraints de `businesses`
- `create table if not exists public.platform_admins`
- `create table if not exists public.business_admin_invitations`
- RLS y policies generales de plataforma
- funciones generales: `is_platform_admin`, `platform_summary`, `platform_list_businesses`, `platform_create_business`, `platform_update_business`, `platform_resend_business_invitation`, `handle_new_user`, `current_business_id`
- grants de funciones

### Bloques que requieren adaptacion

No ejecutar sin reemplazar la estrategia por UUID real:

- `insert into public.platform_admins ... where lower(u.email)=lower('yatdavid326@gmail.com')`
- `update public.businesses ... where ... lower(u.email)=lower('yatdavid326@gmail.com')`
- cualquier bloque que dependa de un correo hardcodeado
- cualquier bloque que asuma que ya existe un `profiles` correcto para el admin

### Recomendacion

No ejecutar los bloques hardcodeados de `010`. Reemplazarlos por el procedimiento de `docs/SUPABASE_LEGACY_BOOTSTRAP_ADMIN.md` usando el UUID real del usuario administrador creado en Supabase Auth.

## Checklist manual en Supabase Dashboard

1. Crear proyecto `mundo-mega-pos-legacy-prod`.
2. Confirmar region, password de base y plan.
3. Guardar Project URL, anon key y service role key en un gestor seguro.
4. Abrir SQL Editor.
5. Ejecutar el orden SQL definido en esta guia.
6. Omitir `003`.
7. Ejecutar `010` por bloques, evitando los bloques hardcodeados.
8. Ejecutar `011` a `017`.
9. Crear usuario admin desde Authentication > Users.
10. Ejecutar bootstrap admin con placeholders reemplazados.
11. Ejecutar consultas de verificacion.
12. Configurar Auth Site URL y Redirect URLs.
13. Configurar `.env` local sin commitearlo.
14. Configurar Vercel Environment Variables.

## Cuando detenerse

Detener el proceso si ocurre cualquiera de estos errores:

- `relation does not exist`
- `type does not exist`
- error sobre `auth.users`
- error creando `current_business_id`
- error de RLS/policy duplicada no entendido
- error en `platform_create_business`
- error en `handle_new_user`
- cualquier error donde el SQL Editor no reporte exito completo para el bloque actual

Errores aceptables solo con revision humana:

- objeto ya existe en una base no limpia
- policy ya existe cuando se esta reintentando una instalacion parcial
- constraint ya existe si el bloque usa `drop constraint if exists` antes

## Consultas de verificacion posteriores

Extensiones:

```sql
select extname
from pg_extension
where extname in ('uuid-ossp', 'pgcrypto', 'unaccent')
order by extname;
```

Tablas principales:

```sql
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in (
    'businesses','branches','profiles','categories','products','inventory',
    'customers','suppliers','sales','sale_items','sale_payments',
    'cash_sessions','cash_movements','purchases','purchase_items',
    'sale_cancellations','sale_returns','sale_return_items',
    'platform_admins','business_admin_invitations',
    'attendance_employees','attendance_categories','attendance_kiosks','attendance_events'
  )
order by table_name;
```

RLS:

```sql
select c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
  and c.relname in (
    'businesses','branches','profiles','products','inventory','sales',
    'platform_admins','business_admin_invitations','attendance_events'
  )
order by c.relname;
```

Funciones RPC:

```sql
select routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'current_business_id','current_user_role','has_any_role',
    'complete_sale','receive_purchase','cancel_sale','return_sale',
    'is_platform_admin','platform_summary','platform_list_businesses',
    'platform_create_business','platform_update_business','platform_delete_business',
    'cash_closure_reports','cash_closure_movement_details',
    'attendance_seed_defaults','attendance_ensure_kiosk',
    'attendance_kiosk_data','attendance_mark'
  )
order by routine_name;
```

Triggers:

```sql
select trigger_schema, trigger_name, event_object_schema, event_object_table
from information_schema.triggers
where trigger_name = 'on_auth_user_created'
order by trigger_schema, trigger_name;
```

Policies:

```sql
select schemaname, tablename, policyname
from pg_policies
where schemaname = 'public'
order by tablename, policyname;
```

Datos base:

```sql
select count(*) as businesses_count from public.businesses;
select count(*) as branches_count from public.branches;
select count(*) as profiles_count from public.profiles;
select count(*) as platform_admins_count from public.platform_admins;
```

Asistencia:

```sql
select business_id, name, kind, sort_order, active
from public.attendance_categories
order by business_id, sort_order, name;
```

## Antes de conectar el frontend

- Confirmar que existe al menos un usuario Auth.
- Confirmar que ese usuario tiene `profiles.id = auth.users.id`.
- Confirmar que `businesses.status = 'active'`.
- Confirmar que `platform_admins.user_id` apunta al UUID correcto.
- Confirmar que `current_business_id()` devuelve negocio para el admin autenticado.
- Configurar `.env` local con `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY`.

## Antes de conectar Vercel

- Configurar `VITE_SUPABASE_URL`.
- Configurar `VITE_SUPABASE_ANON_KEY`.
- Configurar `SUPABASE_URL`.
- Configurar `SUPABASE_SERVICE_ROLE_KEY` solo como variable server-side.
- Configurar Supabase Auth Site URL y Redirect URLs con dominio legacy.
- Validar que `/api/send-invitation-email` use el proyecto legacy.

## Antes de operar en tienda

- Cargar productos y categorias.
- Cargar inventario inicial por sucursal.
- Confirmar apertura/cierre de caja.
- Probar una venta real de bajo impacto.
- Probar anulacion/devolucion.
- Probar ticket/reimpresion.
- Crear empleados de asistencia.
- Generar QR de asistencia por sucursal.
- Probar marcaje de asistencia desde enlace anonimo.
