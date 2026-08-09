# Usuarios V2 - Auditoria y edicion transaccional

## Estado final

Publicado, SQL aplicado, validado en sitio, auditado y funcionando en produccion.

## Fecha de publicacion

2026-08-09

## Rama

legacy/production-snapshot

## URL de produccion

https://mundo-mega-pos-legacy.netlify.app/

## Commit funcional

585afc6 feat(users): add audited transactional user edits

## Migracion

supabase/027_user_edit_audit_and_transaction.sql

## Objetivo

Cerrar los riesgos residuales de Usuarios V1 al mover la edicion de usuarios a un flujo transaccional, auditado y protegido por reglas de negocio centralizadas en PostgreSQL/Supabase.

## Alcance implementado

- Tabla formal de auditoria `public.user_edit_audit_logs`.
- RPC transaccional `public.update_employee_user_v2`.
- Endpoint existente `/api/update-employee-user` actualizado para llamar la RPC.
- Frontend actualizado para forzar ediciones sensibles desde modal auditado.
- Edicion transaccional de `profiles`, `employee_accounts` y auditoria dentro de una sola RPC.
- Motivo obligatorio de minimo 10 caracteres para cambios sensibles.
- Proteccion del ultimo administrador activo por empresa.
- Proteccion de autoedicion critica.
- Bloqueo de edicion de platform admin desde la pantalla de Usuarios.
- Auditoria solo DB en V2, sin pantalla visual de historial.
- No-op sin registro de auditoria cuando no hay cambios reales.

## Archivos creados

- `supabase/027_user_edit_audit_and_transaction.sql`

## Archivos modificados

- `netlify/functions/update-employee-user.js`
- `src/lib/store.ts`
- `src/App.tsx`

## Tabla user_edit_audit_logs

Tabla creada: `public.user_edit_audit_logs`.

Columnas verificadas:
- `id`
- `business_id`
- `actor_user_id`
- `target_user_id`
- `action`
- `reason`
- `changed_fields`
- `old_values`
- `new_values`
- `created_at`

RLS activo: `rowsecurity = true`.

Policies:
- `user_edit_audit_logs_admin_read`
- `user_edit_audit_logs_no_direct_insert`

Indices:
- `user_edit_audit_logs_actor_created_idx`
- `user_edit_audit_logs_business_created_idx`
- `user_edit_audit_logs_pkey`
- `user_edit_audit_logs_target_created_idx`

## RPC update_employee_user_v2

RPC creada: `public.update_employee_user_v2`.

Responsabilidades:
- Validar `auth.uid()`.
- Permitir ejecucion solo a admin activo de la empresa.
- Validar que el usuario objetivo pertenezca a la misma empresa.
- Bloquear edicion de platform admin activo desde esta pantalla.
- Validar rol permitido.
- Validar sucursal activa de la misma empresa.
- Detectar si existe `employee_accounts`.
- Editar `profiles` y `employee_accounts` de forma transaccional.
- Exigir motivo para cambios sensibles.
- Proteger ultimo admin activo.
- Proteger autoedicion critica.
- Auditar `old_values`, `new_values` y `changed_fields`.
- No registrar auditoria si no hubo cambios reales.

Campos sensibles:
- `role`
- `branch_id`
- `active`
- `force_password_change`
- `permission_template`
- elevacion a admin

Permiso verificado:
- `authenticated_can_execute = true`

## Endpoint update-employee-user.js

Endpoint actualizado: `netlify/functions/update-employee-user.js`.

Cambios:
- Mantiene el endpoint existente `/api/update-employee-user`.
- Valida sesion con token Bearer.
- Usa service role solo del lado servidor.
- Llama la RPC `update_employee_user_v2`.
- Envia `p_reason`.
- Ya no actualiza `profiles` directo.
- Ya no actualiza `employee_accounts` directo.
- No crea endpoint paralelo.
- No toca username, contrasena, `auth_email` ni Supabase Auth.

## Cambios frontend

Archivos:
- `src/lib/store.ts`
- `src/App.tsx`

