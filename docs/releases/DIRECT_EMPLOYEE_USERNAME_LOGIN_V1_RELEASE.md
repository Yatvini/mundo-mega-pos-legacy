# Creacion directa de empleados con username/password V1

## Estado final

Publicado, probado y funcionando en produccion.

## Fecha de publicacion

2026-08-01

## Contexto de produccion

- Proyecto: Mundo Mega POS Legacy
- Rama de produccion: `legacy/production-snapshot`
- URL de produccion: https://mundo-mega-pos-legacy.netlify.app/
- Supabase produccion: `mundo-mega-pos-legacy-prod`

## Commits de la entrega

1. `fa5e37c feat(auth): add direct employee username login`
2. `5581972 fix(auth): avoid employee account embed during store load`
3. `84f5fdc fix(auth): resolve username login without embedded joins`

## Objetivo de la mejora

Permitir que el admin o centro corporativo cree empleados directamente desde la seccion Usuarios, sin depender del envio de una invitacion por correo. El empleado puede iniciar sesion con usuario y contrasena, mientras el correo real queda como dato informativo/de contacto del empleado.

## Decision tecnica principal

- Supabase Auth se mantiene como autoridad interna de sesion.
- `username` se agrega como alias global de acceso.
- `auth_email` funciona como correo tecnico interno para autenticar contra Supabase Auth.
- El email real del empleado se mantiene como dato de contacto.
- El login por email se conserva para usuarios actuales, administradores y platform admin.
- El flujo existente de invitaciones se conserva por compatibilidad.

## Alcance funcional V1

- Creacion directa de empleado desde Usuarios.
- Captura de nombre.
- Captura de apellido.
- Captura de correo de contacto.
- Captura de telefono.
- Campo `avatar_url` preparado.
- Captura de username.
- Captura de contrasena.
- Confirmacion de contrasena.
- Rol `admin`, `supervisor`, `cashier` o `warehouse`.
- Sucursal asignada.
- Estado activo/inactivo.
- `force_password_change`.
- Login por correo o usuario.

## Exclusiones V1

- No se elimino el sistema de invitaciones.
- No se reemplazo Supabase Auth.
- No se implemento subida real de avatar a Storage.
- No se implementaron permisos granulares reales por modulo.
- No se creo tabla de contrasenas.
- No se guardan contrasenas en PostgreSQL.
- No se modifico POS, caja, ventas, inventario ni reportes.

## Archivos creados

- `supabase/026_employee_direct_login_accounts.sql`
- `netlify/functions/create-employee-user.js`
- `netlify/functions/resolve-login-username.js`
- `netlify/functions/complete-force-password-change.js`

## Archivos modificados

- `src/App.tsx`
- `src/lib/store.ts`

## Migracion SQL 026

La migracion `supabase/026_employee_direct_login_accounts.sql` fue aplicada manualmente en Supabase produccion y creo o actualizo:

- `public.employee_accounts`
- `public.employee_account_provisioning`
- Funcion `public.current_employee_login_status()`
- Actualizacion de `public.handle_new_user()`
- RLS
- Policies
- Grants
- `pg_notify('pgrst','reload schema')`

## Tabla employee_accounts

Campos documentados:

- `user_id`
- `business_id`
- `username`
- `auth_email`
- `employee_email`
- `first_name`
- `last_name`
- `phone`
- `avatar_url`
- `force_password_change`
- `dark_mode`
- `permission_template`
- `permissions`
- `created_by`
- `created_at`
- `updated_at`

## Tabla employee_account_provisioning

`employee_account_provisioning` funciona como puente temporal para que `handle_new_user` cree `profiles` de forma segura cuando se crea un Auth user tecnico. Permite conectar el usuario creado en Supabase Auth con la empresa, sucursal, rol y estado operativo correspondientes.

## Netlify Function create-employee-user.js

La funcion:

- Valida Bearer token.
- Valida admin activo.
- Valida `business_id`.
- Valida sucursal.
- Valida username global.
- Valida correo.
- Valida contrasena minima de 8 caracteres.
- Genera `auth_email` tecnico.
- Crea Auth user.
- Crea `employee_accounts`.
- No envia correo.
- Usa service role solo server-side.
- Hace rollback de Auth user si falla el flujo.

