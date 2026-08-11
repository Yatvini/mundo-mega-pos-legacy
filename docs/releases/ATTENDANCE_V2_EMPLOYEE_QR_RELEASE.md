# Asistencia V2 — QR personalizado por empleado

## Estado final

Publicado, validado en sitio, documentado y archivado.

## Fecha de cierre

11 de agosto de 2026

## Rama

`legacy/production-snapshot`

## Producción

https://mundo-mega-pos-legacy.netlify.app/

## Commits

- `e974832 feat(attendance): add employee QR attendance v2`
- `e8047f9 fix(attendance): show employee QR link and age category`

## Migración

- `supabase/028_attendance_qr_v2.sql`

## Objetivo de la mejora

Crear un modo alternativo de asistencia por QR personalizado por empleado/persona, sin romper la asistencia legacy existente.

## Alcance implementado

- Configuración de modo de asistencia por empresa.
- Empresas existentes quedan en modo `legacy`.
- Empresa nueva puede elegir `legacy` o `employee_qr_v2`.
- Personas QR V2 independientes del usuario de login.
- Edad calculada desde fecha de nacimiento.
- Categoría sugerida por edad.
- Override manual de categoría.
- Registro de sexo.
- Token QR seguro.
- `token_hash` en base de datos.
- Link público `/asistencia/qr/<token>`.
- Fallback `?attendanceQrV2=<token>`.
- Netlify Function `attendance-qr-v2`.
- Eventos V2.
- Resumen diario básico.
- Entrada.
- Salida a almuerzo.
- Regreso de almuerzo.
- Salida final.
- Medio día.
- Jornada continua.
- Bloqueo de duplicados.
- Revocación y regeneración de token.
- Bloqueo de jornada cerrada.
- Bloqueo de persona/token inactivo.
- Link textual imprimible.

## Tablas nuevas

- `attendance_settings`
- `attendance_people_v2`
- `attendance_qr_tokens_v2`
- `attendance_events_v2`
- `attendance_daily_records_v2`

## RPCs nuevas

- `attendance_qr_v2_resolve`
- `attendance_qr_v2_record`
- `attendance_qr_v2_create_token`
- `attendance_qr_v2_revoke_token`
- `platform_set_attendance_mode`

## Netlify Function

- `netlify/functions/attendance-qr-v2.js`

## Archivos modificados

- `src/App.tsx`
- `src/lib/store.ts`
- `netlify/functions/attendance-qr-v2.js`
- `supabase/028_attendance_qr_v2.sql`

## Seguridad

- El token plano no se guarda en base de datos.
- Solo se guarda `token_hash`.
- El token es revocable y regenerable.
- No se muestra `token_hash` en la interfaz.
- `create-token` y `revoke-token` requieren Bearer token.
- `resolve` y `record` son públicos por diseño QR.
- RLS activo.
- Sin `DELETE` directo por policy.
- Registro protegido con locks `FOR UPDATE`.
- Ventana `duplicate_scan_window` para bloqueo de marcajes duplicados.
- No se usa servicio externo QR.

## Compatibilidad legacy

- `/?attendance=<token>` se mantiene intacto.
- Empresas existentes quedan en modo `legacy`.
- POS, caja, ventas, inventario y reportes no fueron tocados.
- Auth/login no fueron tocados.

## Flujo operativo

- Primer escaneo: registra entrada.
- Segundo escaneo con almuerzo: muestra opciones de salida a almuerzo o salida final/medio día.
- En almuerzo: permite regreso de almuerzo.
- Después de regreso de almuerzo: solo permite salida final.
- Salida final: cierra jornada.
- Jornada cerrada: bloquea nuevos registros.
- Medio día: cierra como `half_day`.
- Jornada continua: cierra como `continuous_day`.

## Validación SQL

- SQL 028 aplicado manualmente por Gerencia.
- Tablas creadas.
- RLS activo.
- Policies creadas.
- RPCs creadas.
- `authenticated` puede ejecutar RPCs.
- `anon` puede ejecutar `attendance_qr_v2_resolve` y `attendance_qr_v2_record`.
- Backfill legacy creado.
- `token_hash` existe.
- No existe columna `token` plano.

## Validación técnica

- `tsc` OK.
- Build OK.
- Producción responde 200.
- Deploy por push.
- Sin deploy manual.

## Prueba en sitio

- La primera prueba detectó fallas en edad/categoría/link.
- Hotfix `e8047f9` corrigió edad visible, categoría sugerida/final y visualización del link público.
- Prueba enfocada validada por Gerencia.

## Exclusiones

- PIN.
- Geolocalización.
- Selfie.
- QR visual real.
- Rate-limit real.
- Correcciones administrativas avanzadas.
- Configuración por sucursal.
- Exportación avanzada.

## Riesgos residuales

- Endpoint público requiere vigilancia y rate-limit futuro.
- Token en URL puede quedar en historial o logs.
- Link plano solo queda visible al generar/regenerar.
- QR visual real pendiente.
- Timezone fijo `America/Guatemala`.
- Correcciones administrativas futuras pendientes.

## Recomendaciones futuras

- V2.6: correcciones administrativas.
- V2.7: PIN, geolocalización y selfie.
- QR visual local sin servicio externo.
- Rate-limit.
- Auditoría visual.
- Reportes y exportación.
- Configuración por sucursal.

## Estado final

Asistencia V2 queda publicada, validada en sitio, documentada y archivada.