Cambios:
- `UpdateEmployeeUserInput` incluye `reason`.
- `updateEmployeeUser` mantiene `/api/update-employee-user`.
- El listado de usuarios muestra rol como solo lectura.
- El listado de usuarios muestra estado activo/inactivo como solo lectura.
- La asignacion de equipo muestra sucursal como solo lectura.
- Se eliminaron rutas UI rapidas para cambiar rol, estado o sucursal.
- El boton Editar abre el modal de edicion.
- El modal exige motivo minimo de 10 caracteres para cambios sensibles.
- El modal envia cambios por `updateEmployeeUser`.
- Username no editable.
- Contrasena no editable.
- `auth_email` no editable.
- Crear empleado nuevo sigue visible.
- Invitaciones siguen visibles.
- No se agrego pantalla de auditoria en UI.

## Validacion SQL 027

Gerencia aplico manualmente SQL 027 en Supabase.

Verificacion confirmada:
- Tabla `user_edit_audit_logs` existe.
- Columnas verificadas.
- RLS activo.
- Policies creadas.
- RPC `update_employee_user_v2` existe.
- `authenticated` puede ejecutar la RPC.
- Indices creados.

## Prueba en sitio

Gerencia confirmo:
- Admin por correo funciona.
- Usuarios carga normal.
- Rol aparece como solo lectura en listado.
- Estado activo/inactivo aparece como solo lectura.
- Ya no existe cambio rapido de rol.
- Ya no existe boton rapido Activo/Inactivo.
- Boton Editar abre modal.
- Modal muestra Motivo del cambio.
- Cambio sensible sin motivo o con menos de 10 caracteres queda bloqueado.
- Cambio controlado con motivo valido o no sensible funciona.
- `/api/update-employee-user` respondio OK.
- Listado refresca.
- Cambio se refleja.
- Login por correo sigue funcionando.
- Login por username sigue funcionando.
- Invitaciones siguen visibles.
- Crear empleado nuevo sigue visible y funcionando visualmente.
- Console sin errores.

## Verificacion de auditoria DB

Gerencia confirmo registro en `public.user_edit_audit_logs` con:
- `id`
- `business_id`
- `actor_user_id`
- `target_user_id`
- `action = update`
- `reason`
- `changed_fields`
- `old_values`
- `new_values`
- `created_at`

Ejemplo validado:
- `reason`: Cambio no sensible
- `changed_fields`: `["full_name","last_name"]`
- `old_values` con valores anteriores
- `new_values` con valores nuevos
- `actor_user_id` registrado
- `target_user_id` registrado

## Validaciones tecnicas

- TypeScript correcto.
- Build correcto.
- `git diff --check` correcto.
- SQL 027 aplicado.
- Merge fast-forward correcto.
- Push a `legacy/production-snapshot` correcto.
- Produccion responde 200.
- No se hizo deploy manual.

## Exclusiones

- No se toco `.env`.
- No se modifico Netlify config.
- No se modifico `package.json`.
- No se modifico `pnpm-lock.yaml`.
- No se tocaron migraciones anteriores.
- No se tocaron funciones de login:
  - `create-employee-user.js`
  - `resolve-login-username.js`
  - `complete-force-password-change.js`
- No se toco Supabase Auth.
- No se cambio contrasena.
- No se edito username.
- No se edito `auth_email`.
- No se toco POS.
- No se toco caja.
- No se toco ventas.
- No se toco inventario.
- No se tocaron reportes.
- No se creo endpoint paralelo.
- No se agrego UI de auditoria.

## Riesgos residuales

1. Auditoria visible solo en DB; no hay pantalla de historial en UI.
2. `active=false` todavia no deshabilita directamente el usuario en Supabase Auth.
3. Reseteo/cambio de contrasena por admin queda fuera de V2.
4. Edicion de username queda fuera de V2.
5. Consulta visual de auditoria queda para V3.
6. Bloqueo fuerte de sesion activa tras inactivar usuario queda para mejora futura.

## Recomendaciones futuras

1. Usuarios V3: historial visual de auditoria en UI.
2. Reset de contrasena por admin con auditoria.
3. Bloqueo fuerte de usuario inactivo a nivel Auth/session.
4. Edicion segura de username, si Gerencia lo aprueba.
5. Panel de auditoria filtrable por usuario, actor, fecha y tipo de cambio.
6. Alertas para elevacion a admin.
7. Exportacion de auditoria.

## Estado final

Usuarios V2 - Auditoria y edicion transaccional:

PUBLICADO, VALIDADO EN SITIO, AUDITADO, DOCUMENTADO Y ARCHIVADO.
