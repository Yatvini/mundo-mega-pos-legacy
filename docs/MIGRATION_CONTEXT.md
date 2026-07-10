# Contexto técnico de migración - Mundo Mega POS

Fecha de revisión: 2026-07-04.

## Objetivo del sistema

Mundo Mega POS es un sistema web de punto de venta multiempresa para Grupo Multimarkets S.A. El objetivo es administrar empresas independientes, sucursales, ventas, inventario, compras, caja, reportes, usuarios, asistencia de empleados y salarios desde una plataforma SaaS.

El sistema debe permitir que cada empresa tenga datos privados e independientes, mientras un administrador general puede supervisar empresas desde un panel multiempresa.

## Arquitectura

Arquitectura actual:

- Aplicación frontend SPA con React, TypeScript y Vite.
- Supabase como backend principal:
  - PostgreSQL.
  - Supabase Auth.
  - Row Level Security.
  - Funciones SQL/RPC.
  - Triggers de onboarding.
- Vercel para despliegue frontend y función serverless.
- API serverless en `api/send-invitation-email.js` para enviar invitaciones con `SUPABASE_SERVICE_ROLE_KEY`.

Flujo general:

1. El usuario entra a la app en Vercel.
2. React carga sesión con Supabase Auth.
3. El frontend consulta tablas y funciones RPC de Supabase.
4. Supabase aplica aislamiento por empresa/sucursal mediante RLS y funciones como `current_business_id()`.
5. Las invitaciones usan una función serverless con service role, no expuesta al navegador.

## Estructura de carpetas

```text
.
├── api/
│   └── send-invitation-email.js
├── docs/
│   └── MIGRATION_CONTEXT.md
├── src/
│   ├── App.tsx
│   ├── main.tsx
│   ├── data.ts
│   ├── types.ts
│   ├── lib/
│   │   ├── api.ts
│   │   ├── receipt.ts
│   │   ├── store.ts
│   │   └── supabase.ts
│   └── *.css
├── supabase/
│   ├── schema.sql
│   ├── 002_auth_onboarding.sql
│   ├── ...
│   └── 017_restore_previous_attendance.sql
├── .env.example
├── .gitignore
├── package.json
├── pnpm-lock.yaml
├── tsconfig*.json
└── vite.config.ts
```

## Tecnologías utilizadas

Frontend:

- React 18.
- TypeScript.
- Vite.
- CSS propio.
- Lucide React para iconos.
- Recharts para gráficos.

Backend/base de datos:

- Supabase PostgreSQL.
- Supabase Auth.
- Row Level Security.
- Funciones PostgreSQL/RPC.
- Triggers.

Infraestructura:

- Vercel.
- GitHub.
- pnpm.

## Frontend

El frontend está principalmente en:

- `src/App.tsx`: contiene la mayor parte de pantallas, navegación y flujos.
- `src/lib/store.ts`: capa de acceso a datos con Supabase.
- `src/lib/supabase.ts`: cliente Supabase del frontend.
- `src/lib/receipt.ts`: impresión de recibos/tickets.
- Archivos CSS en `src/` para estilos por módulo.

Pantallas principales:

- Login/registro/configuración de contraseña.
- Panel multiempresa.
- Resumen.
- Centro de control.
- Punto de venta.
- Productos.
- Compras.
- Clientes.
- Caja.
- Reportes.
- Configuración.
- Asistencia.

## Backend

No hay servidor Node tradicional. El backend real está repartido entre:

- Supabase SQL/RPC/RLS.
- Vercel Function `api/send-invitation-email.js`.

La función serverless usa `SUPABASE_SERVICE_ROLE_KEY` para acciones administrativas de invitación por correo.

## Base de datos

La base de datos está definida por archivos SQL en `supabase/`.

Áreas principales:

- Empresas y sucursales.
- Perfiles y roles.
- Productos, categorías e inventario.
- Clientes y proveedores.
- Caja y movimientos.
- Ventas, pagos e ítems.
- Compras.
- Devoluciones y anulaciones.
- Reportes corporativos.
- Plataforma multiempresa.
- Asistencia, empleados, categorías, QR y salarios.

RLS:

- El sistema usa políticas por `business_id`.
- `current_business_id()` determina el negocio activo del usuario.
- Algunas funciones usan `security definer` para operaciones controladas.

## Autenticación

Autenticación con Supabase Auth:

- Login con correo y contraseña.
- Registro inicial.
- Invitaciones para empresas y miembros.
- Configuración de contraseña vía enlace de Supabase.
- Roles internos en tabla `profiles`.

Roles conocidos:

- `admin`
- `supervisor`
- `cashier`
- `warehouse`

Además existe una capa de administrador de plataforma para el panel multiempresa.

## Módulos existentes

Terminados o funcionales actualmente:

- Autenticación base.
- Multiempresa SaaS.
- Panel de empresas/clientes.
- Invitaciones de empresas y usuarios.
- Usuarios y roles.
- Sucursales.
- Cambio de sucursal.
- Resumen de ventas.
- POS.
- Productos e inventario.
- Compras.
- Clientes.
- Caja.
- Reportes.
- Centro corporativo.
- Matriz por sucursal.
- Devoluciones parciales.
- Anulaciones.
- Tickets térmicos.
- Reimpresión de tickets.
- Cierre de caja.
- Reportes de cierre de caja.
- Asistencia por QR.
- Empleados de asistencia.
- Categorías de asistencia.
- Medio turno.
- Cálculo de salarios según asistencia.
- Impresión de asistencia y salarios.
- Eliminación permanente de empleados de asistencia.
- Eliminación permanente de categorías de asistencia.
- Eliminación de registros de asistencia.

## Módulos incompletos o pendientes

Pendientes técnicos o de producto:

- Pruebas automatizadas.
- Refactorización de `src/App.tsx` en componentes/páginas más pequeñas.
- Seguridad avanzada de asistencia. Se probó una versión con geolocalización, QR rotativo, alertas y marcaje manual, pero fue revertida para restaurar el comportamiento anterior.
- Integración fiscal FEL Guatemala.
- Reportes financieros avanzados.
- Auditoría formal de acciones críticas.
- Exportación a Excel/PDF para todos los reportes.
- Control de permisos más fino por módulo/acción.
- Validación robusta de formularios.
- Manejo centralizado de errores.
- Optimización del bundle.

## Decisiones técnicas tomadas

- Usar Supabase como backend principal para acelerar desarrollo.
- Usar RLS por `business_id` para aislamiento multiempresa.
- Mantener service role únicamente en Vercel/serverless.
- Mantener `VITE_SUPABASE_ANON_KEY` en frontend porque es la clave pública de Supabase.
- Implementar invitaciones desde API serverless para no exponer claves privadas.
- Restaurar asistencia al modo anterior después de problemas con la seguridad avanzada.
- Mantener las migraciones SQL como historial incremental manual ejecutable desde Supabase SQL Editor.
- No eliminar funcionalidades existentes durante esta revisión.

## Comandos de instalación

```powershell
pnpm install
Copy-Item .env.example .env
```

## Comandos de desarrollo

```powershell
pnpm dev
```

URL local habitual:

```text
http://localhost:5173
```

## Comandos de compilación

```powershell
pnpm build
```

También se puede ejecutar TypeScript directamente:

```powershell
pnpm exec tsc -b
```

## Comandos de pruebas

Actualmente no hay pruebas automatizadas configuradas.

Comando de verificación disponible:

```powershell
pnpm build
```

Recomendación:

- Agregar Vitest para pruebas unitarias.
- Agregar Playwright para pruebas end-to-end del POS, caja y asistencia.

## Variables de entorno necesarias

Frontend:

```env
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
```

Backend/Vercel Function:

```env
SUPABASE_SERVICE_ROLE_KEY=
```

Opcional:

```env
SUPABASE_URL=
```

Reglas:

- No subir `.env`.
- No usar `SUPABASE_SERVICE_ROLE_KEY` en el frontend.
- Configurar `SUPABASE_SERVICE_ROLE_KEY` solo en Vercel o backend seguro.

## Verificación realizada

En esta revisión:

- Se inspeccionó la estructura del proyecto.
- Se identificaron tecnologías y módulos principales.
- Se ejecutó TypeScript:

```powershell
tsc -b
```

Resultado: correcto.

- Se ejecutó build de producción:

```powershell
vite build --config vite.config.ts
```

Resultado: correcto.

Advertencia:

- Vite reporta que el bundle principal supera 500 kB. No rompe la compilación.

## Problemas conocidos

- No hay pruebas automatizadas.
- El archivo `src/App.tsx` concentra demasiadas responsabilidades.
- Hay textos con problemas históricos de encoding en algunas cadenas visibles.
- La seguridad avanzada de asistencia fue revertida; si se retoma, debe hacerse en una rama separada y con pruebas.
- El despliegue depende de que las migraciones SQL se hayan ejecutado correctamente en Supabase.
- `dist/`, logs y archivos de build no deben versionarse.

## Siguiente trabajo recomendado

1. Confirmar en producción que asistencia, QR y marcajes históricos cargan correctamente.
2. Crear una rama para refactorizar `src/App.tsx` sin cambiar comportamiento.
3. Agregar pruebas básicas:
   - render de login;
   - carga de tienda;
   - flujo POS;
   - apertura/cierre de caja;
   - asistencia QR.
4. Documentar un checklist de despliegue Supabase + Vercel.
5. Retomar seguridad avanzada de asistencia solo después de separar y probar el módulo actual.
6. Evaluar code splitting para reducir el tamaño del bundle.

