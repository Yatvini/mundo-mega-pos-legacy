# Asistencia QR personalizado - Unificacion, eliminacion segura y eliminacion forzada

## Estado final

Publicado, validado en produccion y listo para archivo.

## Objetivo de la mejora

Esta entrega consolida la experiencia operativa de asistencia bajo el nombre visible **Asistencia QR personalizado**, unificando el flujo de QR V2 con los movimientos configurables de Asistencia V3.

El objetivo fue ocultar la complejidad tecnica V2/V3 para el uso diario, mantener compatibilidad con los modulos existentes y agregar controles de eliminacion permanente segura y eliminacion forzada con auditoria previa.

## Alcance funcional

- Empleados QR dentro de Asistencia QR personalizado.
- Movimientos configurables dentro del mismo flujo operativo.
- Lector QR disponible en la misma seccion.
- Reporte operativo dentro de la seccion unificada.
- Eliminacion permanente segura con bloqueo cuando existe historial.
- Eliminacion permanente forzada para casos autorizados por administracion.
- Doble confirmacion visual antes de acciones destructivas.
- Auditoria previa a la eliminacion forzada.

## Mapa visual

```text
Asistencia
|-- Resumen
|-- Asistencia QR personalizado
|   |-- Empleados QR
|   |-- Movimientos
|   |-- Lector
|   `-- Reporte
|-- QR legacy
|-- Reporte anterior
`-- Salarios
```

## Decisiones gerenciales

- El nombre visible aprobado para operacion diaria es **Asistencia QR personalizado**.
- QR V2 deja de aparecer como tab principal.
- QR V2 se conserva internamente para compatibilidad con empleados QR existentes.
- Asistencia V3 se conserva internamente para movimientos configurables y lector.
- La eliminacion segura bloquea registros con historial.
- La eliminacion forzada permite borrar historial relacionado cuando Gerencia acepta el impacto.
- Las acciones destructivas quedan restringidas a flujos controlados y auditados.

## Arquitectura tecnica

### Reuso de V2

La entrega conserva la base operativa de empleados QR V2 para mantener continuidad con datos y flujos ya usados en produccion.

### Aporte de V3

Asistencia V3 aporta movimientos configurables por empresa, lector operativo y reporte asociado, manteniendo separacion logica respecto a asistencia legacy y QR legacy.

### SQL 039

`supabase/039_attendance_qr_personalizado_safe_delete.sql` agrega eliminacion permanente segura para movimientos y personas QR, bloqueando la eliminacion cuando hay historial asociado.

### SQL 040

`supabase/040_attendance_qr_personalizado_force_delete.sql` agrega eliminacion permanente forzada con borrado explicito de historial relacionado, auditoria previa, filtros por `business_id` y control transaccional.

### Netlify Function, store y UI

La UI expone controles de eliminacion permanente y forzada. El frontend no ejecuta `DELETE` directo: solicita acciones controladas al backend, y el backend delega en RPCs con validaciones de seguridad y auditoria.

## SQL 039 - Eliminacion segura

- Crea tabla de auditoria para registrar intentos/acciones de eliminacion.
- Crea RPCs de eliminacion segura.
- Bloquea eliminacion si existen registros historicos.
- Usa `FOR UPDATE` para reducir carreras de concurrencia.
- No concede permisos a `anon`.
- Mantiene permisos controlados para `authenticated` y `service_role` segun el contrato aprobado.
- Mantiene funciones con `security definer`.
- Mantiene `set search_path=public`.

## SQL 040 - Eliminacion forzada

- Crea nuevas RPCs de eliminacion forzada.
- No reemplaza el comportamiento seguro de SQL 039; lo complementa para casos autorizados.
- Elimina historial relacionado de forma explicita.
- Registra auditoria antes de eliminar.
- Marca metadata con `forced=true`.
- Registra conteos por tabla cuando aplica.
- Usa `FOR UPDATE`.
- Filtra por `business_id` para evitar cruce multiempresa.
- No concede permisos a `anon`.

## Orden de eliminacion

### Movimiento

```text
attendance_events_v3
attendance_movement_types_v3
```

### Persona QR

```text
attendance_events_v3
attendance_events_v2
attendance_daily_records_v2
attendance_qr_tokens_v2
attendance_people_v2
```

## Seguridad y auditoria

- No existe eliminacion directa desde el frontend.
- No existe eliminacion directa desde Netlify Function.
- Toda eliminacion pasa por RPC.
- La eliminacion forzada registra auditoria previa.
- `business_id` es obligatorio en las operaciones sensibles.
- Las RPC filtran por empresa para evitar cruce multiempresa.
- La eliminacion no depende de cascadas como mecanismo principal.
- No se exponen secretos ni tokens en respuestas visibles.

## Riesgos aceptados

- La eliminacion forzada es irreversible.
- La eliminacion forzada puede borrar historial operativo relacionado.
- Los reportes de asistencia pueden cambiar al eliminar historial.
- El impacto en calculos salariales debe revisarse antes de usar eliminacion forzada sobre empleados con registros reales.
- Debe usarse con criterio administrativo y solo cuando Gerencia acepte la perdida de historial.

## Validacion realizada

- Asistencia carga correctamente.
- Tabs principales visibles.
- Botones de eliminacion visibles segun corresponde.
- Doble confirmacion disponible.
- Movimiento sin historial eliminado correctamente.
- Movimiento con historial eliminado mediante flujo forzado.
- Persona QR sin historial eliminada correctamente.
- Persona QR con historial eliminada mediante flujo forzado.
- Compatibilidad con QR legacy, reporte anterior y salarios intacta.
- Console sin errores rojos criticos durante la validacion reportada.

## Commits incluidos

- `50078c9 refactor(attendance): unify qr attendance flow`
- `541d98f feat(attendance): add safe permanent delete controls`
- `b2d1c49 feat(attendance): add forced permanent delete controls`

## Archivos modificados o creados

- `src/App.tsx`
- `src/lib/store.ts`
- `netlify/functions/attendance-v3.js`
- `supabase/039_attendance_qr_personalizado_safe_delete.sql`
- `supabase/040_attendance_qr_personalizado_force_delete.sql`

## Estado de publicacion

- Rama de produccion: `legacy/production-snapshot`
- Commit final publicado: `b2d1c49 feat(attendance): add forced permanent delete controls`
- URL de produccion: `https://mundo-mega-pos-legacy.netlify.app/`
- Asset validado: `assets/index-ekJEJ7Fn.js`
- Deploy automatico por Netlify confirmado en el flujo de produccion.

## Reglas futuras de operacion

- Preferir **Inactivar** cuando se necesite preservar historial.
- Usar **Eliminar permanentemente** solo cuando Gerencia acepte la perdida de historial.
- No eliminar empleados reales sin revision administrativa previa.
- No reaplicar SQL 039 ni SQL 040 si ya fueron aplicados en produccion.
- Toda nueva eliminacion destructiva debe conservar auditoria previa.

## Recomendaciones futuras

- Agregar modal reforzado que exija escribir `ELIMINAR`.
- Guardar snapshot completo de filas eliminadas antes de acciones forzadas.
- Crear panel de auditoria de eliminaciones.
- Separar `App.tsx` en componentes especializados de asistencia.
- Revisar impacto salarial de eliminaciones antes de ampliar el uso operativo.

## Cierre

Asistencia QR personalizado - Unificacion, eliminacion segura y eliminacion forzada queda publicado, validado en produccion y listo para archivo tecnico.