## Netlify Function resolve-login-username.js

La funcion:

- Recibe username.
- Normaliza username.
- Busca en `employee_accounts`.
- Valida profile activo.
- Valida empresa activa.
- Devuelve solo `auth_email` tecnico.
- No devuelve datos sensibles.
- Incluye hotfix para no depender de joins embebidos PostgREST.

## Netlify Function complete-force-password-change.js

La funcion:

- Requiere Bearer token.
- Valida usuario autenticado.
- Limpia `force_password_change` solo del propio `user_id`.
- No permite modificar otro usuario.

## Cambios en login

- El campo visual pasa a aceptar "Correo o usuario".
- Si el valor contiene `@`, se usa login por email.
- Si el valor no contiene `@`, se resuelve primero el username.
- Luego se usa Supabase Auth normal.
- No se muestra el `auth_email` tecnico.
- No se guarda contrasena en frontend ni en PostgreSQL.

## Cambios en Usuarios / TeamSettings

- Nuevo formulario de creacion directa de empleados.
- Se conserva el flujo anterior de invitacion.
- El formulario queda dividido funcionalmente en informacion basica, informacion de acceso y permisos/rol.
- Los roles actuales siguen siendo la seguridad real.

## Hotfix 1

Commit: `5581972 fix(auth): avoid employee account embed during store load`

Despues del deploy inicial, produccion mostro "No fue posible cargar los datos". La causa probable fue que `loadStore` y `loadTeam` dependian del embed `employee_accounts(...)` dentro de `profiles`. La solucion fue consultar `employee_accounts` por separado y tolerar ausencia o fallo para usuarios existentes, sin romper la carga de perfil, negocio y sucursal.

## Hotfix 2

Commit: `84f5fdc fix(auth): resolve username login without embedded joins`

El login por username fallaba con `/api/resolve-login-username` status 400. SQL directo confirmaba que empleado, profile, business y Auth user existian. La causa probable fue el join embebido PostgREST en la Netlify Function. La solucion fue resolver username con consultas separadas a `employee_accounts`, `profiles` y `businesses`.

## Seguridad

- `SUPABASE_SERVICE_ROLE_KEY` se usa solo server-side.
- No hay service role en `src/`.
- No se guardan contrasenas en PostgreSQL.
- RLS sigue usando `auth.uid()`.
- `profiles` sigue controlando `business_id`, `branch_id`, `role` y `active`.
- `username` es unico global.
- Un usuario inactivo no puede operar en la aplicacion.
- Las invitaciones existentes quedan preservadas.

## Pruebas realizadas

- SQL 026 aplicado y verificado.
- Tablas creadas.
- Columnas verificadas.
- Indices unicos verificados.
- RLS verificado.
- Policies verificadas.
- Funcion `current_employee_login_status` verificada.
- Trigger `on_auth_user_created` verificado.
- `tsc` correcto.
- Build correcto.
- Login admin por correo correcto.
- Carga negocio/sucursal/usuario correcta despues de hotfix.
- Empleado de prueba creado correctamente.
- `employee_accounts`, `profiles` y `auth.users` verificados.
- Login por username funcionando correctamente despues del hotfix.
- Sistema principal funcionando.

## Riesgos residuales

- `resolve-login-username` no tiene rate limiting avanzado.
- `auth_email` tecnico se usa internamente.
- Un usuario inactivo podria autenticar tecnicamente si conoce el `auth_email`, pero app/RLS bloquean operacion.
- Los permisos granulares por modulo aun no son seguridad real.
- Avatar real requiere Storage seguro en V2.

## Recomendaciones V2

- Rate limiting para `resolve-login-username`.
- Gestion admin de reseteo de contrasena.
- Deshabilitar Auth user cuando `profile.active=false`.
- Subida real de avatar con Supabase Storage.
- Auditoria de creacion/cambio de contrasena.
- Permisos granulares respaldados por backend/RLS/RPC.
- Mejor UI para plantillas de permisos.
- Mantenimiento y limpieza de usuarios de prueba.

## Estado final

Creacion directa de empleados con username/password V1: PUBLICADO, PROBADO Y FUNCIONANDO EN PRODUCCION.
