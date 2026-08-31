# modules-status.md — Estado de módulos

Listado de módulos identificados a partir del relevamiento del sistema anterior.
Todos arrancan en **PENDIENTE** hasta que se implementen sobre `plantas_*`.

| # | Módulo | Descripción breve | Estado |
|---|--------|--------------------|--------|
| 1 | Dashboard | KPIs del mes, analítica de proveedores, despacho por camión | EN CURSO — service + `DashboardView` listos (KPIs dobles tn/m³, comparativa de proveedores por período, detalle por camión con remito garantizado); falta aplicar migración SQL 05; **el semáforo de stock 🔴/🟡 proyectado semanal (banner de alerta) sigue sin construir en la UI del Dashboard** — la dependencia de datos ya está resuelta (módulo Stock, `plantas_stock`), falta el banner/cálculo de proyección en sí (`business-rules.md`, `UMBRAL=0.2`) |
| 2 | Pedidos | ABM de pedidos, ciclo solicitado→confirmado→despachado→postergado | EN CURSO — **Fase 1 de fidelidad funcional cerrada (2026-08-28)**: ver detalle abajo. |
| 3 | Plan semanal | Vista de pedidos confirmados/despachados agrupados por día | EN CURSO — service + `PlanSemanalView` (matriz lunes-domingo, KPIs tn/m³ por obra y total) listos; falta aplicar migración SQL |
| 4 | Stock | Stock por material en kg, ingresos/salidas manuales, guardas | **COMPLETADO (MVP) — 2026-08-31**: ver detalle abajo. |
| 5 | Despachos | Historial de pedidos despachados, filtros, exportación Excel | EN CURSO — **fidelidad funcional cerrada (2026-08-31)**: ver detalle abajo. Falta exports Excel (fuera de alcance de esta tanda). |
| 6 | Báscula / Balanza | Puertas de pesaje, vales de asfalto, ingreso/egreso de áridos | EN CURSO — **fidelidad funcional con el legado cerrada (2026-08-28, Fase 1+2 sobre el relevamiento Etapa 3)**: ver detalle abajo. **Descuento/ingreso de stock ya resuelto (migraciones 13/14)**: ingreso/egreso de áridos mueve `plantas_stock` directo desde `registrar_pesada_bascula`; el pesaje de asfalto YA NO toca `plantas_pedidos` (ver "Stock e Inventarios" abajo, migración 14) — el cierre del pedido y su descuento de stock son exclusivos de Pedidos |
| 7 | Fórmulas | Composición de mezclas (asfalto/hormigón), conversión a kg | EN CURSO — service + `FormulasView` con edición inline de insumos listos, scaffold Vite listo; falta `npm install` y aplicar la migración SQL de `plantas_formulas` (pendiente de confirmación). `calcularConsumoKg()`/`calcularConsumoTotalKg()` tienen gemela SQL (`plantas_calcular_consumo_kg`, migración 13) usada por el descuento de stock — si se cambia una, cambiar la otra. |
| 8 | Maestros | Obras, encargados, proveedores, patentes, choferes, materiales | EN CURSO — service + `MaestrosView` (tabs) listos, scaffold Vite listo; falta `npm install` y aplicar la migración SQL de `plantas_encargados/proveedores/patentes/choferes` (pendiente de confirmación). **Tab "Materiales" agregada 2026-08-31** (`plantas_materiales`, migración 13) — catálogo del módulo Stock, mismo patrón `crudEntidad` que el resto. |
| 9 | Usuarios | ABM de usuarios, mapeo con Supabase Auth y roles | PENDIENTE |
| 10 | Roles | Configuración de permisos por rol (override sobre defaults) | PENDIENTE |
| 11 | Backup | Backups automáticos/manuales y restauración | PENDIENTE |
| 12 | Resumen mensual / Reportes | Excel mensual de producción por obra e insumos | PENDIENTE |
| 13 | Migración de historial | Migrar datos del sistema anterior a `plantas_*` | PENDIENTE |
| 14 | Simulador de producción | Simular mix de fórmulas contra el stock actual, sin tocar datos reales | **COMPLETADO (MVP) — 2026-08-31**: ver detalle abajo. (No tenía fila propia en esta tabla hasta ahora — el relevamiento original lo mencionaba solo de paso dentro de Stock.) |

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

