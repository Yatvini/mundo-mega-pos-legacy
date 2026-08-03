# Edición de información de usuarios/empleados V1

## Estado final

Publicado, validado en sitio y funcionando en producción.

## Fecha de publicación

2026-08-02

## Rama de producción

legacy/production-snapshot

## URL de producción

https://mundo-mega-pos-legacy.netlify.app/

## Commit publicado

816c968 feat(users): add employee edit workflow

## Asset producción

assets/index-Bu45VPae.js

## Objetivo de la mejora

Permitir que el administrador/centro corporativo edite información de usuarios y empleados ya creados desde la sección Usuarios, manteniendo el alcance seguro de V1 sin cambios en Auth/login, SQL ni módulos operativos del POS.

## Alcance funcional V1

Para usuarios antiguos sin `employee_accounts`:

- Editar nombre completo.
- Editar rol.
- Editar sucursal.
- Activar/inactivar.

Para empleados directos con `employee_accounts`:

- Editar nombre.
- Editar apellido.
- Editar correo de contacto.
- Editar teléfono.
- Editar `avatar_url`.
- Editar rol.
- Editar sucursal.
- Activar/inactivar.
- Editar `force_password_change`.
- Editar `permission_template` visual si aplica.

## Campos bloqueados/no editables

- `username`.
- Contraseña.
- `auth_email` técnico.
- `user_id`.
- `business_id`.
- `created_by`.
- `created_at`.
- Platform admin.
- Usuarios de otra empresa.
- Permisos granulares reales.
- Datos internos de Supabase Auth.

## Archivos creados

- `netlify/functions/update-employee-user.js`

## Archivos modificados

- `src/App.tsx`
- `src/lib/store.ts`

## Netlify Function `update-employee-user.js`

- Acepta `POST` y `OPTIONS`.
- Valida Bearer token.
- Usa `SUPABASE_SERVICE_ROLE_KEY` solo server-side.
- Valida admin activo.
- Valida `role = admin`.
- Valida misma empresa.
- Valida sucursal activa de la misma empresa.
- Valida rol permitido.
- No edita platform admin.
- No edita `username`.
- No edita contraseña.
- No edita `auth_email`.
- No toca Supabase Auth.
- No envía correos.
- No borra usuarios.

## Cambios en `store.ts`

- Se agregó `UpdateEmployeeUserInput`.
- Se agregó `updateEmployeeUser()`.
- Se usa `/api/update-employee-user` con Bearer token.
- Se extendió `TeamMember` con datos adicionales.
- `loadTeam` sigue compatible con usuarios antiguos.

## Cambios en `App.tsx` / `TeamSettings`

- Botón Editar por usuario.
- Modal/panel "Editar usuario".
- Carga datos actuales.
- Diferencia usuario antiguo vs empleado directo.
- Guardar llama `updateEmployeeUser`.
- Guardar refresca listado.
- Cancelar cierra sin guardar.
- Conserva invitaciones.
- Conserva creación de empleado nuevo.
- No toca login/Auth.

## Exclusiones V1

- No hubo SQL.
- No hubo migraciones.
- No hubo auditoría formal en DB.
- No hubo RPC transaccional.
- No se modificó login/Auth.
- No se modificaron `create-employee-user.js`, `resolve-login-username.js` ni `complete-force-password-change.js`.
- No se modificó Netlify config.
- No se tocó `.env`.
- No se modificaron POS/caja/ventas/inventario/reportes.
- No se implementó cambio de contraseña.
- No se implementó edición de `username`.
- No se deshabilitó Auth user cuando `active=false`.

## Validaciones técnicas

- `tsc` correcto.
- Build correcto.
- `git diff --check` correcto.
- Merge fast-forward correcto.
- Push a `legacy/production-snapshot` correcto.
- Netlify publicó asset nuevo.
- `/api/update-employee-user` existe y exige sesión.

## Prueba en sitio

- Admin por correo funciona.
- Usuarios carga normal.
- Editar aparece.
- Modal abre.
- Carga datos actuales.
- Usuario antiguo editable.
- Empleado directo editable.
- `username` no editable.
- Contraseña no editable.
- `auth_email` no editable.
- Cancelar cierra sin guardar.
- Guardar funciona.
- Listado refresca.
- Cambios se reflejan.
- Invitaciones siguen visibles.
- Crear empleado nuevo sigue visible.
- Login por correo sigue funcionando.
- Login por username sigue funcionando.
- Console sin errores.
- `/api/update-employee-user` OK.

## Riesgos residuales

- No hay auditoría formal en DB.
- No hay transacción real entre `profiles` y `employee_accounts`.
- Si `profiles` actualiza y `employee_accounts` falla, podría existir estado parcial.
- `active=false` no cierra sesión Auth inmediatamente.
- No se valida "último admin de empresa".
- Un admin puede elevar otro usuario a admin según alcance V1.
- `username` y cambio de contraseña quedan para V2.

## Recomendaciones V2

- Auditoría formal con tabla de historial.
- RPC transaccional para evitar estado parcial.
- Motivo obligatorio para cambios sensibles.
- Control para impedir inactivar/eliminar el último admin.
- Reseteo/cambio de contraseña por admin con Netlify Function y auditoría.
- Edición segura de `username` si Gerencia lo aprueba.
- Deshabilitar Auth user cuando `active=false`.
- Registro de quién editó, cuándo, valores anteriores y valores nuevos.

## Estado final

Edición de información de usuarios/empleados V1:

PUBLICADO, VALIDADO EN SITIO, DOCUMENTADO Y ARCHIVADO.
