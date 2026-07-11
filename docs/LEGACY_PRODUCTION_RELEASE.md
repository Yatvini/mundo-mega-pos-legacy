# Mundo Mega POS Legacy - Cierre tecnico de produccion

## Estado

Mundo Mega POS Legacy queda marcado como:

**Produccion legacy operativa**

Esta version queda disponible para operacion diaria temporal mientras el sistema nuevo continua su evolucion.

## Accesos y referencias

- URL de produccion: https://mundo-mega-pos-legacy.netlify.app
- Repositorio: https://github.com/Yatvini/mundo-mega-pos-legacy.git
- Rama de produccion legacy: `legacy/production-snapshot`
- Proyecto Supabase: `mundo-mega-pos-legacy-prod`

## Modulos validados

- Login
- Empresa/Sucursal
- Productos
- Inventario
- Caja
- POS/Ventas
- Devolucion/anulacion
- Cierre de caja

## Variables de entorno usadas en Netlify

Variables publicas requeridas:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

## Variables prohibidas

No configurar ni exponer estas variables en frontend, Netlify ni archivos versionados:

- `SUPABASE_SERVICE_ROLE_KEY`
- `DATABASE_PASSWORD`
- `SUPABASE_ACCESS_TOKEN`
- `JWT_SECRET`

## Incidencia pendiente no bloqueante

El Centro corporativo / `branch_control_report_v2` mantiene una incidencia pendiente.

Esta incidencia no bloquea la operacion basica validada del sistema legacy:

- login;
- carga de empresa y sucursal;
- productos;
- inventario;
- caja;
- POS/ventas;
- devoluciones/anulaciones;
- cierre de caja.

## Reglas de operacion

- No usar service role en frontend.
- No compartir claves privadas.
- Probar cambios primero localmente.
- Hacer commit antes de deploy.
- No usar datos reales para pruebas destructivas.
- Mantener datos `TEST` separados de la operacion real.

## Checklist final

- Build pasa.
- Netlify deploy publicado.
- Supabase Auth URL configurado.
- Login validado.
- Operacion basica validada.
