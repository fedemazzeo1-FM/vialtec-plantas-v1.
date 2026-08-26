# modules-status.md — Estado de módulos

Listado de módulos identificados a partir del relevamiento del sistema anterior.
Todos arrancan en **PENDIENTE** hasta que se implementen sobre `plantas_*`.

| # | Módulo | Descripción breve | Estado |
|---|--------|--------------------|--------|
| 1 | Dashboard | Pedidos confirmados de la semana + alertas de stock (🔴/🟡) | PENDIENTE |
| 2 | Pedidos | ABM de pedidos, ciclo solicitado→confirmado→despachado | PENDIENTE |
| 3 | Plan semanal | Vista de pedidos confirmados/despachados agrupados por día | PENDIENTE |
| 4 | Stock | Stock por material en kg, ingresos/salidas manuales, guardas | PENDIENTE |
| 5 | Despachos | Historial de pedidos despachados, filtros, exportación Excel | PENDIENTE |
| 6 | Báscula / Balanza | Slots de pesaje, vales de asfalto, ingreso/egreso de áridos | PENDIENTE |
| 7 | Fórmulas | Composición de mezclas (asfalto/hormigón), conversión a kg | EN CURSO — service + `FormulasView` con edición inline de insumos listos, scaffold Vite listo; falta `npm install` y aplicar la migración SQL de `plantas_formulas` (pendiente de confirmación) |
| 8 | Maestros | Obras, encargados, proveedores, patentes, choferes, materiales | EN CURSO — service + `MaestrosView` (tabs) listos, scaffold Vite listo; falta `npm install` y aplicar la migración SQL de `plantas_encargados/proveedores/patentes/choferes` (pendiente de confirmación) |
| 9 | Usuarios | ABM de usuarios, mapeo con Supabase Auth y roles | PENDIENTE |
| 10 | Roles | Configuración de permisos por rol (override sobre defaults) | PENDIENTE |
| 11 | Backup | Backups automáticos/manuales y restauración | PENDIENTE |
| 12 | Resumen mensual / Reportes | Excel mensual de producción por obra e insumos | PENDIENTE |
| 13 | Migración de historial | Migrar datos del sistema anterior a `plantas_*` | PENDIENTE |

Actualizar el estado de cada fila a medida que se avanza (PENDIENTE → EN CURSO →
LISTO), no borrar filas.
