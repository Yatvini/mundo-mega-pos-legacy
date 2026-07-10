# Mundo Mega POS

Sistema web POS multiempresa de **Grupo Multimarkets S.A.** para ventas, inventario, caja, sucursales, reportes, asistencia y salarios.

El proyecto está construido como una aplicación web React desplegable en Vercel, con Supabase como base de datos, autenticación y backend principal.

## Tecnologías principales

- Frontend: React 18, TypeScript, Vite.
- UI y gráficos: CSS propio, Lucide React, Recharts.
- Backend principal: Supabase PostgreSQL, Supabase Auth, funciones SQL/RPC y Row Level Security.
- API serverless: Vercel Functions en `api/send-invitation-email.js`.
- Gestor de paquetes: pnpm.

## Requisitos

- Node.js 18 o superior.
- pnpm.
- Proyecto Supabase configurado.
- Cuenta de Vercel para despliegue en producción.

## Instalación local

```powershell
pnpm install
Copy-Item .env.example .env
```

Edita `.env` y coloca las variables públicas de Supabase:

```env
VITE_SUPABASE_URL=https://tu-proyecto.supabase.co
VITE_SUPABASE_ANON_KEY=tu-clave-anon-publica
```

## Base de datos

En Supabase, abre el SQL Editor y ejecuta los archivos de la carpeta `supabase/` en orden numérico:

1. `schema.sql`
2. `002_auth_onboarding.sql`
3. `003_confirm_first_admin.sql`
4. `004_runtime_operations.sql`
5. `005_users_and_roles.sql`
6. `006_branches.sql`
7. `007_returns_and_cancellations.sql`
8. `008_branch_control_center.sql`
9. `009_corporate_control_hub.sql`
10. `010_multi_tenant_saas.sql`
11. `011_fix_business_creation.sql`
12. `012_business_admin_and_cash_closure_reports.sql`
13. `013_cash_closure_movement_details.sql`
14. `014_attendance_payroll.sql`
15. `015_attendance_branch_kiosks.sql`
16. `016_attendance_half_shift.sql`
17. `017_restore_previous_attendance.sql`

Cada ejecución correcta debe mostrar algo como `Success. No rows returned`.

## Ejecutar en desarrollo

```powershell
pnpm dev
```

Vite normalmente abre el sistema en:

```text
http://localhost:5173
```

o:

```text
http://127.0.0.1:5173
```

## Compilar para producción

```powershell
pnpm build
```

Este comando ejecuta:

- `tsc -b`
- `vite build`

## Vista previa de producción local

```powershell
pnpm preview
```

## Variables de entorno

Frontend/local:

```env
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
```

Servidor/Vercel:

```env
SUPABASE_SERVICE_ROLE_KEY=
```

Opcional para la API serverless:

```env
SUPABASE_URL=
```

Notas importantes:

- `VITE_SUPABASE_ANON_KEY` es pública y puede usarse en el frontend.
- `SUPABASE_SERVICE_ROLE_KEY` es secreta y solo debe configurarse en Vercel o en un entorno backend seguro.
- Nunca subas `.env` ni claves reales al repositorio.

## Despliegue en Vercel

1. Conecta el repositorio de GitHub a Vercel.
2. Configura las variables de entorno.
3. Usa el comando de build:

```text
pnpm build
```

4. Publica desde la rama `main`.

## Módulos actuales

- Autenticación con Supabase Auth.
- Panel de administración multiempresa.
- Creación, edición, suspensión y eliminación lógica de empresas.
- Invitaciones por correo para empresas y usuarios.
- Roles: administrador, supervisor, cajero y bodega.
- Multiempresa y multisucursal con aislamiento por negocio.
- Resumen de ventas.
- Punto de venta con carrito y medios de pago.
- Productos, inventario, costos, precios y stock mínimo.
- Compras y proveedores.
- Clientes.
- Caja: apertura, movimientos y cierre.
- Reportes.
- Centro corporativo/multisucursal.
- Reportes por sucursal.
- Devoluciones y anulaciones.
- Tickets térmicos y reimpresión.
- Cierres de caja con reporte imprimible.
- Asistencia de empleados por QR.
- Empleados de asistencia, categorías, asistencia y salarios.
- Impresión de asistencia y salarios.

## Pruebas y verificación

Actualmente no hay framework de pruebas automatizadas configurado.

Verificaciones disponibles:

```powershell
pnpm build
```

También puedes ejecutar TypeScript directamente:

```powershell
pnpm exec tsc -b
```

## Problemas conocidos

- No existe suite de pruebas automatizadas todavía.
- El bundle de producción supera 500 kB y Vite muestra una advertencia de tamaño. No bloquea el build.
- Varias pantallas están concentradas en `src/App.tsx`; conviene modularizar cuando el sistema entre a una fase de mantenimiento más formal.
- Algunos textos históricos pueden requerir normalización de acentos/encoding.
- La integración fiscal FEL de Guatemala no está implementada; requiere proveedor/certificador autorizado.

## Siguiente trabajo recomendado

1. Separar `src/App.tsx` en módulos/páginas reutilizables.
2. Agregar pruebas unitarias y de integración.
3. Agregar validación de formularios más robusta.
4. Mejorar control de errores visible para usuarios finales.
5. Definir estrategia final para seguridad de asistencia antes de reintentar geolocalización o QR dinámico.