## Pedidos — Fase 1 de fidelidad funcional — CERRADA (2026-08-28)

Misma metodología: auditoría línea por línea contra Logica sis. plantas
v1.rtf/v2.rtf + `business-rules.md` + relevamiento en vivo → lista de gaps
→ aprobación de Federico → implementación → build → prueba real en el
navegador con datos de QA temporales (creados e **íntegramente borrados**
al terminar, la base de dev quedó igual que antes: 0 pedidos, 0 fórmulas).

Migración `supabase/migrations/11_postergar_historial_cierre_despacho.sql`
aplicada y verificada (incluye el fix de la misma sesión: `postergar_pedido`
también acepta re-postergar un pedido ya `postergado`, no solo
solicitado/confirmado).

**Implementado:**
- **Postergar pedido**: modal (nueva fecha + motivo, ambos opcionales) +
  RPC `postergar_pedido` (atómica, guarda fecha_programada_anterior/nueva
  en el historial). Probado en vivo end-to-end.
- **Historial del pedido**: `plantas_pedidos_historial` ahora se escribe en
  cada transición (`crearPedido`/`confirmarPedido`/`cancelarPedido` insertan
  su evento desde el service; `postergar_pedido`/`finalizar_despacho` lo
  hacen atómicamente dentro de la RPC) y se lee con el modal "Ver
  historial" (timeline con badge + fecha/hora + usuario + motivo). Probado
  en vivo, incluye el nombre real del usuario logueado.
- **Cierre parcial + pedido residual**: nueva RPC `finalizar_despacho` —
  única responsable de pasar confirmado→despachado, con lo cargado hasta
  ese momento (parcial o completo, Logica v1 §2.2). Si queda saldo, checkbox
  "Dividir pedido" genera automáticamente un pedido nuevo confirmado por el
  residual en la fecha elegida. `registrar_carga_asfalto`/
  `registrar_carga_hormigon` ya NO cierran el pedido solas (se les sacó esa
  lógica). **Probado en vivo end-to-end**: despacho parcial de 60/100 tn +
  dividir → pedido original quedó `despachado` (60 tn), se creó el residual
  `confirmado` (40 tn, fecha elegida), historial correcto en ambos.
- **Multi-carga hormigón**: `useCargaHormigon.js` reescrito al mismo patrón
  que `useDespachoAsfalto.js` (array de cargas, "+ Agregar carga"), mismo
  título de modal "Registrar despacho" para los dos materiales (confirmado
  en vivo que el legado usa uno solo). Se sacaron los campos Chofer y
  Fecha/hora (el legado real no los pide ahí) — quedan Cantidad, N° Remito,
  Patente.
- **WhatsApp (WppToast)**: `src/modules/pedidos/whatsapp.js` (funciones
  puras, arma mensaje + link `wa.me/?text=...`, sin número de destino
  porque `plantas_usuarios_roles` no tiene teléfono todavía). Toast
  dismissible con botón "Enviar por WhatsApp" al crear (→ plantista) y al
  confirmar (→ encargado; + toast adicional si es hormigón, sin hardcodear
  ningún contacto puntual como hacía el legado con "angel"/u12). Probado en
  vivo, el toast aparece con el mensaje correcto.
- **Editar pedido**: modal reutilizando el mismo set de campos que "Nuevo
  pedido", conectado a `actualizarPedido()` (sin evento propio de
  historial — edición no es un cambio de estado).
