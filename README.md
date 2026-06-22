# MUNDO MEGA · Grupo Multimarkets S.A.

Sistema web de punto de venta para minimarket, con panel de indicadores, venta rápida, inventario, compras, clientes, caja y reportes.

## Ejecutar

```powershell
pnpm install
Copy-Item .env.example .env
pnpm dev
```

La interfaz incluye datos de demostración y funciona sin credenciales. Para persistencia real:

1. Crea un proyecto en Supabase.
2. Ejecuta `supabase/schema.sql` en el SQL Editor.
3. Coloca `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` en `.env`.
4. Crea el primer negocio, sucursal y perfil administrativo desde el SQL Editor o un flujo de onboarding.

## Módulos

- Resumen de ventas, transacciones, ticket promedio y alertas.
- POS con búsqueda, categorías, carrito, cliente y múltiples medios de pago.
- Productos, stock mínimo, costos, precios y códigos de barras.
- Compras, proveedores y cuentas pendientes.
- Clientes e historial de consumo.
- Apertura/cierre y movimientos de caja.
- Reportes de ventas, margen y productos más vendidos.
- Esquema multiempresa/multisucursal con RLS y cobro transaccional.

## Nota fiscal

El sistema registra comprobantes internos. La emisión de FEL en Guatemala requiere integrar un certificador autorizado; esa conexión debe configurarse según el proveedor elegido.
