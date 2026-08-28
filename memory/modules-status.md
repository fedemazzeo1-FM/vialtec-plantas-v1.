# modules-status.md — Estado de módulos

Listado de módulos identificados a partir del relevamiento del sistema anterior.
Todos arrancan en **PENDIENTE** hasta que se implementen sobre `plantas_*`.

| # | Módulo | Descripción breve | Estado |
|---|--------|--------------------|--------|
| 1 | Dashboard | KPIs del mes, analítica de proveedores, despacho por camión | EN CURSO — service + `DashboardView` listos (KPIs dobles tn/m³, comparativa de proveedores por período, detalle por camión con remito garantizado); falta aplicar migración SQL 05; alertas de stock 🔴/🟡 originales del sistema legado no están implementadas todavía (dependen del módulo Stock) |
| 2 | Pedidos | ABM de pedidos, ciclo solicitado→confirmado→despachado | EN CURSO — service + `PedidosView` (filtros, alta con ubicación, confirmar/cancelar, "Registrar carga" hormigón, y despacho de asfalto multi-camión con vale por carga vía `useDespachoAsfalto`) listos; lógica movida a composables (`usePedidos`/`useDespachoAsfalto`/`useCargaHormigon`, 2026-08-28) |
| 3 | Plan semanal | Vista de pedidos confirmados/despachados agrupados por día | EN CURSO — service + `PlanSemanalView` (matriz lunes-domingo, KPIs tn/m³ por obra y total) listos; falta aplicar migración SQL |
| 4 | Stock | Stock por material en kg, ingresos/salidas manuales, guardas | PENDIENTE |
| 5 | Despachos | Historial de pedidos despachados, filtros, exportación Excel | PENDIENTE |
| 6 | Báscula / Balanza | Puertas de pesaje, vales de asfalto, ingreso/egreso de áridos | EN CURSO — **fidelidad funcional con el legado cerrada (2026-08-28, Fase 1+2 sobre el relevamiento Etapa 3)**: ver detalle abajo. Descuento de stock al pesar sigue siendo un TODO hasta que exista el módulo Stock |
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

## Fase 2 de mejoras (paridad funcional Pedidos/Báscula + composables) — APLICADO en Supabase (2026-08-28)

