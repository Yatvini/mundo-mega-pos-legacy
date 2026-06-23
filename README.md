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

## Correos de invitacion

El sistema envia invitaciones automaticas para nuevas empresas y usuarios usando Supabase Auth desde una API segura en Vercel.

En Vercel agrega estas variables:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

La `SUPABASE_SERVICE_ROLE_KEY` se encuentra en Supabase: Project Settings -> API -> service_role key. Debe quedar solo en Vercel como variable privada; no debe pegarse en el frontend ni subirse al repositorio.

Cuando el invitado abre el correo, el sistema le pedira crear su contrasena y luego entrara a su empresa o sucursal asignada.

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
