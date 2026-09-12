# Usuarios - Eliminacion permanente segura

## Estado final

- Publicado.
- Validado en produccion.
- Listo para archivo.

## Fecha de cierre

2026-09-12

## Objetivo de la mejora

Esta entrega agrega eliminacion permanente segura de usuarios en Mundo Mega POS Legacy, limitada a usuarios sin historial operativo. El objetivo es permitir limpieza controlada de usuarios creados por error o sin uso real, protegiendo ventas, caja, inventario, reportes y auditorias operativas.

La eliminacion del acceso de Supabase Auth se realiza desde backend mediante Netlify Function server-side. SQL 041 no borra `auth.users`.

## Alcance funcional

- Boton "Eliminar permanentemente" en Usuarios.
- Accion visible solo para admin.
- Confirmacion fuerte con palabra `ELIMINAR`.
- Motivo obligatorio con minimo 10 caracteres.
- Validacion de elegibilidad antes de eliminar.
- Eliminacion de Supabase Auth desde backend server-side.
- Limpieza de registros publicos permitidos.
- Auditoria de preparacion, bloqueo, exito y fallo de Auth.

## Decisiones gerenciales

- No se permite eliminacion forzada de usuarios con historial en V1.
- Usuarios con historial deben inactivarse.
- Solo admin puede eliminar usuarios.
- Supervisor no puede eliminar usuarios.
- No se permite self-delete.
- No se permite eliminar el ultimo admin activo.
- No se permite eliminar `platform_admin`.

## Arquitectura tecnica

- `profiles` es la identidad operativa del sistema POS.
- `profiles.id` coincide con `auth.users.id`.
- `employee_accounts` administra el login directo con username/password.
- `netlify/functions/delete-employee-user.js` coordina el flujo seguro backend.
- SQL 041 define la auditoria y las RPC transaccionales de control.
- Supabase Auth se elimina solo desde server-side usando `SUPABASE_SERVICE_ROLE_KEY`.
- Frontend no recibe ni usa service role.

## SQL 041

Archivo aplicado y versionado:

- `supabase/041_user_permanent_delete_controls.sql`

Incluye:

- Tabla `public.user_delete_audit_logs`.
- RPC `public.admin_check_user_delete_eligibility`.
- RPC `public.admin_prepare_user_permanent_delete`.
- RPC `public.admin_delete_user_public_records`.
- RPC `public.admin_mark_user_auth_delete_failed`.
- RLS habilitado en auditoria.
- Grants sin `anon`.
- Execute para `authenticated` y `service_role`.
- Funciones `security definer`.
- `set search_path=public`.
- `pg_notify('pgrst','reload schema')`.

## Tabla de auditoria

Tabla:

- `public.user_delete_audit_logs`

Acciones auditadas:

- `delete_prepared`
- `permanent_delete`
- `delete_blocked`
- `auth_delete_failed`

La auditoria conserva snapshots de empresa, actor, usuario objetivo, correo, username, rol, motivo, bloqueos y metadata tecnica.

## Flujo Auth/DB

Orden operativo final:

1. Check eligibility.
2. Prepare/audit.
3. Delete Supabase Auth desde Netlify Function server-side.
4. Finalize public records.
5. Mark `auth_delete_failed` si falla Auth.

Este orden evita dejar un Auth user vivo sin profile cuando falla la eliminacion de Auth.

## Reglas de elegibilidad

La eliminacion se bloquea si:

- El usuario objetivo es el usuario actual.
- El usuario objetivo es el ultimo admin activo.
- El usuario objetivo es `platform_admin`.
- El actor no es admin.
- El usuario pertenece a otra empresa.
- El usuario tiene historial operativo.

## Tablas revisadas para historial

La elegibilidad bloquea si el usuario aparece en:

- `cash_sessions.user_id`
- `cash_movements.user_id`
- `cash_movements.updated_by`
- `cash_movements.voided_by`
- `sales.cashier_id`
- `purchases.user_id`
- `inventory_movements.user_id`
- `sale_returns.user_id`
- `sale_cancellations.user_id`
- `user_edit_audit_logs.actor_user_id`
- `user_edit_audit_logs.target_user_id`
- `cash_movement_audit_logs.performed_by`
- `team_invitations.invited_by`
- `employee_accounts.created_by`
- `employee_account_provisioning.created_by`
- `attendance_movement_types_v3.created_by`
- `platform_admins.user_id`
- `business_admin_invitations.invited_by`

## Registros que puede eliminar

Solo despues de elegibilidad aprobada y Auth eliminado correctamente, el flujo puede limpiar:

- `employee_account_provisioning` relacionado.
- `employee_accounts` del target.
- Invitaciones pendientes relacionadas.
- `profiles` del target si aun existe.

## Registros que NO elimina

Esta entrega no elimina:

- Ventas.
- Caja.
- Inventario.
- Reportes.
- Auditorias operativas.
- Historial operativo.
- `auth.users` desde SQL.

## Seguridad

- No hay service role en frontend.
- No hay DELETE directo frontend para usuarios.
- No hay DELETE directo desde la Function sobre tablas publicas.
- No hay SQL delete sobre `auth.users`.
- No hay grants a `anon`.
- Multiempresa protegida por `business_id`.
- Auditoria obligatoria.
- Backend es la autoridad final.

## Validacion realizada

Gerencia confirmo:

- Funcionalidad publicada.
- Usuarios carga correctamente.
- Boton visible.
- Eliminacion segura operativa.
- Compatibilidad general del sistema.

## Estado de publicacion

- Rama produccion: `legacy/production-snapshot`.
- Commit final: `77f2147 feat(users): add safe permanent delete controls`.
- Asset validado: `assets/index-DmZPIUKq.js`.
- Deploy: automatico por Netlify.

## Riesgos residuales

- Auth y DB no forman una unica transaccion.
- Si Auth delete pasa y la finalizacion publica falla, requiere revision manual.
- Usuarios con historial no se eliminan; deben inactivarse.
- Requiere cuidado administrativo antes de confirmar eliminaciones reales.

## Reglas operativas futuras

- Preferir inactivar cuando exista historial.
- No eliminar usuarios reales sin revisar historial.
- No reaplicar SQL 041.
- Toda eliminacion debe tener motivo.
- Solo admin debe usar esta funcion.

## Pendientes recomendados futuros

- Modal visual mas formal en vez de `prompt` / `confirm`.
- Panel de auditoria de eliminaciones.
- Contrato JSON con `deleted:false` explicito en errores 403.
- Revision futura para desactivar Auth conservando perfil historico.
- Mejorar textos con acentos si se desea.

## Cierre

La mejora de Usuarios - Eliminacion permanente segura queda validada, publicada y lista para archivo.