Primer lote de ajustes funcionales del relevamiento (`memory/relevamiento-sistema-viejo.md`,
gaps #4/#5/#6/#7), aprobado por Federico. **Migración 09
(`supabase/migrations/09_ubicacion_temperatura_egreso_multicarga.sql`)
aplicada y verificada contra el schema real**:

- `plantas_pedidos.ubicacion` (texto libre, opcional).
- `plantas_vales.temperatura` (°C, opcional, asfalto) y `plantas_vales.material`/`destino`
  (para `tipo_vale='egreso_arido'`, nuevo valor agregado al CHECK).
- Tabla nueva `plantas_cargas_asfalto` + RPC `registrar_carga_asfalto` (atómica,
  mismo patrón de lock de fila que `registrar_carga_hormigon`): despacho de
  asfalto multi-camión con N° de vale obligatorio por carga, disponible desde
  el modal "Registrar despacho" de Pedidos (ya no solo desde Báscula). El
  `despacharPedido(id, cantidad)` genérico que existía se **eliminó** —
  ya no hay un tercer camino que pise `cantidad_despachada`/`estado` a mano.
- `registrar_pesada_bascula` extendida con `p_temperatura`/`p_destino` (misma
  firma + 2 parámetros opcionales al final; se dropeó la firma vieja antes de
  recrear para evitar overload ambiguo).

Decisión operativa confirmada por Federico (sin cambio de schema):
`fetchPedidosAsfaltoConSaldo()` (filtraba por saldo pendiente) se **eliminó**
y se reemplazó por `fetchPedidosAsfaltoParaPesada()` — el selector de
pedidos de Báscula ya no filtra por saldo, calza con el comportamiento del
legado (permite pesar contra un pedido `despachado`).

**Arquitectura (principio confirmado por Federico para todo el refactor: UX
idéntica al legado, código 100% moderno)**: Pedidos y Báscula quedaron con
la lógica de negocio movida a composables — las vistas (`PedidosView.vue`,
`BasculaView.vue`) son template puro:
- `src/modules/bascula/composables/useBascula.js`
- `src/modules/pedidos/composables/usePedidos.js`
- `src/modules/pedidos/composables/useDespachoAsfalto.js` (nuevo, multi-carga)
- `src/modules/pedidos/composables/useCargaHormigon.js` (extraído, ya existía inline)

Nota de implementación para el próximo composable que agrupe estado bajo un
prefijo (ej. `despacho.error`, `despacho.abierto`): el composable tiene que
devolver `reactive({...})`, no un objeto plano — un objeto plano con refs
adentro NO se auto-desenvuelve en el template (`despacho.error` daría el Ref
crudo, no su valor). `useBascula`/`usePedidos` no tienen este problema porque
sus vistas desestructuran el retorno en bindings top-level de `<script
setup>` (ahí sí aplica el auto-unwrap nativo de Vue).

Build verificado (`npm run build`) y humo visual en el navegador (campo
Ubicación en "Nuevo pedido", tabs "Salida asfalto"/"Ingreso árido"/"Egreso
árido" + temperatura en Báscula, columna "Dif. s/remito" en el historial) —
sin submit real contra producción para no consumir un número de vale real
con datos de prueba.

Falta antes de considerar esto terminado:
1. Probar el flujo completo con datos reales (`plantas_formulas` está vacía
   hoy — no se pudo crear un pedido de punta a punta en el smoke test).
2. Decisión pendiente de Federico: botón "Eliminar" en vales/despachos — se
   mantiene la regla de `business-rules.md` (nunca se eliminan), no se agregó.
3. Extender el mismo patrón de composables al resto de las vistas
   (Dashboard, Fórmulas, Maestros, Plan Semanal) — quedaron fuera de esta
   tanda a propósito, no se tocó código que no estuviera relacionado con los
   gaps aprobados.

## Báscula — Fase 1 + Fase 2 de fidelidad funcional — CERRADA (2026-08-28)

Metodología "un módulo a la vez" (regla fijada por Federico esta sesión):
se auditó Báscula línea por línea contra `Logica sis. plantas v1.rtf`/`v2.rtf`,
`business-rules.md` y `memory/relevamiento-sistema-viejo.md` Etapa 3, se
listaron los gaps, Federico aprobó, y se implementó completo. Migración
`supabase/migrations/10_bascula_acumulado_remito_duplicado_egreso_obra.sql`
aplicada y verificada.

**Fase 1 (impresión + auto-print + acumulado + validación + header):**
- `ValeImprimible.vue`: formato A4 landscape con **dos copias por página**
  (planta/chofer, `print:grid-cols-2`) para modo `vale`; N° formateado a 8
  dígitos (`formatearNumeroVale()`); logo VIAL-TEC S.A. reproducido en
  CSS/texto (no se pudo extraer el archivo de imagen que pegó Federico en el
  chat — no hay herramienta para bajarlo a disco; si se quiere el logo real
  hay que dejarlo en `src/assets/` y lo cableamos); muestra Mezcla,
  Temperatura y **Acumulado siempre** (antes solo en modo remito).
- `useBascula.js`: al guardar un vale de asfalto se abre automáticamente el
  modal de impresión (`abrirImpresionVale`) — interpretado como "abrir el
  diálogo/modal de impresión" tal como lo pidió Federico, **no** se dispara
  `window.print()` solo automáticamente (mayor riesgo de bloqueo del
  navegador tras un `await`; si se quiere ese comportamiento más agresivo,
  pedirlo explícito).
- `bascula.service.js#obtenerAcumuladoHastaFecha()`: agrupa por `pedido_id`
  si existe, cae a `obra_id` solo si no hay pedido — antes agrupaba siempre
  por obra, mezclando el acumulado de dos pedidos distintos de una misma
  obra despachándose en paralelo. Se recalcula en vivo tanto para el modo
  `vale` como `remito` (antes solo remito recalculaba), igual que el legado.
- RPC `registrar_pesada_bascula` (migración 10): valida N° de remito
  duplicado contra `plantas_ingresos` antes de guardar un ingreso de áridos.
- `BasculaView.vue`: header "Báscula — Despachos simultáneos" +
  "X puertas abiertas · Próximo N° 00009579" (`obtenerProximoNumeroVale()`,
  lectura de solo lectura vía `max(numero_vale)+1`, no consume la secuencia).

**Fase 2 (apertura de puertas + colapso + selectores):**
- Un solo botón **"+ Abrir puerta"** (antes 3 botones fijos por tipo); cada
  puerta abierta tiene un `<select>` interno (Vale Asfalto/Ingreso
  Áridos/Vale Salida Áridos) que cambia el tipo en cualquier momento,
  reseteando el formulario a la forma del nuevo tipo (`cambiarTipoSlot`).
- Las puertas dejaron de ser un tab-bar de "una activa a la vez": ahora son
  **cards apiladas independientes** (como el legado), cada una con su propio
  botón colapsar (▲/▼, `toggleColapso`) + cerrar (✕). Se sacó el concepto de
  `slotActivoId`/`slotActivo` del composable — ya no aplica.
- Ingreso de áridos: `Proveedor` pasó de texto libre a `<select>` sobre
  `plantas_proveedores` (catálogo ya existía, hoy vacío en la base de
  desarrollo — sin datos para probar el flujo completo todavía); `N° de
  remito` ahora es obligatorio (antes opcional); se sacó el campo `Chofer`
  (el legado no lo pide para ingreso/egreso, solo para Vale Asfalto).
- Egreso de áridos: `Destino` pasó de texto libre a `<select>` de obra
  (`obra_id`, reusa la columna que ya usaba asfalto) — la migración 10
  **eliminó la columna `plantas_vales.destino`** agregada en la migración 09
  (quedó redundante, no se dejó como deuda técnica).

Verificado: `npm run build` limpio, smoke test visual en el navegador (header,
3 tipos de puerta con sus campos correctos, colapso, apertura de 2 puertas en
simultáneo, sin errores de consola). **No se pudo probar el flujo completo de
guardado real** (RPC → historial → auto-print) porque la base de desarrollo
no tiene pedidos ni fórmulas ni proveedores cargados — pendiente probarlo con
datos reales antes de dar el módulo por 100% cerrado.

Pendiente explícito, fuera de esta tanda (no pedido por Federico esta vez):
- `Material` sigue siendo texto libre en ingreso/egreso (bloqueado por el
  catálogo `plantas_materiales`, que no existe — gap #2 de la Etapa 1).
- Módulo Despachos (historial dedicado) sigue sin construir — es el próximo
  módulo completo de la metodología, no un ajuste de Báscula.