- **Ajustes visuales**: `VBadge` variante `postergado` (violeta, antes
  compartía `warning`/ámbar con `solicitado`) — confirmado en vivo, el
  color se ve correctamente distinto. `VButton` variante `success` (verde)
  para "Despachar"/"Registrar carga" — confirmado en vivo.
- **KPIs de estado** (pedido adicional de Federico durante la
  implementación, no estaba en la lista original): 5 tarjetas
  SOLICITADO/CONFIRMADO/DESPACHADO/POSTERGADO/CANCELADO con conteo y color
  por estado, arriba de la tabla — `fetchConteoEstados()` (5 `count:
  'exact', head: true` en paralelo, no lee filas, no pisa la regla de
  paginación). Probado en vivo, conteos correctos.

**Gap encontrado y corregido durante la prueba en vivo (no estaba en el plan
original)**: un pedido `postergado` se quedaba sin ninguna acción para
volver a `confirmado` — `business-rules.md` documenta esa transición
explícitamente (`postergado → confirmado → despachado`). Se agregó:
Confirmar/Postergar/Cancelar también disponibles desde `postergado`, y el
RPC `postergar_pedido` ahora permite re-postergar.

**Pendiente, fuera de esta Fase 1** (ya estaba fuera de alcance en el gap
report original, Federico no lo pidió esta vez):
- Roles/visibilidad por obra asignada — pospuesto a la etapa global de
  seguridad (decisión explícita de Federico).
- Exportar Excel de pedidos.
- Layout de cards agrupadas por tipo (Hormigón/Asfalto) — se mantuvo la
  tabla plana, solo se sumaron los KPIs de conteo arriba.
- Módulo Despachos (historial dedicado) — sigue sin construir. **✅ construido
  2026-08-31, ver sección "Despachos — fidelidad funcional cerrada" abajo.**

## Despachos — fidelidad funcional cerrada (2026-08-31)

Misma metodología que Báscula/Pedidos: auditoría contra `Logica sis. plantas
v1.rtf`/`v2.rtf` + `memory/relevamiento-sistema-viejo.md` §3/Etapa 3 → gap
report → aprobación de Federico → implementación → build → commit aislado.

Migración `supabase/migrations/12_despachos_vista_camion_y_correccion.sql`
aplicada y verificada. Incluye un ajuste de diseño hecho **en vivo durante la
aprobación**: la primera versión de este archivo deduplicaba
`plantas_cargas_asfalto` contra `plantas_vales` por N° de vale (para evitar
un supuesto doble conteo); Federico corrigió el flujo operativo real antes de
aplicarla — Báscula es detalle auditable camión por camión, Pedidos es donde
se cierra el despacho con la cantidadReal del remito final consolidado, no
son el mismo dato contado dos veces. La versión aplicada NO deduplica nada
— ver `memory/business-rules.md` §"Fuente de verdad según el tipo de
transacción" para el detalle completo de esta regla (también aplica al
futuro módulo Stock).

