# modules-status.md — Estado de módulos

Listado de módulos identificados a partir del relevamiento del sistema anterior.
Todos arrancan en **PENDIENTE** hasta que se implementen sobre `plantas_*`.

| # | Módulo | Descripción breve | Estado |
|---|--------|--------------------|--------|
| 1 | Dashboard | KPIs del mes, analítica de proveedores, despacho por camión | EN CURSO — service + `DashboardView` listos (KPIs dobles tn/m³, comparativa de proveedores por período, detalle por camión con remito garantizado); falta aplicar migración SQL 05; alertas de stock 🔴/🟡 originales del sistema legado no están implementadas todavía (dependen del módulo Stock) |
| 2 | Pedidos | ABM de pedidos, ciclo solicitado→confirmado→despachado | EN CURSO — service + `PedidosView` (filtros, alta, confirmar/despachar/cancelar, y "Registrar carga" para hormigón con remito) listos; falta aplicar migraciones SQL 02 y 05 (pendiente de confirmación) |
| 3 | Plan semanal | Vista de pedidos confirmados/despachados agrupados por día | EN CURSO — service + `PlanSemanalView` (matriz lunes-domingo, KPIs tn/m³ por obra y total) listos; falta aplicar migración SQL |
| 4 | Stock | Stock por material en kg, ingresos/salidas manuales, guardas | PENDIENTE |
| 5 | Despachos | Historial de pedidos despachados, filtros, exportación Excel | PENDIENTE |
| 6 | Báscula / Balanza | Slots de pesaje, vales de asfalto, ingreso/egreso de áridos | EN CURSO — service + `BasculaView` (slots paralelos, doble impresión vale/remito) listos; ingreso de áridos ya captura material/proveedor/remito y escribe en `plantas_ingresos` (migración 05); falta aplicar migraciones SQL 04 y 05; descuento de stock al pesar sigue siendo un TODO hasta que exista el módulo Stock |
| 7 | Fórmulas | Composición de mezclas (asfalto/hormigón), conversión a kg | EN CURSO — service + `FormulasView` con edición inline de insumos listos, scaffold Vite listo; falta `npm install` y aplicar la migración SQL de `plantas_formulas` (pendiente de confirmación) |
| 8 | Maestros | Obras, encargados, proveedores, patentes, choferes, materiales | EN CURSO — service + `MaestrosView` (tabs) listos, scaffold Vite listo; falta `npm install` y aplicar la migración SQL de `plantas_encargados/proveedores/patentes/choferes` (pendiente de confirmación) |
| 9 | Usuarios | ABM de usuarios, mapeo con Supabase Auth y roles | PENDIENTE |
| 10 | Roles | Configuración de permisos por rol (override sobre defaults) | PENDIENTE |
| 11 | Backup | Backups automáticos/manuales y restauración | PENDIENTE |
| 12 | Resumen mensual / Reportes | Excel mensual de producción por obra e insumos | PENDIENTE |
| 13 | Migración de historial | Migrar datos del sistema anterior a `plantas_*` | PENDIENTE |

Actualizar el estado de cada fila a medida que se avanza (PENDIENTE → EN CURSO →
LISTO), no borrar filas.

## Fase 1 de mejoras (auth + RPC atómicas + paginación UI) — APLICADO en Supabase

Estado real verificado en la base (2026-08-27): **01, 02, 04, 05 ya estaban
aplicadas** en Supabase desde antes de esta fase (por fuera de este chat, sin
quedar registradas en `list_migrations` — se aplicaron con SQL directo, no
con la herramienta de migraciones). **06, 07 y 08 se aplicaron en esta
sesión** vía `apply_migration` (sí quedan trackeadas). Verificado después de
aplicar: `plantas_usuarios_roles` existe, el admin
(`federico.mazzeo@vialtec.com.ar`) está cargado y activo,
`registrar_pesada_bascula`/`registrar_carga_hormigon` existen, `postergado`
está en el CHECK de `plantas_pedidos.estado`, y las 10 tablas `plantas_*`
(+`plantas_pedidos_historial`) tienen policies de RLS.

Código (build verificado con `npm run build`):

- **Auth real**: `auth.store.js` (login/logout/restaurar sesión vía Supabase
  Auth), guards de router por rol (`router/index.js`), gate de sesión en
  `App.vue`, `LoginView.vue` nueva, sidebar filtrado por permisos en
  `DesktopLayout.vue`. Rol se resuelve contra `plantas_usuarios_roles` (tabla
  nueva, migración 07) — NO contra `flota_roles` (drift real detectado, ver
  `pending.md`).
- **RPC atómicas**: `registrar_pesada_bascula` y `registrar_carga_hormigon`
  (migración 07) reemplazan el flujo multi-paso de
  `bascula.service.js#registrarPesada` y
  `pedidos.service.js#registrarCargaHormigon` — arreglan la race condition de
  slots paralelos pesando el mismo pedido (lock de fila server-side).
- **PedidosView**: soporta `tipo_pedido` (obra/venta), `cliente_externo`,
  `encargado`, filtro + acción de archivado.
- **Paginación server-side de UI**: `fetchPagina()` nuevo en
  `fetch-paginado.js`, usado por `fetchPedidos()` y `fetchHistorialVales()`
  (devuelven `{ filas, total }`, ya no un array plano). `VTable.vue` soporta
  footer de paginación opcional (`page`/`page-size`/`total`). Fuera de
  alcance a propósito: `fetchDetalleDespachosCamion` (Dashboard) y
  `fetchAnaliticaProveedores` siguen con `fetchPaginado()` (traen todo — son
  agregaciones, no listados de UI).

**08 (RLS mínima)**: `for all to authenticated using (true)` en las 9 tablas
de negocio (cualquier usuario autenticado del proyecto Supabase compartido
—incluye usuarios de flota sin rol en `plantas_usuarios_roles`— puede
leer/escribir), y `plantas_pedidos_historial` con select+insert únicamente
(append-only por regla de negocio). Esto es deliberadamente amplio —
confirmado por Federico como suficiente para desbloquear la app ahora; la
restricción fina por rol/obra queda para la tarea dedicada **P0.2** (todavía
PENDIENTE).

Falta antes de considerar esto terminado:
1. Cargar `plantas_usuarios_roles` para cada usuario real más allá del admin
   (Federico es el único con fila hoy).
2. Tarea P0.2: RLS fina por rol/obra (reemplazar los `using (true)` de la
   migración 08).
3. **Pregunta abierta sin resolver**: Federico mencionó que el sistema viejo
   vive en tablas `vt_f9`/`vt_s9`/`vt_maestros9` en esta misma base — se
   verificó contra el schema real (`information_schema.tables`, todos los
   schemas) y **esas tablas no existen** en `ejitztewkpnmrckwmvny`. No se
   escribió esto en `architecture.md` porque no se pudo confirmar. Falta que
   Federico aclare dónde vive realmente el histórico del sistema legado antes
   de retomar la tarea de migración de historial (ver `pending.md`).
