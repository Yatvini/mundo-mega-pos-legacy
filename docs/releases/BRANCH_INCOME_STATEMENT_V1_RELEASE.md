# Estado de Resultados por Sucursal V1 - Release

## 1. Nombre de la funcion

Estado de Resultados automatico por sucursal - V1.

## 2. Fecha de publicacion

2026-07-28.

## 3. Rama usada

`legacy/production-snapshot`.

## 4. Commit publicado

`f816d6b feat(reports): add branch income statement`.

## 5. Archivos modificados

- `src/App.tsx`
- `src/lib/store.ts`
- `supabase/024_branch_income_statement.sql`

## 6. Migracion SQL aplicada

`supabase/024_branch_income_statement.sql`

La migracion fue aplicada manualmente en Supabase antes de publicar el frontend.

## 7. RPC creada

`public.branch_income_statements(p_from timestamptz, p_to timestamptz, p_branch_id uuid default null)`

La RPC es de solo lectura, usa `security definer`, fija `search_path=public` y tiene permiso `EXECUTE` para `authenticated`.

## 8. Roles autorizados

- `admin`: puede consultar todas las sucursales de su empresa o filtrar una sucursal.
- `supervisor`: puede consultar solo su sucursal asignada.

## 9. Roles denegados

- `cashier`
- `warehouse`
- platform admin sin perfil de empresa autorizado
- cualquier rol no autorizado por la RPC

## 10. Metricas incluidas

- Ventas brutas
- Devoluciones
- Anulaciones
- Ventas netas
- Costo de ventas
- Utilidad bruta
- Gastos operativos
- Salarios estimados
- Diferencias negativas de caja
- Diferencias positivas de caja
- Utilidad operativa
- Margen bruto
- Margen operativo
- Ticket promedio
- Cantidad de ventas
- Productos vendidos
- Indicador de fallback de costo
- Notas del reporte

## 11. Decisiones financieras aplicadas

- Las ventas brutas consideran solo ventas completadas.
- Las devoluciones se restan de ventas brutas.
- Las anulaciones se muestran como referencia y no se restan de ventas netas.
- Las ventas netas se calculan como `gross_sales - returns_total`.
- La utilidad bruta se calcula como `net_sales - cost_of_sales`.
- La utilidad operativa se calcula como utilidad bruta menos gastos operativos, salarios estimados y faltantes de caja, mas sobrantes de caja.
- Los margenes se protegen contra division por cero.

## 12. Limitaciones conocidas

- Los gastos operativos se mantienen en `0` en esta V1.
- La nomina es estimada con base en salarios activos y prorrateo simple.
- Las anulaciones son informativas y no reducen ventas netas.
- El fallback de costo aplica solo si falta `sale_items.unit_cost`.

## 13. Resultado de pruebas

Gerencia confirmo que las pruebas funcionales en produccion fueron satisfactorias.

Validaciones tecnicas realizadas:

- TypeScript sin errores.
- Build de produccion exitoso.
- Publicacion en Netlify confirmada por cambio de asset JS.
- RPC y permiso `EXECUTE` confirmados previamente en Supabase.

## 14. Riesgos residuales

- Los gastos operativos aun no reflejan egresos contables reales.
- La nomina estimada no sustituye una nomina contable definitiva.
- El reporte depende de que las ventas, devoluciones, anulaciones, cajas y salarios esten registrados correctamente.
- La V1 no incluye exportacion PDF/Excel.

## 15. Recomendaciones para V2

- Agregar catalogo de gastos operativos por sucursal.
- Separar nomina estimada de nomina contable cerrada.
- Agregar exportacion PDF/Excel controlada.
- Agregar comparativos por periodo anterior.
- Agregar auditoria o bitacora de consultas financieras si Gerencia lo requiere.
- Agregar pruebas automatizadas para calculos financieros criticos.

## 16. Estado final

Publicado y funcionando en produccion legacy.
