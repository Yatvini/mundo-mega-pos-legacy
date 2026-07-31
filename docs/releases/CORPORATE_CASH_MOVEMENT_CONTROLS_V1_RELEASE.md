# Control de caja corporativo V1 - Cierre de produccion

## 1. Nombre de la funcion

Control de caja corporativo V1.

## 2. Fecha de publicacion

31 de julio de 2026.

## 3. Rama usada

`legacy/production-snapshot`

## 4. Commit publicado

`a06a51a feat(cash): add corporate cash movement controls`

## 5. Archivos modificados

- `src/App.tsx`
- `src/lib/store.ts`
- `supabase/025_corporate_cash_movement_controls.sql`

## 6. Migracion SQL aplicada

`supabase/025_corporate_cash_movement_controls.sql`

## 7. Campos agregados a cash_movements

- `status`
- `voided_at`
- `voided_by`
- `void_reason`
- `updated_by`
- `updated_at`
- `correction_reason`

## 8. Tabla de auditoria creada

`cash_movement_audit_logs`

## 9. RPC creadas

- `corporate_cash_movements`
- `corporate_update_cash_movement`
- `corporate_void_cash_movement`

## 10. Reportes ajustados

- `cash_closure_reports`
- `cash_closure_movement_details`
- `control_center_movements`
- `loadCash`

Los calculos financieros consideran solo movimientos activos.

## 11. Roles autorizados

- `admin`: puede ver, editar y anular movimientos manuales permitidos desde el Centro Corporativo.

## 12. Roles denegados

- `supervisor`
- `cashier`
- `warehouse`
- `platform admin` sin perfil financiero de empresa

## 13. Reglas financieras

- No hay borrado fisico de movimientos.
- La anulacion es logica mediante `status = 'voided'`.
- Toda edicion o anulacion requiere motivo obligatorio.
- Toda edicion o anulacion registra auditoria obligatoria.
- Solo se corrigen movimientos de cajas abiertas.
- Las cajas cerradas son solo lectura en V1.
- Solo aplican movimientos manuales de `cash_movements`.
- No se editan ventas POS.
- No se editan pagos POS.
- No se editan devoluciones.
- No se editan anulaciones de venta.
- No se modifica inventario.

## 14. Resultado de pruebas

Gerencia confirmo que la funcion fue publicada y funciona correctamente en produccion.

Validaciones tecnicas previas:

- TypeScript paso correctamente.
- Build de Vite paso correctamente.
- SQL 025 fue aplicado manualmente en Supabase.
- RPCs y permisos `EXECUTE` fueron confirmados.
- Produccion quedo publicada en Netlify.

## 15. Riesgos residuales

- La correccion se limita a cajas abiertas; no resuelve ajustes historicos de cajas cerradas.
- La auditoria queda consultable desde base/RPC, pero no cuenta con exportacion dedicada en V1.
- Si se habilitan correcciones de cierres historicos en el futuro, sera necesaria una politica contable adicional.

## 16. Limitaciones V1

- No edita cajas cerradas.
- No permite que supervisor corrija movimientos.
- No hay correccion historica de cierres.
- No hay exportacion especifica de auditoria.
- No hay adjuntos ni comprobantes.

## 17. Recomendaciones para V2

- Agregar vista detallada de auditoria por movimiento.
- Evaluar exportacion PDF/Excel de auditoria.
- Definir flujo contable para correcciones historicas de cajas cerradas.
- Evaluar permisos avanzados por sucursal para supervisor, si Gerencia lo aprueba.
- Agregar adjuntos o comprobantes para correcciones sensibles.

## 18. Estado final

Publicado y funcionando.

URL de produccion:

`https://mundo-mega-pos-legacy.netlify.app/`