**Implementado:**
- **Fix de `plantas_v_despachos_camion`** (gap #12 del diagnóstico): la
  vista (migración 05) nunca se había actualizado cuando se agregó
  `plantas_cargas_asfalto` (migración 09) — un despacho de asfalto declarado
  desde Pedidos y todavía no pesado en Báscula no aparecía en el detalle por
  camión del Dashboard. Se agregó como tercer `UNION ALL`, sin deduplicar.
- **`src/services/despachos.service.js`**: listado paginado sobre
  `plantas_pedidos` (`estado='despachado'`), KPIs de acumulado histórico
  completo (`fetchAcumuladoHistorico`, sin límite de fecha — el Dashboard
  solo tenía el KPI del mes) + KPI del mes, resumen por obra
  (`fetchResumenPorObra`, agrupa por `obra_id` o por `cliente_externo` si es
  venta externa), detalle de cargas por camión (`fetchCargasDelPedido`, lee
  `plantas_cargas_asfalto`/`plantas_cargas_hormigon` directo — **no** la
  vista ni `plantas_vales`, porque la fuente de verdad del despacho es
  Pedidos), y `corregirDespacho()` (RPC `corregir_despacho`, migración 12).
- **`DespachosView.vue`** + `useDespachos.js` (composable, vista como
  template puro): 4 KPIs (Asfalto/Hormigón del mes + acumulado histórico,
  como el legado), filtros pill Todos/Hormigón/Asfalto + Mezcla + Obra +
  Desde/Hasta, resumen por obra con selector `<input type="month">` y grid
  de cards, tabla FECHA/OBRA/MEZCLA/PEDIDO/REAL/DIFERENCIA, acciones 🚛 Ver
  detalle de cargas / Corregir / 👁 Ver remito.
- **`DespachoImprimible.vue`**: remito A4 landscape imprimible (mismo
  mecanismo `.imprimible` + `window.print()` que `ValeImprimible.vue` de
  Báscula), una sola copia con dos firmas (responsable de planta / encargado)
  — Logica sis. plantas v1.rtf §4.5.
- **Corrección post-despacho**: RPC `corregir_despacho` (solo
  plantista/admin/plantista_hormigon, solo sobre pedidos `despachado`) edita
  `cantidad_despachada`/`nro_remito_global`/`nro_vale_global`, auditado en
  `plantas_pedidos_historial` como evento `corregido` (nuevo valor agregado
  al CHECK de esa tabla — no afecta los 5 estados reales de
  `plantas_pedidos`) con el valor anterior y el nuevo en `datos_legados`.
- Ruta `/despachos`, link + ícono nuevo (`camion`) en el sidebar, tab
  habilitado para plantista/encargado/supervisor/gerencia/admin (no
  balancero — confirmado en el relevamiento en vivo).

Build verificado (`npm run build` limpio). **Pendiente antes de darlo por
100% probado**: smoke test visual en el navegador con datos reales — la base
de dev no tiene despachos cargados hoy (mismo caveat que Pedidos/Báscula
Fase 1). Fuera de alcance a propósito, no pedido por Federico esta vez: los
5 botones de export (Eficiencia, Resumen mensual, Excel período, Por obra,
Excel completo) y el Resumen mensual completo (reporting pesado, toca
Stock + Ventas externas). Visibilidad "solo mis despachos" para
encargado/supervisor sigue pendiente de RLS fina (P0.2).

## Stock e Inventarios — COMPLETADO (MVP) — 2026-08-31

Misma metodología que Despachos/Pedidos/Báscula: auditoría contra
`Logica sis. plantas v1.rtf` §2.3/§4.4, `Logica sist plantas v2.rtf` §3.4 y
`memory/relevamiento-sistema-viejo.md` §6/Etapa 3 → gap report → 7
decisiones de diseño aprobadas por Federico → implementación → build →
hallazgo corregido en vivo → commit aislado.

Migraciones `supabase/migrations/13_stock_e_inventarios.sql` y
`14_bascula_sin_autocierre.sql` aplicadas y verificadas.

**Schema (migración 13):** 3 tablas nuevas — `plantas_materiales` (catálogo,
con `stock_minimo_kg`/`stock_maximo_kg`/`controla_stock`, CRUD en Maestros →
tab "Materiales"), `plantas_stock` (saldo actual en kg, 1 fila por
material), `plantas_stock_movimientos` (historial único append-only, nunca
se elimina, `cantidad_kg` con signo, 7 tipos: `ingreso_proveedor`,
`egreso_despacho`, `egreso_arido`, `ingreso_manual`, `egreso_manual`,
`ajuste`, `recalculo_despacho`).

**RPCs nuevas:** `registrar_movimiento_manual` (ingreso/salida manual, solo
plantista/admin), `registrar_relevamiento_stock` (relevamiento mensual —
**NO pisa el stock directo**, calcula diferencia por material e inserta un
movimiento `ajuste`; implementa `saveStockGuard` con los umbrales exactos
del legado: bloquea si <50% de los materiales con valor lo pierden, o el
total cae >90%). Helpers internos (sin grant a `authenticated`):
`plantas_buscar_material_id` (matching por nombre contra el texto libre de
fórmulas/báscula/ingresos), `plantas_calcular_consumo_kg` (gemela SQL de
`calcularConsumoKg()` de `formulas.service.js`), `plantas_aplicar_movimiento_stock`,
`plantas_descontar_stock_despacho`.

**Integración con Pedidos/Báscula:** `finalizar_despacho()` y
`corregir_despacho()` ahora descuentan/reajustan stock automáticamente
(delta × fórmula, excluyendo Agua/Purgue por nombre); `registrar_pesada_bascula()`
mueve stock en `ingreso_arido` (cantidad del remito, no el peso neto) y
`egreso_arido` (peso neto real).

**Hallazgo corregido en la misma sesión (migración 14):**
`registrar_pesada_bascula()` (asfalto, con `pedido_id`) seguía cerrando el
pedido a `despachado` directamente al alcanzar `cantidad_solicitada` —
comportamiento de la migración 09, nunca tocado por la migración 11 (que
estableció que solo `finalizar_despacho()` cierra). Con el descuento de
stock recién enganchado ahí, un despacho cerrado por esa vía **nunca
descontaba stock**. Se sacó por completo el bloque que tocaba
`plantas_pedidos` desde `registrar_pesada_bascula()` — Báscula queda 100%
como detalle auditable, sin efecto sobre el pedido; el cierre y el
descuento de stock son exclusivos de Pedidos (`registrar_carga_asfalto` +
`finalizar_despacho`).

**Código:** `src/services/stock.service.js`, `src/modules/stock/composables/useStock.js`,
`src/views/StockView.vue` (cards con `VSemaforo` + barra min/máx ya
construido y sin uso hasta ahora, toggle tn/kg, ingreso/salida manual,
relevamiento mensual, historial paginado). Analítica de proveedores queda
en el Dashboard (decisión de Federico) — Stock solo tiene un link de acceso
rápido, no se duplica.

Build verificado (`npm run build` limpio). Pendiente antes de darlo por
100% probado: smoke test con datos reales (no hay materiales cargados en la
base de dev todavía). Fuera de alcance a propósito: exportar Excel, y el
semáforo de stock **proyectado semanal** del Dashboard/Plan Semanal (usa
`plantas_stock` como fuente pero el banner/cálculo en sí no está construido
— ver fila #1 de la tabla de arriba).

## Simulador de Producción — COMPLETADO (MVP) — 2026-08-31

Misma metodología, con un paso extra: la documentación del legado (.rtf +
relevamiento Etapa 1) era mucho más escasa que la de los demás módulos (una
sola línea en cada .rtf, sin pasada Etapa 3) — antes de diseñar el MVP se
hizo un **relevamiento en vivo dedicado** contra `produccion.vialtec.app`
(sesión de Federico como Administrador) para ver la pantalla de resultado
real, algo que ninguna sesión anterior había llegado a hacer.

**Hallazgos del relevamiento en vivo** (cargada una simulación real con mix
de 2 fórmulas — asfalto + hormigón):
- Confirma mix de fórmulas simultáneo con subtotales separados por tipo
  ("Total asfalto"/"Total hormigón", cada uno solo visible si hay entradas
  de ese tipo).
- Tabla de impacto: INSUMO | STOCK ACTUAL | CONSUMO TOTAL | STOCK PROYECTADO
  | ESTADO — consumo combinado de TODAS las entradas por insumo.
- **NO calcula "capacidad máxima"** (cuántas unidades más entran dado el
  stock) — es resta simple `proyectado = actual - consumo`, puede dar
  negativo en pantalla sin problema (es solo informativo).
- **ESTADO es BINARIO** (OK / Insuficiente, badges pill) — a propósito
  distinto del semáforo de 3 colores de las cards de Stock.
- **Sin ningún botón de exportar** en toda la pantalla.

Aprovechando la sesión logueada se relevó también Stock a fondo (ver
hallazgos abajo) y se confirmó que el histórico "AJUSTE" no existe en el
legado (coincide con que el relevamiento mensual legado nunca dejaba
auditoría — por eso Federico decidió que el nuestro sí, ver sección Stock).

**Implementado — `src/modules/simulador/composables/useSimulador.js` +
`src/views/SimuladorView.vue`**: 100% client-side, **sin tabla ni migración
SQL propia** — reusa `calcularConsumoTotalKg()` (`formulas.service.js`) y
`fetchStockActual()` (`stock.service.js`). Formulario con unidad dinámica
(tn/m³ según tipo de fórmula), lista acumulable con ✕, subtotales
condicionales, tabla de impacto fiel a lo relevado (estado binario, sin
capacidad máxima, sin export). Ruta `/simulador`, tab habilitado para
admin/plantista (únicos roles que lo listan ambos .rtf y el menú real).

## Fixes de Stock (colaterales al relevamiento de Simulador) — migración 15

- **Piso en 0** (`GREATEST`, Logica sis. plantas v1.rtf §5.3: "el stock
  nunca queda negativo, va a 0 como mínimo") en
  `plantas_aplicar_movimiento_stock`. El delta que se audita en
  `plantas_stock_movimientos` es el **realmente aplicado** (no el
  solicitado) para que `sum(movimientos)` siempre reconcilie exacto contra
  `plantas_stock.cantidad_kg` — si hubo recorte por piso, queda una nota
  automática en `observaciones`.
- **Umbral "Ajustado" corregido** en `calcularEstadoSemaforo()`
  (`stock.service.js`): `mínimo + 20% del rango (máx-mín)`, confirmado
  contra un caso real de producción (ARENA 0/3: 66,38t, mín 50t, máx 150t →
  Ajustado) — el supuesto anterior (`mínimo × 1,2`) no encajaba con ese
  dato real.
- **Columna Responsable** en el historial de movimientos:
  `plantas_stock_movimientos.responsable_email` (nuevo, `auth.email()`
  server-side — `auth.users` no se expone vía API) + `fetchNombresPorEmail()`
  nuevo en `flota.service.js` (cruza contra `flota_usuarios_email`, mismo
  patrón que ya usa `auth.store.js`).

Build verificado (`npm run build` limpio).

## Módulos pendientes de desarrollo (2026-08-28, actualizado 2026-08-31)

Próximos en la metodología (relevamiento en vivo → gap report → aprobación
→ implementación → build → prueba real → commit aislado).

- **Usuarios y Permisos por rol** — restricciones reales (RLS fina, hoy
  `using (true)` en las 9 tablas) y visibilidad de pedidos por obra
  asignada — es la etapa de seguridad pospuesta durante Pedidos Fase 1.
- **Auditoría** — panel para ver quién ejecutó cada acción y su
  trazabilidad (además del historial de pedidos, que ya existe).

**Nota explícita para cuando se arranque cualquiera de estos**: antes de
tocar código hay que repetir la misma auditoría que ya se hizo con Báscula
y Pedidos — navegar en vivo el sistema viejo (produccion.vialtec.app) para
relevar el comportamiento exacto de ese módulo puntual (botones, modales,
validaciones, columnas), no asumirlo solo desde `Logica sis. plantas
v1.rtf`/`v2.rtf` o `business-rules.md`. Esos documentos son la base, pero
el relevamiento en vivo ya corrigió varias veces cosas que decían distinto
de lo que el sistema real hace hoy (ver `relevamiento-sistema-viejo.md`).
