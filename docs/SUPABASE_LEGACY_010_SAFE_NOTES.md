# Supabase Legacy 010 Safe Notes

## Objetivo

`supabase/010_multi_tenant_saas_legacy_safe.sql` instala la estructura SaaS necesaria para Mundo Mega POS Legacy sin ejecutar el bootstrap historico del administrador inicial.

## Que se tomo del 010 original

- Extension `unaccent`.
- Nuevas columnas de `public.businesses`.
- Generacion de `slug` para negocios existentes.
- Indices y constraints de `businesses`.
- Tabla `public.platform_admins`.
- Tabla `public.business_admin_invitations`.
- RLS de plataforma.
- Policies generales de plataforma.
- Funciones generales de plataforma:
  - `is_platform_admin`
  - `platform_summary`
  - `platform_list_businesses`
  - `platform_create_business`
  - `platform_update_business`
  - `platform_resend_business_invitation`
  - `handle_new_user`
  - `current_business_id`
- Grants necesarios para usuarios autenticados.

## Que se omitio

- Insercion inicial en `public.platform_admins` basada en correo.
- Actualizacion inicial de `public.businesses` basada en correo.
- Cualquier bootstrap que dependa de un profile administrador ya existente.

## Por que se omitio

El Supabase legacy nuevo debe crearse con un administrador basado en el UUID real de `auth.users`. Los bloques omitidos dependen de un correo historico hardcodeado y pueden dejar el proyecto sin administrador o asignar privilegios al usuario equivocado.

## Riesgos que elimina

- Asignar `platform_admins` al usuario incorrecto.
- Actualizar el negocio Mundo Mega usando una cuenta que no existe en el proyecto nuevo.
- Depender de un correo historico para instalar schema.
- Mezclar bootstrap operativo con estructura de base de datos.

## Riesgos residuales

- El archivo debe ejecutarse despues de `009_corporate_control_hub.sql`.
- El archivo espera que existan tablas base como `businesses`, `branches`, `profiles`, `team_invitations`, `sales` y `products`.
- `platform_create_business` usa `gen_random_uuid()`. En Supabase suele estar disponible, pero si el proyecto no tiene `pgcrypto`, ejecutar `create extension if not exists pgcrypto;` antes de usar esa funcion.
- `platform_admins` queda vacio hasta ejecutar el bootstrap con UUID real.
- RLS puede bloquear la aplicacion si no existe un `profiles` correcto para el usuario administrador.

## Orden de ejecucion final

1. `supabase/schema.sql`
2. `supabase/002_auth_onboarding.sql`
3. Omitir `supabase/003_confirm_first_admin.sql`
4. `supabase/004_runtime_operations.sql`
5. `supabase/005_users_and_roles.sql`
6. `supabase/006_branches.sql`
7. `supabase/007_returns_and_cancellations.sql`
8. `supabase/008_branch_control_center.sql`
9. `supabase/009_corporate_control_hub.sql`
10. `supabase/010_multi_tenant_saas_legacy_safe.sql`
11. `supabase/011_fix_business_creation.sql`
12. `supabase/012_business_admin_and_cash_closure_reports.sql`
13. `supabase/013_cash_closure_movement_details.sql`
14. `supabase/014_attendance_payroll.sql`
15. `supabase/015_attendance_branch_kiosks.sql`
16. `supabase/016_attendance_half_shift.sql`
17. `supabase/017_restore_previous_attendance.sql`

## Despues de ejecutar 010 safe

Crear el administrador inicial con `docs/SUPABASE_LEGACY_BOOTSTRAP_ADMIN.md`:

1. Crear usuario en Supabase Authentication.
2. Copiar UUID real.
3. Crear o confirmar business Mundo Mega.
4. Crear o confirmar sucursal principal.
5. Crear `profiles`.
6. Crear `platform_admins`.
7. Verificar acceso con RLS.

## Advertencias

- No ejecutar `supabase/010_multi_tenant_saas.sql` completo en el Supabase legacy nuevo.
- No ejecutar `supabase/003_confirm_first_admin.sql`.
- No usar correos hardcodeados para bootstrap.
- No crear `profiles` con UUID inventado.
- No conectar frontend ni Vercel hasta confirmar que `platform_admins`, `businesses`, `branches` y `profiles` contienen datos correctos.
