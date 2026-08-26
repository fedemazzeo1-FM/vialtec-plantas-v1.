# modules-status.md — Estado de módulos

Listado de módulos identificados a partir del relevamiento del sistema anterior.
Todos arrancan en **PENDIENTE** hasta que se implementen sobre `plantas_*`.

| # | Módulo | Descripción breve | Estado |
|---|--------|--------------------|--------|
| 1 | Dashboard | KPIs del mes, analítica de proveedores, despacho por camión | EN CURSO — service + `DashboardView` listos (KPIs dobles tn/m³, comparativa de proveedores por período, detalle por camión con remito garantizado); falta aplicar migración SQL 05; alertas de stock 🔴/🟡 originales del sistema legado no están implementadas todavía (dependen del módulo Stock) |
| 2 | Pedidos | ABM de pedidos, ciclo solicitado→confirmado→despachado | EN CURSO — service + `PedidosView` (filtros, alta, confirmar/despachar/cancelar) listos; falta aplicar migración SQL de `plantas_pedidos` (pendiente de confirmación) |
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
