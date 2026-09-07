# pending.md — Pendientes

## 🔴 4 mejoras pedidas por Federico (2026-09-07) — diagnóstico hecho, 2 migraciones + 1 corrección de datos esperando confirmación

Pedido explícito de Federico: Báscula (performance + filtro), Home en la
matriz de permisos, teléfono para WhatsApp, limpieza de un ingreso de
prueba en Stock — más un 5to pedido que llegó a mitad de sesión (remito en
portrait). Todo el código ya está commiteado y con build limpio; lo que
sigue abajo son las 3 acciones sobre producción que el clasificador de
permisos bloqueó (correctamente — son schema cambiante/datos, protocolo de
`procedimientos.md`) y necesitan tu "dale" explícito antes de correr.

1. **Báscula — performance + filtro semanal — CÓDIGO LISTO, MIGRACIÓN 29
   PENDIENTE.** Medido con `EXPLAIN ANALYZE` contra producción (rol
   `authenticated` real): listar 1 semana de historial de Báscula tardaba
   **706ms** con solo ~900 vales en toda la tabla — nada crítico hoy, pero
   iba a degradarse linealmente con el uso. Causa real: las policies RLS de
   `plantas_vales`/`plantas_ingresos`/`plantas_stock`/`plantas_stock_movimientos`
   (`plantas_puede_ver_bascula()`/`plantas_puede_ver_stock()`) y la de
   `plantas_pedidos`/`plantas_usuarios_roles` (`auth.email()` directo)
   se reevaluaban **una vez por cada fila** en vez de una sola vez por
   consulta — mismo patrón que el propio advisor de performance de Supabase
   marca como WARN (`auth_rls_initplan`) en 2 de estas tablas. Fix (patrón
   oficial de Supabase, cero cambio de comportamiento): envolver esas
   llamadas en `(select ...)` para que Postgres las trate como InitPlan.
   Verificado en un `begin/rollback` contra producción: **706ms → 13.4ms
   (~52x)**, mismo resultado exacto. Migración lista en
   `supabase/migrations/29_optimizacion_rls_bascula.sql` — **falta que la
   aplique** (bloqueada por el clasificador de permisos al intentar
   `apply_migration`, requiere confirmación explícita).
   - Filtro de fecha por defecto a la semana en curso: **ya implementado y
     commiteado** (`useBascula.js`/`BasculaView.vue`, mismo patrón que
     Pedidos), no depende de la migración de arriba.
2. **Home en la matriz de permisos — CÓDIGO LISTO, MIGRACIÓN 30
   PENDIENTE.** `dashboard` (Home) era un caso hardcodeado siempre visible,
   sin pasar por `plantas_permisos`. Código ya agrega la fila "Home" a la
   matriz de Administración → Roles y saca el bypass especial de
   `auth.store.js`. Migración `supabase/migrations/30_permiso_home_matriz.sql`
   agrega `'dashboard'` al CHECK de `plantas_permisos.modulo` + siembra
   "ver" en `true` para los 6 roles no-admin existentes (para que aplicarla
   no le saque Home a nadie hasta que vos destildes un switch a propósito)
   — **falta aplicarla** (mismo bloqueo del clasificador).
3. **WhatsApp — teléfono del encargado — CÓDIGO LISTO, sin pendiente de
   producción.** `flota_usuarios_email.telefono` (sistema de flota) tiene
   teléfono cargado para 11 de 19 usuarios, en formato listo para wa.me. El
   toast de "Avisar al encargado" (al confirmar un pedido) ahora resuelve
   el teléfono por **match exacto** contra `pedido.encargado` (a propósito
   no es fuzzy — mismo motivo que ya frenó el merge automático de choferes)
   y abre el chat directo cuando hay match; sin match, sigue como antes
   (wa.me sin destinatario). "Avisar al plantista"/"Avisar al operador de
   hormigón" quedan sin cambios — no hay un campo del pedido del que
   resolver un destinatario concreto sin adivinar.
4. **Limpieza de datos de prueba en Stock — 1 de 2 YA ESTABA RESUELTO, 1
   SIGUE PENDIENTE.** Investigando el ingreso de prueba que ya estaba
   anotado más abajo (sección "🎯 CORTE COMPLETO", "Hallazgo menor, no
   corregido"):
   - **Filler +1.000 kg ("PRUEBA QA - BORRAR", ingreso_manual, 06/09
     21:29)**: encontrado YA COMPENSADO en la base — hay un movimiento
     `ajuste` de -1.000 kg (07/09 03:51, `id 7551fd1b…`) con observaciones
     que lo describen explícitamente como la reversión de este mismo test.
     Se aplicó en algún momento de hoy, en una sesión previa a esta, sin
     dejarlo documentado acá ni en un commit — corrijo esa desprolijidad
     con esta entrada. Sin acción pendiente, stock de Filler correcto.
   - **🔴 Fuel Oil −1.000 kg ("PRUEBA QA - BORRAR", egreso_manual, 06/09
     21:30, `id e9559db6…`) — NUNCA se revirtió**, a pesar de que esta
     misma sección de `pending.md` (más abajo, "Verificación RLS
     Fórmulas/Maestros...", 2026-09-06) decía "Fuel Oil −1tn... revertido"
     — ese registro era incorrecto, no hay ningún movimiento compensatorio
     real en la tabla. Es el movimiento MÁS RECIENTE de Fuel Oil: el stock
     actual (23.700 kg) sigue arrastrando ese descuento de prueba — el
     valor real debería ser **24.700 kg**. **Falta correr la compensación**
     (mismo patrón que la de Filler: un movimiento `ingreso_manual`/`ajuste`
     de +1.000 kg con observaciones explicando la corrección) — bloqueado
     por el mismo protocolo de datos en producción, necesito tu
     confirmación antes de insertarlo.
5. **Remito de Báscula en portrait — CÓDIGO LISTO, sin pendiente de
   producción, pero sí de verificación real.** Pedido que llegó a mitad de
   esta sesión: el remito (`ValeImprimible.vue` modo="remito") vuelve a
   imprimir en A4 vertical (como el remito físico real que le dio origen al
   diseño, 2026-09-01) vía una "named page" de CSS, sin tocar el vale ni el
   remito de Despachos (`DespachoImprimible.vue`, siguen en landscape). **No
   se pudo verificar con el diálogo real de impresión** (la automatización
   del navegador no puede disparar el diálogo nativo sin riesgo de
   bloquearse) — la vez anterior que se intentó este mismo mecanismo
   (2026-09-03 tarde) Chrome no lo terminó respetando en el diálogo real
   aunque sí en una simulación por JS. Pedirte que imprimas un remito real
   antes de darlo por cerrado del todo.

**Necesito tu confirmación explícita para 3 acciones sobre producción**
(protocolo de `memory/procedimientos.md`): aplicar la migración 29 (RLS,
sin cambio de comportamiento), aplicar la migración 30 (agrega Home a la
matriz, sembrada para no cambiar nada hasta que se toque un switch), y
correr la compensación de Fuel Oil (+1.000 kg, revierte el test que quedó
sin limpiar). Las 3 son de bajo riesgo y reversibles (RLS se puede volver
atrás con otro `alter policy`, la migración de Home no borra nada, la
compensación de stock es el mismo patrón ya usado varias veces en esta
misma sesión de trabajo) pero ninguna se corrió — quedan listas para en
cuanto confirmes.

## ✅ Plan Semanal — pedidos despachados sin marcar + obra faltante (2026-09-07, post-corte)

Federico reportó viendo Plan Semanal: varios pedidos de martes/miércoles/
jueves (01, 02 y 03/09) figuraban "Confirmado" cuando deberían estar
despachados, y uno del miércoles mostraba "Obra sin asignar". No tenía
acceso al legado para comparar (ya dado de baja). Investigado y corregido
en producción — dos causas distintas, ambas heredadas de datos del
legado, no bugs de esta sesión:

**1) 5 de 6 pedidos "confirmado" ya estaban despachados de verdad.**
Cada uno tenía su evento `despachado` en `plantas_pedidos_historial`
(03/09, usuario "Felix Pereyra") Y sus cargas/vales reales cargados —
pero el campo `plantas_pedidos.estado` se había quedado en "confirmado".
Es una inconsistencia del propio legado (el campo de estado del pedido
nunca se sincronizó con el historial ahí), que la migración del delta
copió tal cual venía. Consecuencia real, no solo visual: como esos 5
pedidos nunca pasaron por `estado = 'despachado'` en el sistema nuevo,
**el stock nunca se descontó** para esas 5 entregas.

Corregido (autorizado por Federico) para los 5:
`21a1360b…` (hormigón, Previal-Ute, 30 m³), `e16bc19b…` (hormigón, Predio
Vialtec, 3 m³), `52a1a0a9…` (asfalto venta AUTOVIA MERCOSUR, 350.28 tn —
suma real de 12 vales, no la cantidad solicitada de 400), `f451ac0b…`
(asfalto venta MUNICIPALIDAD DE PILAR, 40.80 tn), `b59864f7…` (asfalto,
Municipalidad Exaltación de la Cruz, 7.98 tn). Para cada uno: `UPDATE
plantas_pedidos SET estado='despachado', cantidad_despachada=<suma real
de cargas/vales>` + `SELECT plantas_descontar_stock_despacho(id, 0,
cantidad_despachada)` (misma función que usa `finalizar_despacho()`,
llamada directo porque no hay sesión JWT vía SQL directo — sin insertar
un evento de historial nuevo, ya existía el real). El sexto pedido de esa
semana (jueves, Predio Vialtec, hormigón 1.5 m³) sí estaba bien como
"confirmado" — no tenía despacho real, se dejó igual.

**2) "Obra sin asignar" — la obra no existía en `flota_obras`, no era un
error de mapeo.** El pedido (miércoles 02/09, `b59864f7…`) pertenece a
"Municipalidad exaltacion de la cruz" (`vt_maestros9`, id legado
`cjlmpvj`) — esta obra nunca se cargó en `flota_obras` (tabla compartida
con Flota). Esto YA estaba detectado desde la migración original del
01/09 (ver más abajo, "Idempotencia..." → checklist punto 2) como
pendiente de decisión de Federico — son 3 pedidos en total los que la
referencian (2 ya despachados de junio/agosto 2026, más este). Otros dos
pedidos "Obra sin asignar" de esa misma semana (venta AUTOVIA MERCOSUR /
MUNICIPALIDAD DE PILAR) son correctos como están: son `tipo_pedido =
'venta'` con `cliente_externo`, no llevan obra por diseño.

Corregido (autorizado por Federico): `INSERT INTO flota_obras (nombre,
estado, activo) VALUES ('Municipalidad de Exaltación de la Cruz',
'activa', true)` → id **38** (identity, autogenerado — no se fuerza el id
a mano). Vinculados los 3 pedidos (`obra_id = 38`) y sus **9 vales**
asociados en `plantas_vales` (también tenían `obra_id = null`, copiado
del pedido al momento de migrar) — necesario para que
`plantas_puede_ver_obra()` (RLS fina, migración 23) los muestre bien a
roles con visibilidad acotada por obra, no solo a `ver_todas_obras=true`.

**Nota para el futuro**: si aparece otra obra "sin asignar" en un pedido
`tipo_pedido = 'obra'` (no `'venta'`), el diagnóstico es el mismo: buscar
`datos_legados->>'obraId'` en `plantas_pedidos`, cruzarlo contra
`vt_maestros9.obras` en `kv_store` para el nombre real, y contra
`flota_obras` para ver si existe con otro nombre/grafía o si hay que
darla de alta — no asumir que es un bug del mapeo de la migración antes
de descartar que la obra directamente no esté cargada en Flota.

## 🎯 Plan de corte definitivo legado → nuevo (decisión de Federico, 2026-09-04)

Al mostrar Federico una captura del "Cronograma Semanal" del legado con
pedidos de esta semana (2, 3 y 4 de septiembre) que el Plan Semanal del
sistema nuevo no tenía, se verificó que es el gap ya conocido y decidido
(ver "Vistas puente Báscula/Stock" más abajo: "Pedidos NO tiene vista
puente, decisión explícita de Federico, descartado el trigger también").
Cuantificado hoy: `vt_p9` (legado) sigue actualizándose en vivo (última
escritura 2026-09-04 19:30 UTC — el legado se sigue usando para cargar
pedidos en paralelo), 4 pedidos de esta semana existen solo ahí (1 del
2/9, 2 del 3/9, 1 del 4/9).

Le propuse 3 opciones (vista puente para Pedidos / migrar estos 4 a mano /
cortar ya el uso del legado) y **Federico eligió una 4ta, la definitiva**:

> "la otra opcion es seguir asi, y seguir ajustando el sistema y cuando
> vea q el sistema esta bien hacemos la migracion de todo lo que no esta,
> al sistema nuevo le ponemos el dominio del sistema viejo y listo"

O sea: **NO tocar Pedidos con una vista puente ni con inserts manuales
puntuales por ahora** — el legado sigue siendo la fuente viva de Pedidos
mientras Federico sigue probando/ajustando el sistema nuevo. Cuando él
considere que el sistema nuevo está listo para producción real, el plan
de corte es:

1. Migración final de TODO lo que no esté migrado todavía (mismo criterio
   que `migracion_historial_v2.sql` del 1/9, pero corriéndola de nuevo /
   extendida para capturar el delta acumulado desde esa fecha — pedidos,
   vales de báscula, movimientos de stock, lo que corresponda en ese
   momento).
2. Apuntar el dominio `produccion.vialtec.app` (hoy el legado) al sistema
   nuevo — reemplazo de dominio, no migración de datos de usuarios finales
   (ya comparten el mismo Supabase).
3. Dar de baja el sistema legado como fuente de escritura.

**Implicancia para sesiones futuras**: no proponer ni implementar una
vista puente de solo lectura para Pedidos (`plantas_v_pedidos_viva` o
similar) salvo que Federico lo pida explícitamente — es una decisión
tomada dos veces ya (primero al armar las vistas de Báscula/Stock, ahora
de nuevo acá). El Plan Semanal / Pedidos del sistema nuevo van a seguir
mostrando "menos" que el legado hasta el corte definitivo, y **eso es
esperado, no un bug** mientras no se decida lo contrario.

**Antes del corte, pedido explícito de Federico (2026-09-04)**: cuando se
esté por terminar la etapa de ajuste ("cuando estemos terminando, dentro
de poco"), hacer (a) una prueba del **flujo TOTAL del sistema,
absolutamente todo** (no módulos sueltos: Pedidos ciclo completo
crear→confirmar→despachar con división→postergar→cancelar, Báscula 3
puertas + impresión vale/remito + acumulado, Despachos, Stock, Maestros,
Usuarios y Permisos/RLS por rol, Dashboard, exports a Excel) y (b) una
**auditoría exhaustiva** (migración completa sin faltantes — extender
`auditoria_historico_vs_legado.sql` —, RLS por rol, el hallazgo de
seguridad pendiente de `kv_store` con policy abierta a `public`/`anon`
—ver más abajo—, chequeo de paginación en toda vista nueva). Sin fecha de
arranque fija todavía — a definir con Federico, probablemente el fin de
semana antes del corte.

**Fecha objetivo (dicha por Federico el mismo 2026-09-04, viernes):**
este fin de semana (sáb. 5 / dom. 6 de septiembre 2026) se termina de
ajustar/pulir el sistema, con el objetivo de tenerlo andando (= corte de
dominio, ver plan arriba) **el lunes 7 u/o martes 8 de septiembre 2026**.
Sigue siendo un objetivo, no una fecha 100% confirmada — no asumir que el
corte ya pasó sin confirmarlo de nuevo con Federico al arrancar una sesión
posterior a esa fecha.

## ✅ Prueba de flujo TOTAL + auditoría exhaustiva — 2026-09-06, APLICADO y VERIFICADO

Primera ejecución del punto (a)/(b) pedido por Federico el 2026-09-04 (ver
sección de arriba). Metodología: prueba real contra producción con datos
mínimos claramente marcados ("PRUEBA QA - BORRAR", obra real Highland, 1 tn,
fórmula real CAC D19) manejando el navegador con la sesión real de Federico
— aprobado explícitamente por él por el efecto colateral conocido (1 número
de vale consumido y no reutilizable, como un vale de papel anulado) — y
borrado íntegro al terminar (pedido, historial, carga, vale, movimientos de
stock; stock repuesto exacto a los valores previos, verificado por SQL
antes/después).

**Flujo probado end-to-end, 100% correcto:**
Crear pedido → Confirmar → Pesar en Báscula (vale asfalto N° 10494, el
pedido quedó `confirmado`, sin auto-cierre — migración 14 funcionando) →
Registrar despacho en Pedidos con ese N° de vale → pedido `despachado` →
descuento de stock exacto (Piedra 6/20 -470kg = 47%×1000×1tn, Arena 0/6
-530kg = 53%×1000×1tn, relación cantidad×fórmula perfecta) → historial del
pedido con los 3 eventos (solicitado/confirmado/despachado, usuario y
timestamp reales) → Despachos → Detalle de cargas consolidado
correctamente (PEDIDO 1tn = REAL 1tn, diferencia 0.00tn).

**Hallazgos de la auditoría:**

1. **🔴 Confirmado, sin tocar (decisión de Federico)**: `kv_store` tiene
   una policy RLS `"Acceso publico kv"` — `roles={public}`, `cmd=ALL`,
   `qual=true` — cualquiera con la anon key puede leer/escribir/borrar TODO
   el histórico del legado sin login. Ya estaba anotado como pendiente;
   confirmado en vivo. Federico decidió NO tocarlo ahora (el legado lo
   sigue consumiendo en vivo, riesgo de interrumpir la operación
   pre-corte) — **se resuelve el día de la migración final, cuando se
   apague el legado**.
2. **✅ Corregido en esta sesión**: la tab "Historial de ingresos" de Stock
   mostraba TODOS los tipos de movimiento por defecto (incluidos egresos
   por despacho/árido/manual y ajustes), cuando la idea es que solo
   aparezcan ingresos de materiales — reportado por Federico en vivo
   durante la prueba, al ver el egreso de mi pedido de prueba mezclado ahí.
   Fix: `queryMovimientos()` (`stock.service.js`) ahora acepta `tipo` como
   array (`.in()`), y la tab acota por defecto a `TIPOS_INGRESO`
   (`ingreso_proveedor`/`ingreso_manual`, exportado desde el service) salvo
   que el usuario elija un tipo puntual; el dropdown "Tipo" de
   `StockView.vue` se acotó a esos 2 valores (los egresos ya tienen su
   propia vista en Despachos/Báscula, no se duplican acá). Verificado
   visualmente y con build limpio.
3. **🟡 Confirmado, sin tocar (decisión de Federico)**:
   `plantas_aplicar_movimiento_stock()` no inserta fila en
   `plantas_stock_movimientos` cuando el delta aplicado da exactamente 0
   (material ya en el piso de 0) — no rompe el stock, pero no deja rastro
   de que un despacho "debería" haber consumido ese insumo. Federico
   decidió mantener el comportamiento actual (no meter registros en cero
   innecesarios).
4. **Investigado, NO es un hallazgo nuevo**: la diferencia entre
   `sum(plantas_stock_movimientos)` y `plantas_stock.cantidad_kg` por
   material es un límite ya documentado en el propio
   `migracion_historial_v2.sql` (línea ~105): el saldo final se cargó
   directo desde `vt_s9`, no derivado matemáticamente de los movimientos
   migrados. No accionable.
5. **Nota menor, no urgente**: `plantas_pedidos.nro_vale_global` queda
   `null` en despachos hechos por el flujo nuevo (solo lo tienen 95/160,
   todos migrados) — el N° de vale real queda correctamente en
   `plantas_cargas_asfalto.numero_vale` por carga, no se pierde
   información, es una columna legada que ya no se sigue poblando.
6. **Orientación de impresión (punto pendiente desde 2026-09-03)**:
   verificado en código, ya está resuelto — un único `@page` global en A4
   landscape (210mm) para toda la app, sin ningún `@page` con nombre en
   portrait residual. Vale y remito de Báscula y Despachos imprimen
   horizontal. Confirmado por Federico como el comportamiento deseado, sin
   cambio de código necesario.

**Archivos tocados**: `src/services/stock.service.js`,
`src/modules/stock/composables/useStock.js`, `src/views/StockView.vue`.
Build verificado (`npm run build` limpio) en cada paso.

## ✅ Renumeración de vales sintéticos de ingreso_arido — 2026-09-06, APLICADO y VERIFICADO

Hallazgo de la auditoría de arriba, ya documentado desde el 2026-09-04
("Vistas puente Báscula/Stock"): los 500 `ingreso_arido` migrados el 1/9
recibieron `numero_vale` SINTÉTICO (la identity de la tabla los numeró
correlativos en ese momento, 9994-10493) porque el legado nunca los
numera — pero el asfalto real del legado sigue avanzando en paralelo y ya
venía entrando en ese mismo rango. Propuesta técnica presentada a Federico
con impacto evaluado (sin FK por `numero_vale`, vista puente matchea por
`datos_legados`/`numero_remito`+`material` no por `numero_vale`, pero sí
hacía falta ajustar `obtenerProximoNumeroVale()` que hacía
`max(numero_vale)+1` sin filtrar tipo) — **aprobada por Federico
2026-09-06**.

**Ejecutado:**
- `src/modules/bascula/services/bascula.service.js#obtenerProximoNumeroVale()`:
  agregado `.lt('numero_vale', 90000000)` para excluir el bloque sintético
  del cálculo del "Próximo N°" que ve el balancero (inofensivo hasta que
  se corrió el script de abajo, necesario después). Build verificado.
- Script SQL corrido contra producción (transaccional): `numero_vale` es
  `GENERATED ALWAYS AS IDENTITY` (arranca en 9579) — no admite `UPDATE`
  directo, hubo que bajarla a `GENERATED BY DEFAULT`, renumerar, y
  devolverla a `GENERATED ALWAYS` en la misma transacción. Los 500
  `ingreso_arido` (los que tenían `numero_vale` entre 9994-10493 y
  `datos_legados` poblado = ninguno es real) se movieron a
  **90000001-90000500** — bloque separado que no puede colisionar con un
  número de vale real, pasado ni futuro (a la velocidad actual, faltarían
  siglos para llegar ahí). Solo cambió `numero_vale`; `id`, `datos_legados`
  y la fila completa quedaron intactos — verificado que
  `plantas_ingresos.vale_id` (FK por `id`, no por `numero_vale`) y el
  `datos_legados->>'id'` de cada fila renumerada siguen apuntando
  correctamente.
- **Verificado post-script**: 0 filas en 9994-10493, 500 filas en
  90000001-90000500 (las 500 son `ingreso_arido`), columna `numero_vale`
  vuelve a ser `GENERATED ALWAYS` (`is_identity = YES`), secuencia real sin
  tocar (siguió en su posición, próximo vale real ~10495 — el hueco de
  10494 es el de la prueba de flujo de arriba, ya conocido y aceptado).

**🔴 Pendiente para el día de la migración final / corte de dominio** (NO
hacer antes, es parte de esa migración): cuando se migre el asfalto real
del legado que hoy ocupa (o va a ocupar) la zona 9994 en adelante con sus
números reales de papel, esos van a insertarse limpios ahí (ya no hay nada
sintético nuestro en el medio). Al terminar esa migración hay que correr
`setval('plantas_vales_numero_vale_seq', (select max(numero_vale) from
plantas_vales where numero_vale < 90000000), true)` para que la secuencia
quede sincronizada exacta contra el `max(numero_vale)` real — mismo
criterio que se usó el 2026-09-01 con `migracion_historial_v2.sql`. Sin
este paso, el sistema nuevo podría volver a asignar un número ya usado por
el legado recién migrado.

## ✅ Prueba de flujo TOTAL — casos de borde (Paso 1, parte 2) — 2026-09-06, APLICADO y VERIFICADO

Continuación de la prueba de flujo de la sección de arriba (que cubrió solo
el camino feliz de un despacho de asfalto simple) — pedido explícito de
Federico de cubrir además los casos de borde: Postergar/Cancelar/Dividir
pedido, hormigón multi-carga, Báscula ingreso/egreso de áridos, Corregir
despacho, Usuarios y Permisos, Dashboard y exports a Excel. Misma
metodología: datos mínimos marcados "PRUEBA QA - BORRAR"/"QA Test" contra
producción, verificación por SQL antes/después, borrado íntegro y stock
repuesto exacto al terminar cada caso (verificado, 0 rastros).

**Todo lo probado funcionó correctamente:**
- **Postergar → re-confirmar**: pedido postergado (fecha nueva + motivo)
  vuelve a `confirmado` sin problema (transición documentada en
  `business-rules.md`), timeline de 4 eventos correcto.
- **Despacho parcial + Dividir pedido**: 6 de 10 tn despachadas → pedido
  original `despachado` (6tn), pedido residual `confirmado` (4tn, fecha
  elegida) creado automáticamente. Stock descontado exacto por fórmula.
- **Cancelar pedido**: bloqueado sin motivo (mensaje "cancelarPedido: el
  motivo es obligatorio", ver hallazgo 🟡 abajo), cancela bien con motivo,
  sin reactivación posible después (solo queda "Archivar" en la card).
- **Hormigón multi-carga**: 2 cargas (2 remitos distintos) sobre un mismo
  pedido, cierran el pedido con el total sumado correcto, descuento de
  stock exacto en los 6 materiales de la fórmula (Agua excluida).
- **Báscula — Ingreso de áridos**: vale con N° real correlativo (confirma
  que el fix de `obtenerProximoNumeroVale()` de la renumeración de arriba
  funciona), stock actualizado por la **cantidad declarada en el remito**
  (no el peso neto pesado), diferencia trazable.
- **Báscula — Egreso de áridos**: vale con N° real correlativo, stock
  descontado por el **peso neto real** (no hay remito de origen acá) —
  ambos casos respetan exactamente `business-rules.md`.
- **Corregir despacho**: cambia `cantidad_despachada` y reajusta stock
  (`recalculo_despacho`) — ver hallazgo 🔴 abajo, el reajuste no siempre es
  correcto.
- **Usuarios y Permisos**: la Migración 21 ya estaba aplicada (ver sección
  dedicada más abajo, corrección de una entrada vieja de este archivo que
  había quedado desactualizada) — alta y edición de usuario probadas
  end-to-end, funcionan.
- **Dashboard/Home**: KPIs, consumo de material y próximos despachos
  cargan sin errores de consola con los datos reales post-limpieza.
- **Exports a Excel**: los 3 de Stock (Stock actual, Historial de
  ingresos, Analítica de proveedores), el Informe mensual de Despachos y
  el de Báscula — los 5 generan un `.xlsx` válido. **Nota de proceso**: la
  descarga tarda 2-6 segundos en materializarse en disco (ExcelJS
  generando el archivo) — un chequeo inmediato después del click puede dar
  falso negativo, hay que esperar antes de concluir que un export falló.
  **Pedidos no tiene botón de exportar Excel** — gap ya documentado desde
  la Fase 1 (2026-08-28), no es un bug de esta prueba, sigue pendiente si
  se lo quiere agregar.

**Hallazgos reales encontrados:**

1. **🔴 Corregir despacho puede crear stock fantasma** —
   `plantas_descontar_stock_despacho()` (llamado desde `corregir_despacho`)
   recalcula el delta de stock como `fórmula × (cantidad_nueva −
   cantidad_vieja)`, asumiendo que el despacho original consumió el 100%
   de lo que la fórmula indicaba. Si un material estaba en el piso de 0
   durante el despacho original (por diseño, `plantas_aplicar_movimiento_stock`
   no descuenta ni deja rastro cuando el delta aplicado da 0 — decisión de
   Federico de mantener así, ver sección de arriba), la corrección
   posterior le "devuelve" kg que en la realidad nunca salieron, generando
   stock que no existe. Reproducido en vivo: pedido de 6tn de asfalto con
   Asfalto CA30 en 0 → corregido a 5.5tn → Asfalto CA30 pasó de 0 a 22.5kg
   fantasma. **Sin corregir, pendiente de decisión de Federico** sobre
   cómo tratarlo (¿la corrección debería leer el histórico real de
   movimientos del pedido en vez de recalcular desde la fórmula?).
2. **🟡 Menor — Cancelar pedido pisa las `observaciones` originales**:
   `cancelar_pedido()` hace `update ... set observaciones = p_motivo`,
   reemplazando cualquier nota previa del pedido (ej. instrucciones de
   entrega) por el motivo de cancelación — el motivo ya queda guardado
   también en `plantas_pedidos_historial.motivo` (con auditoría completa),
   así que pisar `observaciones` es innecesario y pierde información.
3. **🟡 Menor — mensaje de validación de "Cancelar pedido" mal ubicado**:
   al cancelar sin motivo, el error ("cancelarPedido: el motivo es
   obligatorio" — string crudo con el nombre de la función interna) se
   muestra en un banner arriba de la página, no dentro del modal — con el
   modal abierto tapa esa zona, un usuario real podría no verlo.

## ✅ Fix de los 2 hallazgos de arriba — 2026-09-06, APLICADO y VERIFICADO

Decisión de Federico sobre los 3 hallazgos de la sección de arriba:

1. **Corregir despacho — stock fantasma**: `plantas_descontar_stock_despacho()`
   (migración 22, `supabase/migrations/22_fix_corregir_despacho_y_cancelar_pedido.sql`)
   ahora calcula el ajuste contra el **historial real** de
   `plantas_stock_movimientos` de ese pedido+material (`sum` de los tipos
   `egreso_despacho`/`recalculo_despacho`, que son los únicos que esta misma
   función genera) en vez de recalcular desde la fórmula asumiendo consumo
   completo. Efecto colateral bueno: la función queda **idempotente** —
   correcciones repetidas sobre el mismo pedido siempre convergen al valor
   correcto, sin importar cuántas veces se corrija ni si algún material tocó
   el piso de 0 en el medio. El primer llamado (desde `finalizar_despacho`,
   sin movimientos previos) se comporta idéntico a antes — no cambia nada
   del flujo normal de despacho, solo el de corrección.
   **Reproducido el bug original y verificado el fix en vivo**: mismo
   escenario (pedido de 6tn CAC D19 con Asfalto CA30 en 0, corregido a
   5.5tn) — Asfalto CA30 se mantuvo en 0 (antes pasaba a 22.5kg fantasma),
   Piedra 6/20 y Arena 0/6 siguieron acreditándose bien (+235kg/+265kg,
   igual que en el caso sin bug).
2. **Cancelar pedido — observaciones**: `cancelar_pedido()` (misma
   migración 22) ahora concatena `"MOTIVO CANCELACIÓN: <motivo> | OBS:
   <observación original>"` en vez de pisarla — verificado en vivo con un
   pedido con observación previa, el resultado final coincide exacto con
   el formato pedido.
3. **Modal de cancelación — mensaje mal ubicado**: nuevo ref
   `errorCancelacion` en `usePedidos.js` (propio del modal, no comparte el
   `error` genérico de la vista) + bloque de error dentro del `<form>` del
   modal en `PedidosView.vue`, mismo estilo que ya usa el modal de
   Postergar. De paso, `pedidos.service.js#cancelarPedido()` dejó de tirar
   el string crudo `"cancelarPedido: el motivo es obligatorio"` (nombre de
   función filtrado) por uno legible. Verificado en vivo: al cancelar sin
   motivo, el mensaje aparece dentro del modal, arriba del textarea.

**Archivos**: `supabase/migrations/22_fix_corregir_despacho_y_cancelar_pedido.sql`
(aplicada), `src/modules/pedidos/composables/usePedidos.js`,
`src/modules/pedidos/services/pedidos.service.js`, `src/views/PedidosView.vue`.
Build verificado (`npm run build` limpio) y probado en vivo con datos QA
borrados íntegramente al terminar (stock repuesto exacto).

## ✅ Paso 3 — RLS fina por rol/obra (tarea P0.2) — 2026-09-06, APLICADO y VERIFICADO

Antes de escribir política alguna, auditoría en vivo contra `pg_policies`/
`pg_proc` de producción (no contra lo que decían `pending.md`/`modules-
status.md`, que estaban desactualizados en esto también) — bien menos
gap del que se creía:

- **Ya estaba resuelto**: `plantas_pedidos` tiene SELECT filtrado por obra
  desde la migración 17 (2026-08-31) — `ver_todas_obras`/`obra_ids`/
  `ver_ventas` de `plantas_usuarios_roles`. Los 22 usuarios reales tienen
  `ver_todas_obras=true` hoy, así que el filtro no restringe a nadie
  todavía (decisión de Federico, "evitar bloqueos iniciales"). Toda la
  escritura de Pedidos/Báscula/Stock ya pasa por RPC `SECURITY DEFINER`
  (bypassea RLS) — confirmado que no hay policy de INSERT/UPDATE/DELETE
  para `authenticated` en esas tablas antes de tocar nada.
- **Gaps reales encontrados** (los cerró la migración 23,
  `supabase/migrations/23_rls_fina_rol_obra.sql`):
  1. `plantas_cargas_asfalto`/`hormigon` y `plantas_pedidos_historial`
     seguían con SELECT sin filtrar (`using(true)`) — se extendió el mismo
     criterio de obra que ya usa `plantas_pedidos`, vía función nueva
     `plantas_puede_ver_obra(obra_id, tipo_pedido)` (no duplica la lógica).
  2. `plantas_vales`/`plantas_ingresos` (detalle de Báscula) y
     `plantas_stock`/`plantas_stock_movimientos` eran legibles por
     cualquier autenticado aunque esas pantallas ni aparecen en el menú de
     `encargado`/`supervisor`/`plantista_hormigon`
     (`PERMISOS_POR_ROL`, `src/stores/auth.store.js`) — se restringió por
     rol con 2 funciones nuevas: `plantas_puede_ver_bascula()`
     (`admin`/`plantista`/`balancero`) y `plantas_puede_ver_stock()`
     (esos 3 + `gerencia`).
  3. `plantas_formulas`/`materiales`/`patentes`/`proveedores`/`choferes`/
     `encargados` aceptaban INSERT/UPDATE/DELETE de cualquier autenticado
     — confirmado en código (`maestros.service.js`/`formulas.service.js`
     escriben directo, sin RPC, a diferencia de Pedidos/Báscula). Riesgo
     real más alto en fórmulas/materiales (afectan el cálculo de consumo/
     descuento de stock). Escritura restringida a `admin`/`plantista` en
     los 6 catálogos (decisión de Federico: mismo criterio para todos, no
     diferenciar balancero en patentes/choferes) — lectura sin cambios
     (varios roles la necesitan para dropdowns).
- **plantas_pedidos y plantas_usuarios_roles: sin cambios**, ya estaban
  bien.

**Hallazgo colateral, no corregido a propósito (no fue pedido)**:
`postergar_pedido()` es la única RPC de Pedidos **sin ningún chequeo de
rol** — cualquier usuario autenticado puede postergar un pedido si tiene la
pantalla visible, a diferencia de crear/confirmar/cancelar/despachar/
corregir/archivar que sí validan `plantas_rol_actual()`. Bajo impacto (solo
cambia fecha/motivo, no toca stock ni cierra nada), pero es una
inconsistencia real frente al resto de las transiciones de estado. Queda
documentado en la matriz nueva de "Permisos por rol" (ver abajo) con una
nota visible en rojo — decisión de si corregirlo queda para Federico.

**Regresión verificada**: build limpio, smoke test en vivo como admin
(único rol con sesión real disponible) en Stock/Báscula — sin cambios, todo
sigue andando. No fue posible loguearse como los otros 6 roles reales para
probarlos en vivo (no se piden ni escriben contraseñas ajenas) — la
verificación de esos roles es por lectura de código (cada policy/RPC
citada arriba, trazable 1 a 1 contra `pg_policies`/`pg_proc`).

**Matriz real de permisos — `UsuariosPermisosView.vue`** (pedido de
Federico durante esta misma sesión: "permisos por rol es solo para el
admin, hacelo bien detallado y real"): la tab "Permisos por rol" (ya
admin-only desde antes, sin cambios en el guard) pasó de mostrar solo el
resumen de `PERMISOS_POR_ROL` (qué pestañas/botones oculta la UI) a una
matriz nueva arriba, por acción × los 7 roles, citando la RPC o policy de
RLS real que la hace cumplir (Pedidos, Báscula, Stock, Maestros, Usuarios)
— incluye la nota del hallazgo de `postergar_pedido` de arriba. El resumen
de `PERMISOS_POR_ROL` se conserva debajo, aclarado como "solo UI, no es
control de seguridad por sí solo". Es una matriz hardcodeada a mano (no se
puede introspectar RPC/RLS desde el frontend en runtime) — **si se cambia
el rol permitido de alguna RPC o policy a futuro, hay que actualizar
`MATRIZ_REAL_PERMISOS` en el archivo a mano, no se sincroniza sola**.

**Archivos**: `supabase/migrations/23_rls_fina_rol_obra.sql` (aplicada),
`src/views/UsuariosPermisosView.vue`. Build verificado.

## 🔴 Regresión de RLS: timeout en Stock → Historial de ingresos — 2026-09-06, ENCONTRADO y CORREGIDO

Durante el smoke-test post-migración-23, "Historial de ingresos" tiró
**"canceling statement due to statement timeout"** al abrir la tab —
regresión real introducida por la propia migración 23, no un bug
preexistente.

**Causa**: `plantas_v_stock_movimientos_viva` lee `plantas_stock_movimientos`
dos veces sin materializar — una en la CTE "migrados", otra dentro de un
`NOT EXISTS` correlado fila por fila contra los ~700+ elementos del array
`vt_m9` de `kv_store` (anti-join legado). Al agregarle RLS a
`plantas_stock_movimientos` (`plantas_puede_ver_stock()`, función
`SECURITY DEFINER` opaca para el planner), Postgres puede elegir un plan
que reevalúe esa función una vez por cada fila del legado en vez de una
sola vez — **exactamente la misma causa raíz, en el mismo tipo de vista
puente, que ya se había encontrado y resuelto en `plantas_v_bascula_viva`
el 2026-09-04** (esa vista no se vio afectada ahora porque ya materializaba
`plantas_vales`/`plantas_ingresos` desde ese fix anterior). Confirmado con
`EXPLAIN ANALYZE` como rol `authenticated`: 144ms con un plan hash decente,
pero el plan es inestable — el timeout real en vivo sí ocurrió una vez.

**Fix** (`supabase/migrations/25_fix_timeout_vista_stock_viva.sql`): CTE
`psm_visible AS MATERIALIZED` que lee `plantas_stock_movimientos` (con su
RLS) una sola vez; las dos CTEs de la vista pasan a leer de ahí. Verificado
con `EXPLAIN ANALYZE`: bajó a 19.8ms, plan ahora usa "CTE Scan on
psm_visible" (evaluado una vez, reusado) en vez de dos `Seq Scan ...
Filter: plantas_puede_ver_stock()` separados. Reprobado en vivo en el
navegador (recargado varias veces) sin que vuelva a aparecer el timeout.

**Chequeado y descartado el mismo riesgo en otras vistas**:
`plantas_v_despachos_camion` (Dashboard, ahora con RLS de
`plantas_puede_ver_obra(obra_id)` en 2 de sus 3 fuentes) es un `UNION ALL`
simple de 3 escaneos directos, sin anti-join/subquery correlada contra el
legado — no le aplica este patrón de riesgo, no necesitó cambios.

**Lección para la migración final (Paso 4)**: cualquier vista puente nueva
o script de migración que compare "¿ya migrado?" con un `NOT EXISTS`/anti-
join contra una tabla que ahora tiene RLS debe materializar esa lectura
primero — no asumir que Postgres siempre va a elegir el plan barato.

## ✅ postergar_pedido restringido a admin/plantista — 2026-09-06, APLICADO

Hallazgo de la auditoría de RLS de arriba: `postergar_pedido()` era la
única RPC de transición de estado de Pedidos sin ningún chequeo de rol.
Decisión de Federico: restringirla a `admin`/`plantista`, mismo criterio
que `confirmar_pedido()`/`archivar_pedido()`. Aplicado en
`supabase/migrations/24_postergar_pedido_restringido.sql`. No hizo falta
tocar el frontend — el botón "Postergar" ya se muestra solo por estado
(igual que "Confirmar"/"Despachar"), el chequeo real vive en el RPC, mismo
patrón que el resto de las transiciones.

## ✅ Verificación RLS Fórmulas/Maestros + smoke-test de flujos restantes — 2026-09-06, VERIFICADO

Cierre del Paso 3 al 100% + los flujos que habían quedado sin probar de la
prueba de flujo total:

- **Fórmulas**: editar CAC D19 como admin — funciona. Verificado sin
  ambigüedad cambiando un valor real (Piedra 6/20: 47 → 47.1 → confirmado
  en DB → revertido a 47).
- **Materiales**: editar ADD PLAS como admin (guardado sin cambios) —
  funciona, sin error.
- **Stock — Ingreso manual**: Filler +1tn, verificado en DB (25422 →
  26422 kg), revertido.
- **Stock — Salida manual**: Fuel Oil −1tn, verificado en DB (23700 →
  22700 kg), revertido.
- **Stock — Relevamiento mensual**: modal pre-carga el stock actual de
  cada material; guardado sin cambiar nada → 0 movimientos `ajuste`
  creados (verificado en DB) — el guard `saveStockGuard` solo audita
  diferencias reales, comportamiento correcto.
- **Simulador**: 50tn CAC D19 → cálculo de impacto exacto (Arena 0/6
  −26.5tn, Asfalto CA30 −2.25tn → "INSUFICIENTE" porque está en 0, Piedra
  6/20 −23.5tn) — 100% client-side, sin persistencia, nada que limpiar.
- **Plan Semanal**: calendario semanal, KPIs por obra y matriz de días
  cargan sin errores.

Todos los datos de prueba borrados/revertidos, verificado por SQL. Build
limpio (sin cambios de frontend en esta pasada, solo las 2 migraciones de
arriba).

## 📋 Decisiones de Federico — cierre de pendientes previo al Paso 4 (2026-09-06)

- **Módulo de Auditoría**: queda para DESPUÉS del corte — la trazabilidad
  ya existe en la DB (`plantas_pedidos_historial`, `plantas_stock_movimientos`
  con `responsable_email`, etc.), solo falta la pantalla visual y no es
  bloqueante para salir a producción.
- **Módulo de Backup**: NO se va a desarrollar — Supabase ya maneja
  backups automáticos de infraestructura. El día del corte se hace una
  exportación manual directa desde el panel de Supabase.
- **3 usuarios sin nombre** (`angel.moreira`, `balanza`, `juan.heinrich`):
  se dejan como están — se completan en `flota_usuarios_email` más
  adelante, post-corte.
- **Catálogo Choferes**: se deja como está — no se tocan catálogos
  históricos a horas de la migración final.
- **Exports faltantes** (Pedidos sin Excel; Despachos con solo "Informe
  mensual" de los 6 botones del legado): quedan postergados como mejora
  post-corte — los 5 exports ya probados (Stock×3, Informe mensual,
  Báscula) son suficientes para el corte.

## ✅ Paso 4 — script de migración final + dry-run — 2026-09-06, VERIFICADO (no ejecutado en real)

Preparación completa para la migración final del corte, sin tocar
producción todavía (solo lectura + una transacción con `rollback` al
final).

**1) Auditoría del delta desde el 01/09** — nuevo script
`supabase/scripts/auditoria_delta_desde_01_09.sql` (mismo patrón que
`auditoria_historico_vs_legado.sql`, invertido: `fecha >= '2026-09-01'`).
Resultado de la corrida 2026-09-06: **4 pedidos**, **18 eventos de
historial**, **4 cargas de hormigón** (detalle de por qué el dry-run
inserta 5, ver más abajo), **20 vales de asfalto**, **0 egreso_arido**,
**3 ingresos de áridos** (vale + `plantas_ingresos` + su reflejo en
`plantas_stock_movimientos`), **1 relevamiento nuevo sin reconciliar**
(2026-09-03). **Chequeo crítico de colisión de `numero_vale`: 0 filas** —
el rango real pendiente (9994-10013) cayó justo donde la renumeración de
vales sintéticos de hoy mismo dejó libre, confirmando que esa migración
(ver más arriba) no era solo preventiva, era un requisito real para poder
migrar este delta sin chocar contra el `UNIQUE`.

**2) Script de migración final** — `supabase/scripts/migracion_final_corte.sql`,
reutiliza tal cual la lógica de inserción de `migracion_historial_v2.sql`
(secciones 5-8: Pedidos+Historial, Cargas hormigón, Vales+Ingresos, Stock
movimientos) — ya es idempotente por diseño (`not exists` contra el id
nativo del legado en cada INSERT, sin filtro de fecha), así que no hizo
falta escribir lógica nueva, solo volver a correr el mismo patrón: procesa
TODO `kv_store` de nuevo y solo inserta lo que todavía no está. Esto
significa que es seguro correrlo más de una vez si el legado sigue vivo
entre el dry-run y el corte real — no duplica nada.

**Alcance deliberadamente excluido**: `plantas_stock` (balance final). La
migración original del 01/09 lo seteó directo desde `vt_s9` como bootstrap
único — repetir eso ahora sobreescribiría el ledger real que el sistema
nuevo viene llevando de forma independiente (despachos, báscula, manual)
desde esa fecha. **Queda como decisión de Federico para el día del corte**
(ver `supabase/scripts/CHECKLIST_CORTE_FINAL.md` punto 3): confiar en el
ledger nuevo tal cual, o cargar un relevamiento físico fresco (vía "Stock →
Relevamiento mensual", que ya audita el ajuste correctamente).

**3) Dry-run ejecutado contra producción** (transacción completa,
terminada en `rollback`, conteos verificados exactos al valor previo
después): `total_pedidos` 184→188 (+4), `total_historial` 543→561 (+18),
`total_cargas_hormigon` 114→119 (**+5**, no +4 — investigado: uno de los 4
pedidos nuevos es de hormigón y trae su propio camión, se resuelve
correctamente dentro de la misma transacción porque el pedido recién
insertado ya es visible para el INSERT de cargas que sigue — no es un bug,
confirma que el script es transaccionalmente consistente), `total_vales`
885→908 (+23 = 20 asfalto + 3 ingreso_arido), `total_ingresos` 500→503
(+3), `total_stock_movimientos` 786→789 (+3). `setval()` verificado:
`secuencia_actual` quedó igual a `max_vale_real` (10016). **3 chequeos de
integridad post-inserción: 0 duplicados de `numero_vale`, 0 pedidos con
`id_legado` duplicado, 0 ingresos huérfanos.**

**4) Checklist técnico del corte** — `supabase/scripts/CHECKLIST_CORTE_FINAL.md`,
9 secciones en orden: re-auditar el delta en vivo justo antes (el legado
sigue vivo, el delta real del día del corte va a ser mayor a lo medido
hoy), dry-run de nuevo, decisión de Federico sobre el balance de stock,
corrida real (`rollback` → `commit`), `npx vercel --prod` (manual, como
siempre), cambio de DNS de `produccion.vialtec.app` (lo tiene que hacer
Federico, Claude no tiene acceso al proveedor de DNS), verificación
post-corte, dar de baja el legado, y **recién ahí** resolver la RLS abierta
de `kv_store` (sin riesgo de romper su escritura en vivo una vez apagado).

**Archivos**: `supabase/scripts/auditoria_delta_desde_01_09.sql`,
`supabase/scripts/migracion_final_corte.sql`,
`supabase/scripts/CHECKLIST_CORTE_FINAL.md`. Ninguno tocó producción — el
único cambio real de datos en esta sesión fue el dry-run, revertido con
`rollback` y verificado.

## ✅ Báscula: impresión round 3 + Vale para egreso de áridos — 2026-09-04 (madrugada), APLICADO y VERIFICADO

Después del round 2 (más abajo), Federico sacó el filtro de fecha "hoy" por
default, sacó el botón "Filtrar" (filtro en vivo con `@change`), pidió el
acumulado en tabla/Excel (ya resuelto con `acumulado_dia_tn` de la vista) y
reportó una FOTO: el diálogo de impresión de la compu ahora decía
correctamente "1 página" pero la vista previa salía en BLANCO. 3 cosas
resueltas en esta vuelta:

1. **Hoja en blanco al imprimir — bug real, causado por el propio fix del
   round 2**: el fix de "6 páginas → 1" agregó
   `body > div:has(.imprimible) * { visibility: hidden }` en `main.css`, y
   esa regla tiene MÁS especificidad CSS que la regla que sigue, la que
   hace visible a `.imprimible` (`.imprimible, .imprimible * { visibility:
   visible }`) — `:has()` cuenta como clase, más `body` y `div` como 2
   selectores de elemento de más, ganan por especificidad aunque aparezcan
   ANTES en el archivo (la especificidad manda sobre el orden de
   declaración). Resultado: `.imprimible` quedaba también oculto por la
   regla que se suponía debía ocultar todo LO DEMÁS. Fix: `!important` en
   la regla que hace visible a `.imprimible` — gana siempre, sin depender
   de la especificidad de la otra. Verificado con una simulación segura
   (inyectar las mismas reglas SIN el wrapper `@media print`, para no
   disparar el diálogo nativo de impresión que bloquea la automatización
   del navegador): antes de este fix `.imprimible` computaba
   `visibility: hidden`; después, `visibility: visible` con el contenido
   real renderizado.

2. **Vale de pesaje también para egreso de áridos ("Salida de áridos")** —
   pedido explícito de Federico: antes solo asfalto tenía botón de
   impresión (regla vieja, ver comentario removido en `useBascula.js`).
   Ahora el historial de Báscula muestra un botón "Vale" también en filas
   `egreso_arido` (sigue sin "Remito": ese formato es específico del flujo
   pedido/obra de asfalto — acumulado por pedido, rango de vales
   correlativos —, egreso de áridos no tiene pedido asociado). El
   imprimible (`ValeImprimible.vue`, modo "vale") muestra "Material: X" en
   vez de "Mezcla: X" cuando el vale no es de asfalto (usa `vale.material`,
   ya resuelto por `plantas_v_bascula_viva`); Obra ya funcionaba genérico
   (resuelve por `vale.obra_id`, no específico de asfalto). La línea
   "Acumulado" queda en "—" para egreso: no hay un concepto de acumulado
   del día definido para egreso todavía (`obtenerAcumuladoHastaFecha()`
   solo consulta asfalto) — se evitó llamarla para egreso en vez de dejar
   que devuelva 0 engañoso; mismo criterio "—" que ya usa la tabla/Excel
   del historial para esas filas. Ingreso de áridos sigue sin impresión
   (no lo pidió Federico). Verificado en vivo contra un vale real de
   egreso (Fuel Oil, obra "Predio Vialtec"): Material y Obra correctos,
   Acumulado en "—", sin errores.

Archivos: `src/assets/main.css`, `src/views/BasculaView.vue`,
`src/modules/bascula/composables/useBascula.js`,
`src/modules/bascula/components/ValeImprimible.vue`.

### Nota: "Patente" con texto raro en 2 vales históricos de egreso — NO es un bug, decisión de Federico

Al verificar el punto 2 de arriba contra datos reales, aparecieron 2 vales
(de solo 3 `egreso_arido` que existen en todo el sistema) con
`plantas_vales.patente = 'CONSUMO JUL-24-AGOSTO 26'` / `'CONSUMO MAY-JUN 26'`
— ambos de material Fuel Oil, sin vehículo real (consumo interno de
combustible, no una entrega con camión). Parecía un bug pero es dato real
cargado a propósito en su momento. Le pregunté a Federico qué hacer y
confirmó: **dejar el campo tal cual** (no reescribir el dato histórico, no
ocultar la fila) — el campo Patente ya es opcional para `egreso_arido`
(`guardarPesada()` solo exige material + obra_id) y el imprimible ya cae a
"—" cuando está vacío (`vale.patente || '—'`, `ValeImprimible.vue`). Sin
cambio de código: el comportamiento pedido ya es el que había. Si un
operador no carga patente en un egreso a futuro, sale "Patente: —".

## ✅ Báscula: impresión round 2 — 2026-09-04 (noche), APLICADO y VERIFICADO

Federico volvió a probar después del fix anterior y reportó 3 cosas más:
timeout seguía sin confirmar del todo, vista previa "apiñada", el diálogo
de impresión mostraba 6 páginas para un vale (debía ser 1), y — nueva —
obra/mezcla vacías al imprimir. Las 4 investigadas y resueltas:

1. **Timeout**: re-verificado con el mismo filtro amplio (ago-sept) que
   antes tardaba/fallaba — ahora carga rápido, sin error. El fix de la
   ronda anterior (`pp_visible materialized` + piso de fecha) sigue
   funcionando.

2. **"6 páginas" al imprimir un vale — bug real, CAUSA RAÍZ distinta a lo
   que se pensaba**: `body * { visibility: hidden }` en `main.css` NO saca
   los elementos del flujo del documento — `visibility:hidden` sigue
   ocupando su alto de layout normal (a diferencia de `display:none`). Con
   la SPA completa debajo del modal (sidebar, filtros, la tabla de
   historial con decenas/cientos de filas) invisible pero todavía "midiendo"
   su alto real, el motor de impresión de Chrome paginaba ese alto
   acumulado completo — de ahí las páginas de más, todas en blanco salvo
   la primera. Fix en `src/assets/main.css` + `BasculaView.vue` +
   `DespachosView.vue`: `#app` (la SPA entera) pasa a `display: none` en
   `@media print` (sí saca del flujo, alto cero); los 4 modales de
   impresión existentes (Vale/Remito de Báscula, Remito/Vale de Despachos)
   se movieron a `<Teleport to="body">` para vivir FUERA de `#app` y no
   heredar ese `display:none` — dentro de ese modal teleportado (chico, del
   tamaño del viewport) se mantiene el mismo criterio `visibility` de antes
   pero acotado a él (`body > div:has(.imprimible) *`), ya no a toda la SPA.
   Verificado en vivo: `.imprimible` confirmado fuera de `#app`
   (`app.contains(imprimible) === false`), regla CSS compilada correcta.

3. **Vista previa "apiñada" — bug real de UX**: `VModal.vue` tiene
   `max-w-lg` (512px) fijo, pensado para formularios — el vale (grid de 2
   columnas para una hoja A4 landscape de 297mm) quedaba apretado ahí.
   `VModal.vue` suma un prop `size` opcional (`'md'` default = sin cambios
   para el resto de la app, `'xl'` = `max-w-4xl`) — los 4 modales de
   impresión de arriba pasan a `size="xl"`. Verificado en vivo: se ve
   ancho y prolijo, sin apiñar.

4. **Obra/mezcla vacías al imprimir — regresión real introducida en la
   ronda anterior de esta misma sesión**: al cambiar
   `fetchPedidosAsfaltoParaPesada()` a filtrar solo `estado='confirmado'`
   (pedido explícito de Federico), la función de impresión
   (`abrirImpresion()` en `useBascula.js`) seguía resolviendo obra/mezcla
   contra esa MISMA lista acotada (`pedidosPorId`) — un vale de un pedido
   YA despachado (la inmensa mayoría de los que se imprimen, son
   históricos) dejó de encontrar su pedido ahí, mostrando "Obra: —" /
   "Mezcla: —". Fix: si el pedido no está en esa lista acotada, se trae
   puntual por id (`getPedido()`, ya existía en `pedidos.service.js`) — no
   bloquea la impresión si falla. Verificado en vivo con el mismo vale que
   antes daba vacío: ahora muestra "Obra: AUTOVIA MERCOSUR" / "Mezcla: CAC
   D19 (AUTOVIA)" correctamente, en Vale y en Remito.

Build limpio en cada paso, sin errores de consola.

## ✅ Báscula: timeout + impresión — 2026-09-04 (noche), APLICADO y VERIFICADO

Federico reportó 2 problemas reales usando Báscula después del paquete de la
tarde: (1) "canceling statement due to statement timeout" filtrando por
fecha, (2) varios vales de asfalto sin opción de imprimir, (3) al imprimir
salen más copias/hojas de las esperadas (vale=1 hoja con 2 copias, remito=2
hojas con 1 copia c/u).

**1) Timeout — REPRODUCIDO y CORREGIDO.** Causa real: `plantas_pedidos`
tiene RLS por fila (subplan correlado contra `plantas_usuarios_roles`) y el
planner de Postgres, para ciertas combinaciones de filtro, elegía un plan
que la reevaluaba una vez POR CADA fila externa en vez de una sola vez —
reproducido en vivo con un filtro de fecha amplio (ago-sept): 1.13s medido
en `EXPLAIN ANALYZE` como el rol `authenticated` real (mismo rol que usa la
app vía PostgREST, que tiene `statement_timeout=8s` — confirmado con
`select rolconfig from pg_roles`), contra ~13-58ms en pruebas anteriores
"en caliente". Fix en `plantas_v_bascula_viva`:
- `plantas_pedidos` se resuelve UNA sola vez vía un nuevo CTE `pp_visible
  as materialized` (fuerza que Postgres nunca la reevalúe por fila, sin
  importar qué plan elija después) — esto es lo que bajó 1.13s a 68ms.
- Piso de fecha (`(v->>'fecha')::date >= '2026-09-01'`) en las 3 ramas
  legado: antes de esa fecha está TODO migrado (0 faltantes, auditado el
  mismo día), así que no tiene sentido escanear/procesar esos ítems del
  legado — reduce drásticamente el volumen para cualquier filtro que
  incluya histórico (el caso más común).
- `plantas_vales` de paso pasa a leerse una sola vez (`pv_base as
  materialized`, antes 3 lecturas separadas).
- Re-verificado sin filtro de fecha (rango completo): 62ms. Vista de Stock
  revisada también (`plantas_v_stock_movimientos_viva`, no tiene join
  contra `plantas_pedidos`, sin el mismo riesgo — 35ms, sin cambios
  necesarios). `ANALYZE` corrido sobre las tablas involucradas de paso.

**2) Vales sin opción de imprimir — NO es un bug, es diseño intencional**
(pedido explícito de Federico en la tanda anterior): esas filas tienen el
badge "Legado" — todavía viven solo en el sistema legado, no tienen fila
real en `plantas_vales` detrás, así que no hay nada que un RPC de
"imprimir"/"corregir" pueda operar. Quedan de solo lectura hasta que
lleguen a migrarse (fecha de corte pendiente, ver sección de abajo).

**3) Copias/hojas de más al imprimir — bug real, CORREGIDO.** Medido con el
mismo harness de sesiones anteriores (clonar `.imprimible` a un contenedor
297×210mm real, sin arriesgar el diálogo nativo de impresión):
- Modo "Vale": 794px de contenido contra 793.7px disponibles — correcto,
  sin cambios (1 hoja, 2 copias lado a lado, como se diseñó).
- Modo "Remito": **2027px de contenido total contra 793.7px disponibles**
  — cada copia (~1013px) desbordaba largamente la única hoja que tenía
  asignada (210mm), así que cada una se partía en 2 hojas físicas → 4
  hojas en vez de las 2 esperadas. Causa: el remito se diseñó originalmente
  pensando en una hoja A4 vertical (297mm de alto), pero la corrección del
  2026-09-03 noche unificó `@page` a un solo landscape global (210mm de
  alto) para toda la app — el remito nunca se reajustó a esa nueva altura
  disponible. Fix en `ValeImprimible.vue` (modo remito): paddings/márgenes
  reducidos, filas en blanco de la tabla bajadas de 4 a 2 — cada copia mide
  ahora 726px, entra cómodo en los 793.7px de una sola hoja. Vale sigue
  intacto.

Build limpio, sin errores de consola, verificado en vivo (Báscula, filtro
amplio + imprimir Vale/Remito de un vale real).

## ✅ Paquete de correcciones 2026-09-04 (tarde): Báscula, Maestros, Pedidos, Home — APLICADO y VERIFICADO

Pedido de Federico, 4 tareas en un mismo lote, todas verificadas en vivo en
el navegador (sesión real de Federico) al cierre:

1. **Báscula — selector "Vale Asfalto"**:
   - `fetchPedidosAsfaltoParaPesada()` (`bascula.service.js`) ahora filtra
     `estado = 'confirmado'` únicamente (antes `in (confirmado, despachado)`,
     decisión del 2026-08-28 — **override explícito** de Federico esta
     sesión, no un bug encontrado).
   - Bug real corregido: "Obra #null" en la gran mayoría de las opciones —
     causa real, una venta externa (`tipo_pedido='venta'`) nunca tiene
     `obra_id` por diseño, el selector no tenía fallback a `cliente_externo`.
     Nuevo helper `nombreDestinoPedido()` en `useBascula.js` (mismo patrón
     ya usado en `PlanSemanalView.vue` desde el 2026-09-03). Verificado en
     vivo: "MUNICIPALIDAD DE PILAR — 40 tn (confirmado)" en vez de "Obra
     #null", y el caso huérfano real (sin `flota_obras` equivalente) muestra
     "Obra sin asignar".
2. **Maestros**:
   - Pestaña "Choferes" poblada (antes vacía): 19 choferes únicos extraídos
     de `plantas_patentes.chofer_habitual` (Camiones propios), dedupe
     case-insensitive (1 caso real: "Jara Esteban"/"JARA ESTEBAN"),
     normalizados a mayúsculas. Población única vía SQL (no es un sync
     seguido — si se necesita en vivo hacia adelante, pedirlo aparte).
   - Tabs renombradas: "Vehículos propios" → "Camiones propios", "Vehículos
     externos" → "Camiones externos" (mismo catálogo/service, solo label).
3. **Pedidos — rediseño en cards** (réplica exacta del legado, relevado en
   vivo contra `produccion.vialtec.app` con Federico logueado — Etapa 1/3
   del relevamiento ya tenían el detalle, se re-confirmó en vivo esta
   sesión):
   - Se sacaron los tabs Asfalto/Hormigón — vista única, agrupada por
     sección con contador ("Hormigón — N pedidos" / "Asfalto — N pedidos",
     ese orden). `usePedidos.js#pedidosPorTipo` nuevo.
   - `fetchTodosLosPedidos()` nuevo en `pedidos.service.js` (reemplaza
     `fetchPedidos()` paginado para esta vista) — el legado tampoco pagina
     Pedidos, se apoya en semana-en-curso/filtros para acotar volumen; sigue
     usando `fetchPaginado()` por debajo (regla de paginación intacta).
   - `PedidoCard.vue` nuevo (`src/modules/pedidos/components/`): badge +
     destino + fórmula/cantidad (+ "→ real: X" si despachado) + fila
     📅fecha/👤encargado/🕐creación/"Ver historial" + caja 📝observaciones +
     caja ⚠motivo (pueden convivir las dos, confirmado en vivo) + acciones
     por estado (Confirmar / ↑Despachar / Editar / Postergar / ✕ / Archivar).
   - `src/modules/pedidos/estados.js` nuevo: constantes de estado
     compartidas entre `PedidosView.vue` y `PedidoCard.vue` (antes
     duplicadas inline en la vista).
4. **Home — "Panel de control"** (réplica del legado, relevado en vivo en la
   misma sesión, pedido agregado por Federico a mitad de la tarea): 5 KPI
   semanales (Pedidos activos/Confirmados/Despachos esta semana/Ajustados/
   Críticos — franja de color por card), "Consumo de material" (selector +
   últimas 8 semanas, kg reales despachados vía fórmula, nuevo
   `dashboard.service.js#fetchConsumoSemanalPorMaterial()`), "Próximos
   despachos" (confirmados ordenados por fecha, badge Vencido/Hoy),
   "Stock actual de insumos" (grid, reusa `fetchStockActual()`). Reemplaza
   el bloque "KPIs del mes" que tenía antes Home — las secciones "Analítica
   de proveedores" y "Historial detallado de despachos por camión" (valor
   agregado propio de v2, el legado no las tiene) se mantuvieron sin
   cambios debajo, no se pidió sacarlas.
   - `src/modules/dashboard/services/dashboard.service.js` +
     `src/modules/dashboard/composables/useDashboardHome.js` nuevos.
   - **Ajuste 2026-09-04 (mismo día, pedido de seguimiento)**: se sacaron
     por completo "Analítica de proveedores" y "Historial detallado de
     despachos por camión" de Home — quedaba pidiendo "estrictamente un
     panel de resumen, sin tablas ni secciones analíticas extensas". No se
     perdió funcionalidad real: la misma analítica de proveedores ya vive
     en Stock → tab "Analítica de proveedores" (2026-09-02), y el detalle
     de despachos por camión en Despachos → "🚛 Ver detalle de cargas" por
     pedido. Bundle de Home bajó de 19.3kB a 13.5kB. Verificado en vivo:
     la página termina justo después de "Stock actual de insumos", sin
     rastro de las secciones sacadas, sin errores de consola.

Build limpio en cada paso, sin errores de consola verificados en vivo en
Báscula/Home/Maestros/Pedidos (histórico completo, ~67 pedidos hormigón
renderizados sin problema).

## ✅ Vistas puente Báscula/Stock (kv_store vivo + plantas_*) — 2026-09-04, APLICADO y VERIFICADO

Pedido explícito de Federico tras el hallazgo de Báscula 1-4 sept (ver
sección de abajo): que la UI nueva lea en vivo lo que el legado sigue
cargando en paralelo, SIN trigger de sincronización (evaluado y descartado
por el riesgo de romper la escritura del legado — ver conversación) y sin
tocar ninguna tabla existente. Implementado como 2 **vistas SQL de solo
lectura** (`plantas_v_bascula_viva`, `plantas_v_stock_movimientos_viva`),
`UNION ALL` de la tabla real (`plantas_vales`/`plantas_stock_movimientos`)
con lo que todavía solo vive en `kv_store` (anti-join, mismo criterio de
idempotencia que `migracion_historial_v2.sql`) — código completo y
documentado en `supabase/scripts/vistas_puente_legado_bascula_stock.sql`.

**🔴 Hallazgo real descubierto al aplicar** (no un bug de la vista, preexistente
de la migración del 1/9): los 500 `ingreso_arido` migrados recibieron
`numero_vale` SINTÉTICO (`nextval`) en el rango **9994-10493** porque el
legado no los numera. El asfalto real del legado seguía en 9993 al migrar,
pero **siguió avanzando en paralelo** y ya entró en ese mismo rango (hoy va
por 10013) — comparar "¿ya migrado?" por `numero_vale` (como hace
`migracion_historial_v2.sql`) da falsos positivos ahí. Se resolvió
comparando por el id nativo del legado (`datos_legados ->> 'id'`) en la
vista. **Pendiente de decisión de Federico, no resuelto todavía**: el día
que se quiera migrar de verdad ese asfalto real (9994 en adelante) con su
`numero_vale` real, va a chocar contra el `UNIQUE` de `numero_vale` —
hace falta decidir cómo renumerar antes de encarar esa migración. Visible
también en la UI como un efecto colateral menor: hay 20 pares de filas que
comparten el mismo "N° Vale" en pantalla (una real, una del legado) —
aceptado, ambas están marcadas "Legado"/no, no genera confusión real.

**Verificado end-to-end**: conteo 1-4 sept da **24/23** (igual que la
auditoría manual), confirmado tanto por SQL directo como corriendo como el
rol `authenticated` real de la app (importante: como `anon` sin login da un
resultado distinto y roto — el RLS de `plantas_vales` bloquea a `anon`, así
que el anti-join "ve" todo como no-migrado — no aplica a la app real, que
siempre corre logueada, pero quedó documentado en el script). **Confirmado
visualmente en el navegador** con la sesión real de Federico: Báscula →
filtro 1 al 4/9 → "Mostrando 1–24 de 24", badge "Legado" y colores de fila
(violeta/verde/naranja) correctos; Stock → Historial de ingresos → mismo
badge, fallback de responsable histórico intacto. Sin errores de consola.

**Código adaptado**: `bascula.service.js#queryHistorialVales()` y
`stock.service.js#queryMovimientos()` leen de las vistas (`select('*')`
simple, sin embeds de PostgREST — las filas legado no tienen fila real de
`plantas_ingresos`/`plantas_pedidos`/`plantas_materiales` detrás para que el
embed funcione, así que la vista aplana esas columnas directo).
`useBascula.js#enriquecerVale()` actualizado a las columnas planas. UI:
badge gris sutil "Legado" en la columna Tipo de ambas tablas
(`pendiente_migracion`), acciones Imprimir Vale/Remito deshabilitadas para
esas filas en Báscula (Stock no tiene acciones editables en el historial,
append-only por diseño — no aplicaba "Corregir" ahí). Build limpio.

**Alcance explícito, no cubierto por esta vista**: 'relevamiento' de Stock
queda afuera (delta contra el anterior, mezclar cadenas migrada+legado en
vivo era el mayor riesgo de bug sutil de todo esto — ver comentario en el
script SQL). Pedidos NO tiene vista puente (decisión explícita de Federico,
descartado el trigger también) — sigue mostrando solo lo migrado.

**Sigue siendo un PUENTE temporal**, no la arquitectura definitiva — la
fecha de corte real (cuándo el sistema nuevo pasa a ser el único que se usa
en planta) sigue sin definir, ver sección de abajo.

## ✅ Auditoría integral histórico legado vs. plantas_* (previo al 01/09) — 2026-09-04, LIMPIA

Pedido explícito de Federico tras encontrar la discrepancia de Báscula 1-4
sept (ver sección de abajo): auditar TODO lo migrado el 2026-09-01
(`migracion_historial_v2.sql`) para descartar que haya más datos sin migrar
o con totales mal calculados, no solo el caso puntual de Báscula. Script
reutilizable en `supabase/scripts/auditoria_historico_vs_legado.sql` (solo
lectura, no tocó nada). Resultado — **100% limpio, sin hallazgos nuevos**:

- **Báscula** (`plantas_vales`): 884/884 migrados (382 asfalto + 499 ingreso
  + 3 egreso), 0 faltantes, **totales en tn idénticos** (diferencia 0.0000
  tn en los 3 tipos, no solo conteo de filas — se sumó `peso_neto` legado
  vs. migrado).
- **Pedidos** (`plantas_pedidos`): 178/179, único faltante `wmcde37` (mismo
  caso documentado desde el primer dry-run: `cantidad="-1"`, cancelado, sin
  valor real que migrar).
- **Historial de pedidos** (`plantas_pedidos_historial`): 531/533, los 2
  faltantes son los 2 eventos del mismo `wmcde37` (no puede migrar su
  historial sin el pedido).
- **Fórmulas** (`plantas_formulas`): 19/19, 0 faltantes.
- **Stock — movimientos** (`plantas_stock_movimientos`, sin contar
  relevamiento): 655/655, 0 faltantes en los 4 tipos legados
  (ingreso_aridos/ingreso/egreso_aridos/salida).
- **Stock — relevamiento** (snapshot mensual → delta): 23 relevamientos
  reales pre-01/09 → 124 filas `ajuste` migradas correctamente (delta contra
  el relevamiento anterior de cada material, primer relevamiento de cada uno
  sin base para delta — comportamiento esperado del diseño, no un gap).
- **Integridad general**: 0 `numero_vale` duplicado, 0 `id` de pedido legado
  duplicado, 0 ingresos huérfanos, 0 vales `ingreso_arido` sin su fila en
  `plantas_ingresos`.
- **Hallazgo colateral, no accionable**: 22 "camiones" con `nroRemito`
  dentro de pedidos de ASFALTO (no hormigón) parecían faltantes en
  `plantas_cargas_hormigon` — investigado: es un falso positivo, esa tabla
  es exclusiva de hormigón por diseño (el detalle de asfalto vive en
  `plantas_vales`, ya verificado 100% arriba). Además se encontró que esos
  22 `nroRemito` de camiones de asfalto **no coinciden con ningún
  `numero_vale` real** de ese mismo pedido en `plantas_vales` — parece un
  campo suelto/no confiable del legado para asfalto (no se usa en ningún
  lado de la UI nueva, no requiere acción, solo queda documentado por si
  reaparece la pregunta).

**Conclusión clave**: la migración del 2026-09-01 en sí está impecable — el
problema real (ver sección de abajo, Báscula 1-4 sept) es 100%
posterior/operativo: el legado se sigue usando en paralelo después de la
migración y no hay sync automático hacia `plantas_*`, no un bug de la
migración ni de las queries del sistema nuevo. Confirmado también que la
lógica de escritura actual (RPCs `registrar_pesada_bascula`,
`finalizar_despacho`/`corregir_despacho`, `registrar_movimiento_manual`/
`registrar_relevamiento_stock`) ya está correctamente enganchada a las
tablas `plantas_*` correspondientes (ver migraciones 13/14, modules-status.md)
— cualquier dato cargado HOY desde la app nueva sí impacta donde debe.

## 🔴 Báscula 1-4 sept — discrepancia investigada (2026-09-04)

Federico reportó que Báscula (filtro 1 al 4 de sept) mostraba muchos menos
movimientos que el sistema viejo para el mismo rango. Investigado a fondo:

1. **Bug real de zona horaria — corregido**: `bascula.service.js` (+ mismo
   patrón en `stock.service.js` y `analytics.service.js`) filtraban columnas
   `timestamptz` (`fecha_pesada`/`fecha_movimiento`/`fecha`) con fechas
   "peladas" sin offset — Postgres las casteaba como medianoche UTC en vez
   de medianoche LOCAL (Argentina, UTC-3), perdiendo en silencio los
   movimientos cargados entre las 21:00 y las 23:59 locales del día
   `hasta`. Fix: helpers nuevos `limiteInicioDiaLocal()`/
   `limiteFinDiaLocalExclusivo()` en `src/services/fecha.js`, aplicados en
   los 3 services. Build limpio.
2. **Causa real de la discrepancia — NO es el bug de arriba**: confirmado
   con SQL directo, el legado tiene **24 movimientos reales** entre el 1 y
   el 4/9 (20 vales asfalto + 4 ingresos áridos, en `vt_vales9`/
   `vt_ingaridos9` — mi primer conteo de "20" estaba incompleto, solo
   miraba `vt_vales9`) vs. **1 solo migrado** en `plantas_vales` (el mismo
   ingreso del 1/9 10:54). Los 23 restantes existen ÚNICAMENTE en
   `kv_store` (legado) — nunca llegaron a `plantas_vales` porque no hay
   sincronización en vivo entre el legado y el sistema nuevo, solo corrió
   la migración histórica única del 2026-09-01. `vt_vales9` tiene una
   escritura de HOY mismo (2026-09-04, minutos antes de esta auditoría) —
   el balancero sigue cargando en el sistema viejo.
3. **No se migraron ni tocaron esos 23 registros** — requiere la misma
   decisión pendiente de Federico ya documentada abajo (AUDITORÍA CRÍTICA
   2026-09-03): definir la fecha de corte real en que el sistema nuevo pasa
   a ser el único que se usa en planta, antes de sincronizar nada (si se
   sincroniza ahora y el uso paralelo sigue, se desactualiza de nuevo en
   días).

## 🎨 Colores de fila en Báscula — implementado (2026-09-04)

Pedido de Federico: que la tabla "Movimientos del día" pinte cada fila según
tipo (vale asfalto=violeta, ingreso=verde, egreso=naranja), igual que el
legado. Se reusó el esquema de color ya confirmado contra el legado en
2026-08-28 (`COLOR_PUERTA`, hoy usado en las cards de "puerta") en vez de
inventar uno nuevo — nueva constante `COLOR_FILA_VALE` en `useBascula.js` +
prop `rowClass` nuevo en `VTable.vue` (genérico, reutilizable por cualquier
otra tabla que lo necesite a futuro, aplica tanto en modo desktop como
mobile-card). Build limpio. **Pendiente de confirmación visual**: no se pudo
verificar en el navegador en esta sesión — la extensión de Chrome no estaba
conectada.

## 📋 Resumen de la sesión 2026-09-03 (tarde/noche) — impresión + migración 21

1. **Migración 21 — APLICADA** (con confirmación explícita de Federico):
   policy "admin lee todos los usuarios" + RPC `admin_upsert_usuario_rol`
   en `plantas_usuarios_roles`. La pestaña "Usuarios" queda operativa. Ver
   fila #9 de `modules-status.md`.
2. **Usuarios del legado (`vt_usuarios9`, kv_store) — auditados contra
   `plantas_usuarios_roles`**: los 15 usuarios del legado ya estaban
   migrados (+ 7 nuevos agregados después, 22 en total), con `obra_ids` ya
   reconciliados a IDs reales de `flota_obras` y `telefono` completo — la
   nota vieja de "Federico es el único con fila" en `modules-status.md`
   estaba desactualizada, corregida.
   - **Pendiente, necesita tu decisión** (no se tocó, es tabla `flota_*`):
     `angel.moreira@vialtec.com.ar`, `balanza@vialtec.com.ar` y
     `juan.heinrich@vialtec.com.ar` no tienen fila en
     `flota_usuarios_email` → en la UI de Plantas les aparece el email en
     vez del nombre. Esa tabla es el directorio real del sistema de flota
     (columnas `rol` propio de flota tipo "Encargado de Obra"/"Gerencia",
     `es_admin`, `puede_aprobar_obra/taller/stock`) — **no** es neutra,
     insertarles una fila ahí potencialmente les da acceso/permisos en
     flota. Antes de tocarla necesito que confirmes: ¿querés que existan
     como usuarios de flota también (y con qué rol/flags), o preferís que
     guarde el nombre de estos 3 solo del lado de Plantas (agregando una
     columna `nombre` nullable a `plantas_usuarios_roles`, 100% aislado,
     sin tocar flota)? Esta segunda opción es la más simple/segura si no
     necesitan cuenta de flota.
   - **Dato del legado sin equivalente hoy**: `felix.pereyra@vialtec.com.ar`
     tenía un flag `gestionUsuarios: true` en `vt_usuarios9` (permiso de
     gestionar usuarios sin ser admin). La migración 21 restringe el
     módulo Usuarios exclusivamente a rol admin (así lo pediste
     explícitamente el 2026-09-03 a la mañana) — asumo que es intencional
     que Felix ya no tenga ese acceso especial, no se implementó ningún
     equivalente. Avisame si querés preservarlo de otra forma.
3. **Formato de impresión de Vales y Remitos — 2 rondas de correcciones**
   (`ValeImprimible.vue` + `main.css`), pendiente que Federico pruebe
   imprimiendo de verdad todavía (dijo "me parece que están mal" sin haber
   probado la última versión):
   - Vale: A4 landscape, Original y Duplicado LADO A LADO en 1 sola hoja
     (`grid-cols-2`), línea de corte vertical.
   - Remito: **corregido en la 2ª ronda** — ya NO va lado a lado como el
     vale (esa fue la causa real de que saliera en varias hojas). Ahora
     cada copia (Original/Duplicado) ocupa **su propia hoja completa**, con
     salto de página forzado entre las dos (`break-after-page`). Aproveché
     el ancho completo para acercarlo más a la foto real que compartió
     Federico (agregado el campo "Desde" que faltaba, cajas con línea en
     vez de mini-etiquetas, renglones en blanco en la tabla).
   - Remito de despacho (`DespachoImprimible.vue`, "Ver remito" en
     Despachos): se le sacó el desglose de cargas individuales (llegaba a
     18 líneas, desbordaba solo) — ahora es un slip corto de Total +
     Mezcla + firmas, sigue en 1 copia.
   - Medido con un harness de JS que clona el contenido a un contenedor de
     297×210mm real (mismas dimensiones que `@page`) para verificar que no
     desborda, sin arriesgarme a abrir el diálogo nativo de impresión
     (puede trabar la sesión de automatización) — da holgura de sobra en
     ambos casos. **No es lo mismo que imprimir de verdad** — dev server
     sigue corriendo en `localhost:5173` para que Federico lo pruebe.

## 📋 Resumen de la madrugada 2026-09-03 — para arrancar el día

Trabajé sobre "hasta mañana, seguí trabajando con todo lo que puedas" — esto es
lo que avancé, en orden de importancia. Todo commiteado localmente (nada
deployado, nada escrito en producción salvo lo explícitamente confirmado).

1. **🔴 Necesito tu confirmación**: ~~migración 21~~ **APLICADA 2026-09-03
   noche, ver resumen de sesión arriba** — y el ajuste ×1000 de 642
   movimientos de stock históricos (sección Báscula/Stock, más abajo),
   que sigue sin ejecutarse, lista para correr en cuanto digas.
2. **Módulo Usuarios y Permisos por rol**: pantalla `/usuarios` completa
   (2 tabs), solo accesible para admin. Tab "Permisos por rol" ya
   funciona; tab "Usuarios" **ya operativa** (migración 21 aplicada, ver
   arriba) — queda pendiente el gap de 3 nombres sin resolver (ver arriba).
3. **Remito rediseñado** (2 copias apiladas, como pediste): verificado
   visualmente en vivo, se ve bien.
4. **Ambigüedad sin resolver** sobre la orientación de vale/remito — dejé
   el vale como ya estaba confirmado (vertical) y necesito que me digas si
   eso es lo que querías.
5. **Banner de alerta de stock proyectado** en el Dashboard (🔴/🟡) — gap
   viejo que estaba anotado en `modules-status.md`, lo cerré. No hay nada
   en alerta ahora mismo (stock sano vs. los 5 pedidos confirmados de esta
   semana), es un cambio de bajo riesgo, no necesita tu revisión urgente.
6. **Auditoría legado vs. nuevo**: encontré y documenté que el sistema
   viejo sigue en uso real en paralelo (Stock quedó desactualizado ~260tn
   en Piedra/Arena) — Despachos SÍ coincide exacto. Se cortó a mitad de
   camino: perdí sin querer la sesión ya logueada de
   `produccion.vialtec.app` al navegar esa pestaña, y no tengo tus
   credenciales para volver a entrar.

Detalle completo de cada punto en las secciones de abajo.

## 🔴 AUDITORÍA CRÍTICA 2026-09-03 (madrugada) — Stock nuevo desactualizado vs. el legado en vivo

Pedido explícito de Federico antes de irse a dormir: "audita el sistema
viejo y el nuevo, los datos deben coincidir todos, stock, historiales
etc." — se abrió `produccion.vialtec.app` (sesión ya logueada de
Federico) en paralelo y se comparó Stock actual, material por material,
en vivo. **Hallazgo importante, necesita decisión de Federico antes de
tocar nada** (memory/procedimientos.md).

### La causa raíz: el legado sigue LIVE y en uso real, después de la migración

Ya estaba documentado que esto pasaba DURANTE la migración (2026-09-01),
pero ahora se confirma que **sigue pasando 2 días después**: en
`produccion.vialtec.app` → Stock → Historial de ingresos hay movimientos
reales con fecha **"Mar 1 de septiembre"** y **"Mié 2 de septiembre"**
(posteriores al commit de la migración) — ej. Fuel Oil +25,9 t (Avanzar
S.A, remito 715927, Diego Sanchez, 2/9), Arena 0/6 +33,81 t (Cantera
Pompeya S.A, remito 250171, 2/9), Asfalto AM3 (Autovia) +26,44 t (Avanzar
S.A, remito 132228, Diego Sanchez, 1/9). **Estos movimientos NO están
reflejados en el Stock actual de nuestro sistema nuevo** — el legado
sigue siendo, en la práctica, el sistema que se usa día a día en planta
para cargar ingresos de báscula, no el nuevo.

### Comparación Stock actual — legado (en vivo, 2026-09-03) vs. nuestro sistema

| Material | Legado (ahora) | Nuestro sistema | Diferencia |
|---|---|---|---|
| ASFALTO AM3 (AUTOVIA) | **21,26 t** | 47,47 t | **−26,21 t** |
| ARENA 0/6 | **2.649,98 t** | 2.911,61 t | **−261,63 t** |
| PIEDRA 6/20 | **2.136,86 t** | 2.398,86 t | **−262,00 t** |
| FUEL OIL | **49,6 t** | 23,7 t | **+25,90 t** (al revés — nuestro está MÁS BAJO acá) |
| ADD PLAS | 10,01 t | 10,02 t | ≈ igual (redondeo) |
| ARENA 0/3 | 66,38 t | 66,38 t | ✅ igual |
| ARENA SILICIA | 1.011,52 t | 1.011,52 t | ✅ igual |
| ASFALTO CA30 | 0 t | 0 t | ✅ igual |
| CEMENTO CPC 40 | 70,98 t | 70,98 t | ✅ igual |
| FILLER | 25,42 t | 25,42 t | ✅ igual |
| PIEDRA 10/30 | 571,74 t | 571,74 t | ✅ igual |
| PIEDRA 12/20 | 530,42 t | 530,42 t | ✅ igual |
| PIEDRA 6/12 | 503,19 t | 503,19 t | ✅ igual |

**11 de 13 materiales coinciden exacto** (la mayoría de los áridos "chicos"
no tuvieron movimiento en estos 2 días) — los que NO coinciden son
justamente los que SÍ tuvieron ingresos/egresos reales recientes según el
Historial de ingresos del legado. Nota curiosa: la diferencia de Piedra
6/20 (262,00 t) es **prácticamente idéntica** al ajuste de conciliación
que se aplicó el 2026-09-01 (261.996,85 kg) — a confirmar si es
coincidencia (consumo real similar en magnitud) o si hay algo más ahí,
no alcancé a indagar más a fondo.

**Fuel Oil es el caso raro**: ahí nuestro sistema está MÁS BAJO que el
legado (23,7 vs 49,6 t), al revés que los demás — un ingreso real de
Fuel Oil (+25,9 t, remito 715927, 2/9) está en el legado y no en el
nuestro, lo que cuadra con la diferencia casi exacta.

### Historial de ingresos — conteo

Legado: **612 registros** (ingresos + salidas, sin filtrar, "Historial de
ingresos" del legado mezcla ambos tipos según el relevamiento previo).
Nuestro `plantas_stock_movimientos` tiene **642** filas de tipo
`ingreso_proveedor` sola (no comparé egresos ni otros tipos todavía) — los
conteos no son directamente comparables sin desglosar por tipo en ambos
lados, no llegué a hacer esa reconciliación fina esta noche.

### Qué implica esto — necesito que decidas cómo seguir

1. **El stock de nuestro sistema quedó desactualizado** apenas 2 días
   después de la migración, porque el flujo operativo real de báscula
   sigue pasando por el sistema viejo, no por el nuestro. Esto **no es un
   bug de código** — es un tema de proceso/adopción: mientras se sigan
   cargando ingresos/egresos reales en `produccion.vialtec.app` en vez de
   en la app nueva, el stock de acá se va a seguir desincronizando cada
   día que pasa.
2. Antes de corregir el stock actual (mismo mecanismo ya usado el
   2026-09-01 — Relevamiento mensual, RPC auditada, no un UPDATE directo),
   necesito que confirmes: ¿ya se empezó a usar el sistema nuevo para las
   pesadas reales de báscula, o seguimos en paralelo con el viejo? Si
   seguimos en paralelo, cualquier corrección que haga hoy se vuelve a
   desactualizar en un par de días — antes de re-conciliar convendría
   definir la fecha de corte real en la que el sistema nuevo pasa a ser
   el único que se usa en planta.
3. **No toqué el stock ni hice ningún ajuste** — solo until confirmés
   cómo proceder (memory/procedimientos.md, cambio de datos en
   producción).

### Buena noticia parcial: Despachos SÍ coincide exacto

Comparado en vivo (Despachos → totales acumulados): legado **"Total
asfalto acumulado" 13.435,2 tn / "Total hormigón acumulado" 1.093,6 m³ /
160 resultados** — **exactamente los mismos 3 números** que ya tenía
nuestro sistema (verificado esta misma sesión, sin necesidad de re-abrir).
Esto acota el problema: **el módulo de Despachos/Pedidos está sincronizado
correctamente**, la desactualización es específica de **ingresos/egresos
de báscula de áridos (Stock)** — probablemente porque el balancero sigue
pesando ingresos de proveedores en el sistema viejo, mientras que los
despachos de producción (que son lo que más importa para facturación) sí
se están cargando/reflejando bien en el nuevo.

### Desglose de `plantas_stock_movimientos` por tipo (2026-09-03, madrugada)

| Tipo | Cantidad |
|---|---|
| `ingreso_proveedor` | 642 |
| `ajuste` | 128 |
| `egreso_arido` | 10 |
| `egreso_manual` | 4 |
| `ingreso_manual` | 0 |
| `recalculo_despacho` | 0 |
| `egreso_despacho` | 0 |

**Nota sobre `egreso_despacho` = 0** (a primera vista parece raro, con 160
despachos ya cerrados — investigado, **no es un bug**): los 160 pedidos
`estado='despachado'` tienen TODOS `datos_legados` no nulo (son 100%
migración histórica del sistema viejo, `fecha_programada` hasta el
2026-08-31 nomás) — ninguno pasó todavía por el flujo real
`finalizar_despacho()`/`corregir_despacho()` de la app nueva (que es el
único lugar donde se genera `egreso_despacho`, migración 13). Confirmado
además en vivo en el legado: Despachos → Resumen por obra de septiembre
2026 dice **"Sin despachos en septiembre 2026"** — es decir, tampoco hubo
despachos nuevos en el sistema VIEJO desde el corte. Conclusión: todavía
nadie despachó nada (en ningún sistema) desde el 31/08 — es simple falta
de actividad, no una falla del descuento automático de stock. Sí implica
que la hoja "Consumo de insumos del mes" del Informe Mensual va a salir
vacía hasta que haya al menos un despacho cerrado por la app nueva — es
esperable, no hace falta tocar nada.

### Pendiente para completar la auditoría — interrumpido por pérdida de sesión del legado

Intenté desglosar "Historial de ingresos" del legado por tipo
(ingreso/egreso) para comparar contra la tabla de arriba, pero al navegar
la pestaña del legado (`produccion.vialtec.app`) a una URL distinta perdí
la sesión que ya estaba logueada (quedó pidiendo email/contraseña de
nuevo) — **no tengo tus credenciales y no las voy a ingresar** (regla de
seguridad de la extensión de navegador: nunca completar contraseñas).
Quedó sin hacer:
- Desglosar "Historial de ingresos" del legado por tipo para comparar
  exacto contra la tabla de arriba.
- Revisar Analítica de proveedores del legado vs. la nuestra.

Para retomar esto hace falta que abras sesión de nuevo en
`produccion.vialtec.app` (o me digas que lo dejemos así, ya que la causa
raíz — sistema viejo en uso paralelo — ya quedó bien documentada arriba
con evidencia concreta de Stock).

**Ya confirmado sin necesitar el legado**: nadie despachó nada (ni acá ni
allá) desde el 31/08 — ver nota de `egreso_despacho` arriba — así que el
próximo despacho real que se cierre en la app nueva es, en los hechos, la
primera prueba en vivo de todo el flujo Pedidos → Stock. Vale la pena que
lo mires de cerca cuando pase.
- Confirmar si el balancero sigue pesando ingresos de áridos en el
  sistema viejo (produccion.vialtec.app) en vez del nuevo (Báscula →
  "Ingreso Áridos") — si es así, es un tema de capacitación/adopción, no
  de código: hay que confirmar que efectivamente esté usando la puerta
  de Báscula del sistema nuevo para que el stock deje de desincronizarse.

## Plan Semanal — corrección de datos 2026-09-03 (flota_obras + pedido faltante)

Federico reportó en vivo (miércoles 2026-09-03, viendo Plan Semanal): el
martes 3m³ de hormigón figuraba como "Planta Asfalto Marini VT". Investigado:
el `obra_id` (2) está bien vinculado (45 pedidos desde mayo, todos
consistentes) — lo que estaba mal era el **nombre** guardado en
`flota_obras` (tabla compartida con el sistema de flota). El dato crudo
migrado del legado (`datos_legados->>'obra'`) decía literalmente "Predio
Vialtec"; el script de reconciliación de la migración linkeó bien el lugar
físico pero `flota_obras.id=2` ya tenía cargado el nombre "Planta Asfalto
Marini VT" desde el sistema de flota — dos nombres distintos para el mismo
lugar entre los dos sistemas.

**Corregido con confirmación explícita de Federico** (cambio en tabla
compartida, memory/procedimientos.md): `update flota_obras set nombre =
'Predio Vialtec' where id = 2` — afecta también al sistema de flota, no
solo a Plantas. Verificado en vivo en Plan Semanal.

**Pedido faltante, todavía sin cargar**: Federico identificó un pedido real
que no está en la base — "Predio Vialtec, Hormigón H-21, 3.5 m³,
Confirmado, Daniel Natel, 📝 Cargar 12 hs", miércoles 2026-09-02. Intenté
recrearlo por SQL directo (mismo efecto exacto que crear_pedido +
confirmar_pedido) pero **el clasificador de permisos de Claude Code lo
bloqueó** (escritura de datos de producción) — no se insertó nada. Le pedí
a Federico que lo cargue él mismo desde Pedidos → Nuevo pedido (2 minutos,
además queda con su usuario real en el historial en vez de un placeholder)
con estos datos: Obra Predio Vialtec (id 2) / Fórmula Hormigón H-21 (id
`abf23653-f21d-4ef0-a1a3-153a1e3a53b8`) / 3.5 m³ / 2026-09-02 / Encargado
Daniel Natel / Notas "Cargar 12 hs" / confirmar después de crearlo. **No
confirmó todavía si ya lo cargó** — revisar en la próxima sesión si Plan
Semanal ya muestra 4 pedidos el miércoles.

**Nota para el futuro**: puede haber más casos de `flota_obras` con nombre
"de flota" en vez del nombre operativo real que usa la planta (esta
apareció de casualidad al revisar Plan Semanal) — no se hizo una auditoría
sistemática de las ~22 obras contra los nombres reales de planta, solo se
corrigió el caso puntual reportado.

## Informe mensual de producción (Despachos → Resumen por obra) — implementado 2026-09-02, pregunta de mail RESUELTA

Pedido nuevo de Federico en medio de la sesión de roadmap Mobile:
automatizar el informe mensual que armaba a mano (compartió
`Informe Plantas prod. JULIO 2026.xlsx` de referencia + una captura del
cuerpo de mail deseado). Implementado y commiteado
(`feat(despachos): informe mensual de producción exportable a Excel + macro
de mail`): botón "📧 Exportar informe mensual" en Despachos → Resumen por
obra, arma un `.xlsx` 100% dinámico (Resumen mensual + Resumen anual + una
hoja por obra/cliente, mismo diseño violeta/verde del Excel de referencia)
vía `exceljs` — ver `src/modules/despachos/services/informe-mensual.service.js`
y `excel-informe-mensual.js`.

**Auditado (Excel de julio)**: no tenía macros, fórmulas ni gráficos
nativos — todo tipeado a mano. Se replicó solo la estética (colores/layout
leídos de sus estilos reales, no a ojo), el contenido/estructura se diseñó
de cero 100% dinámico.

**Respondida (2026-09-02, al volver)**: Federico confirmó **Outlook de
escritorio** — la rama Windows/Outlook COM de la macro es la que va a usar
en la práctica, ya escrita y lista, no hace falta tocar nada de esa parte.
Comentó que **potencialmente** más adelante quiere el envío 100%
automático (sin pasar por el borrador manual) — explícitamente **no
ahora**: "por ahora nos vamos a manejar con esto" (el flujo de borrador +
envío manual). Queda anotado como idea a futuro, no un pedido activo — no
se toca hasta que lo pida.

**Decisión técnica tomada de forma autónoma para no bloquear el resto del
trabajo** (avisar a Federico, confirmar o ajustar cuando vuelva):
- Ninguna librería JS (ni `xlsx`, ni `exceljs`, ni ninguna otra) puede
  escribir un `vbaProject.bin` válido sin Excel real instalado — es un
  límite duro del formato, no una limitación de esta sesión. Por eso el
  botón de mail no puede venir "ya embebido" en el .xlsx que genera la
  app.
- Se entregó separado en `docs/informe-mensual-macro/`:
  `EnviarInformeMensual.bas` (macro real, con **detección automática de
  SO** — Outlook COM en Windows, AppleScript a Mail.app en Mac, ninguna
  cifra hardcodeada, todo buscado por texto en las celdas del informe
  abierto) + `INSTRUCCIONES.md` (instalación única de ~2 minutos en el
  Libro de macros personal — después de esa vez, funciona con cualquier
  informe que la app genere, no hay que reinstalar cada mes).
- Si la respuesta real es "uso Gmail/webmail en el navegador", ese caso
  **no puede adjuntar el archivo automáticamente** desde VBA (limitación
  real de cualquier webmail, no sorteable) — la macro tendría que armar
  solo el texto para copiar/pegar, y el adjunto se agrega a mano. Está
  documentado en el INSTRUCCIONES.md, pero si es el caso real hay que
  avisar para simplificar el flujo (hoy la macro asume Outlook/Mail.app).

**Sin poder verificar visualmente en el navegador** (la extensión de Chrome
se desconectó en medio de la sesión, justo cuando Federico se ausentó) —
se verificó igual con un test standalone vía Node + `openpyxl` (bundle con
esbuild, datos simulados) que confirma: las 6+ hojas se crean con los
nombres correctos, los colores/merges/fills coinciden exacto con el Excel
de referencia, y las fechas salen en `DD/MM/YYYY` (no ISO). **Pendiente
para la próxima sesión con Federico presente**: probar el flujo real de
punta a punta en el navegador (con datos reales de producción) y abrir el
`.xlsx` descargado en Excel de verdad.

## Roadmap: adaptación Mobile / Responsive — EN CURSO (registrado 2026-09-02, primera tanda implementada el mismo día)

Pedido explícito de Federico: adaptar la app a mobile/smartphone, **no un
app aparte** — misma SPA, mismos `*.service.js`/composables, solo cambia la
capa de template/layout según viewport. Alcance inicial: Pedidos,
Báscula/Despachos, Maestros, Stock (en ese orden de prioridad, empezando por
Pedidos y Báscula). Fórmulas/Dashboard/Simulador/Plan Semanal quedan para
una segunda tanda, no pedidos esta vez.

**Principio no negociable (mismo que todo el resto del proyecto,
`memory/conventions.md`):** cero lógica de negocio nueva ni duplicada para
mobile — los composables (`usePedidos`, `useBascula`, `useDespachos`,
`useStock`, etc.) y los `*.service.js` se comparten 100% entre Desktop y
Mobile. Lo único que cambia es qué layout/template renderiza cada vista
según breakpoint — mismo estado, mismos datos, mismas llamadas a Supabase.

**Criterios de diseño/UX pedidos:**
- Tablas pesadas (`VTable`) → cards desplegables o listado vertical en
  mobile, no la tabla con scroll horizontal tal cual.
- Controles de acción (botones, navegación de semana, tabs de
  Asfalto/Hormigón o Materiales) con área táctil cómoda para el pulgar.
- Vales/remitos (impresos y previsualizados) legibles en pantalla de
  celular, no solo en la impresión A4.

### Progreso — primera tanda implementada (2026-09-02, misma sesión del diagnóstico)

Resuelve el diagnóstico de más abajo y ejecuta un pedido más grande de
Federico que llegó en la misma sesión (base mobile + ajustes puntuales en
Pedidos/Despachos/Báscula/Stock/Maestros, con "ante la mínima duda revisá
el sistema viejo y replicá"). 7 commits atómicos, todos en local
(`feat/pedidos-fase1`), build verificado en cada uno, sin deploy.

**Base mobile (resuelve el diagnóstico):**
- `useBreakpoint()` (`src/composables/useBreakpoint.js`, matchMedia, 768px
  — mismo valor que `md:` de Tailwind) + `MobileLayout.vue` real (nav
  inferior Pedidos/Báscula/Despachos/Stock + hoja "Más") conectado en
  `App.vue`. `src/layouts/nav.js` nuevo: SECCIONES/ICONOS compartidos entre
  Desktop/Mobile, ya no duplicados.
- `VTable.vue` gana modo cards automático bajo el breakpoint — ningún
  caller cambió, se hereda gratis en Pedidos/Báscula/Despachos/Stock/
  Maestros. `VButton.vue` con área táctil ~44-48px en mobile (`md:` la
  recorta en desktop).

**Pedidos:** las 5 cards de estado son clickeables (filtran la lista,
toggle); se sacaron los botones de navegación semana anterior/siguiente/hoy
(queda semana en curso + "Ver histórico completo").

**Despachos:** "👤 encargado" junto a la fecha (réplica del legado); fix de
un gap real — los despachos migrados del histórico legado no tienen filas
en `plantas_cargas_asfalto`, "Ver detalle de cargas" caía a `plantas_vales`
como fallback (probado en vivo, reconstruye exacto el detalle camión por
camión); selector Remito/Vale nuevo (ícono en vez de emoji 👁, a pedido de
Federico).

**Báscula:** 0 puertas abiertas por default (corrige un supuesto erróneo de
una sesión anterior, verificado en vivo contra produccion.vialtec.app);
filtro Desde/Hasta con default "Hoy" (+ fix de un bug real de rango de
fecha contra columna timestamptz que este mismo cambio hubiera expuesto);
réplica exacta de las 14 columnas del cuadro "Movimientos del día" del
legado (migración 20: `plantas_vales.responsable_email`, aprobada
explícitamente por Federico); botón Excel que respeta filtros y exporta
todo, no solo la página visible.

**Stock:** 3 tabs del legado (Stock actual / Historial de ingresos /
Analítica de proveedores — esta última pedida explícitamente por Federico
"copiar formato al sistema viejo", reconsiderando la decisión del
2026-08-31 de dejarla solo en el Dashboard); botón Excel en las 3.

**Maestros — bug real encontrado y corregido**: las tabs "Vehículos
propios"/"Vehículos externos" estaban 100% rotas desde que se separaron
(2026-09-01) — nunca se había smoke-testeado en el navegador después de
ese cambio. `maestrosService[tabActiva.value]` no encontraba nada
(`patentesPropias`/`patentesExternas` vs. `vehiculosPropios`/
`vehiculosExternos` de la vista) — cualquier acción tiraba "Cannot read
properties of undefined". Corregido y verificado en vivo: 30 vehículos
propios / 21 externos listan correctamente. Choferes queda sin cambios
(decisión confirmada esta sesión: no importar las 47 variantes sucias del
legado).

**Hallazgo sin acción (dato, no código)**: la patente `AD-648-EA` tiene
"YANCE CLAUDIO" (nombre de persona) en `tipo_camion` y `chofer_habitual`
en NULL — columnas cruzadas en el origen migrado, un solo caso detectado.
Falta que Federico confirme el dato real antes de corregirlo a mano
(UPDATE puntual, no masivo).

**Excel export**: librería nueva `xlsx` (SheetJS) + helper transversal
`src/services/excel-export.js`, import DINÁMICO (`await import('xlsx')`)
para no inflar el bundle de ninguna vista que no lo use — queda en su
propio chunk de red (~430kB) que solo se baja al exportar.

**Segunda tanda — completada en autónomo (2026-09-02, Federico ausente)**:
Federico dejó 2 tareas en cola antes de ausentarse por un rato, con
instrucción explícita de avanzar 100% autónomo:
1. Modal de despacho multi-carga (`grid-cols-[1fr_1fr_1fr_auto]`, Pedidos)
   apilado en mobile — `grid-cols-1` por debajo de 768px, botón "Quitar
   carga" con texto (antes ✕ suelto). Verificado en vivo.
2. Revisión responsive de Maestros/Fórmulas/Dashboard — **bug real
   encontrado**: la barra de tabs de Maestros (6 tabs) quedaba recortada
   por el `overflow-x-hidden` de `MobileLayout.vue` sin scroll ni wrap
   visible — la tab "Materiales" quedaba **inalcanzable** desde el
   celular. Mismo patrón en Stock (3 tabs) y Pedidos (2 tabs). Fix:
   `overflow-x-auto` + `shrink-0 whitespace-nowrap` en las 3 barras —
   patrón estándar de tabs scrolleables. Fórmulas (tabla de insumos
   anidada en el modal "Editar fórmula") y Dashboard (KPIs, analítica de
   proveedores, despachos por camión) ya funcionaban bien, sin cambios.

**Deliberadamente fuera de esta tanda** (no tocado, no pedido): Simulador/
Plan Semanal en mobile a fondo; revisión fila por fila de cada grid de
filtro/formulario del resto de las vistas (se revisaron los casos con
grids fijas conocidas, no una auditoría exhaustiva de cada modal).

### Diagnóstico rápido — estado inicial antes de esta tanda (2026-09-02, ver progreso arriba)

**Ya existe una base a medio armar, no conectada:**
- `src/layouts/MobileLayout.vue` — stub vacío (`<router-view />` a secas,
  comentario `// TODO: nav inferior/hamburguesa`), nunca importado en
  ninguna vista.
- `src/App.vue` tiene el comentario explícito "Por ahora solo existe
  DesktopLayout — cuando haya detección de mobile/breakpoint se elige entre
  DesktopLayout y MobileLayout acá" — hoy `DesktopLayout` se renderiza
  siempre, sin ninguna detección de viewport ni switch. **Primer paso
  técnico de esta tarea**: decidir el mecanismo de detección (CSS
  breakpoint con `v-if` sobre un composable `useBreakpoint`, o
  `matchMedia` reactivo) antes de tocar ninguna vista.
- `DesktopLayout.vue` (sidebar de 216px/52px colapsado) no tiene
  equivalente de nav inferior/drawer para mobile — es el otro componente
  estructural que bloquea cualquier vista mientras no exista.

**Componentes compartidos — impacto transversal:**
- `VTable.vue` (`src/components/shared/VTable.vue`) es la única forma de
  listar datos en toda la app — la usan Pedidos, Báscula (historial),
  Despachos, Dashboard, Fórmulas, Maestros, Stock. Hoy es una `<table>`
  con `overflow-x-auto` (scroll horizontal en mobile, no colapso a card) —
  **es el componente de mayor apalancamiento**: una variante mobile acá
  (o un modo "cards" activado por breakpoint dentro del mismo componente)
  resuelve de una sola vez la mitad del trabajo en Pedidos/Báscula/
  Despachos/Stock/Maestros, sin tocar ningún service.
- `VButton.vue` tamaño `sm` (`px-[10px] py-[5px] text-xs`, ~24-28px de alto)
  es el que más se usa para acciones de fila/filtros — bajo el mínimo
  recomendado de ~44px de área táctil. Definir si mobile necesita un
  tamaño `sm` más alto (o usar `md` en mobile) antes de tocar vistas.

**Pedidos (`PedidosView.vue`, prioridad #1):**
- Barra de navegación de semana (‹ Semana anterior / fecha / Semana
  siguiente / Hoy, 4 elementos `VButton size="sm"` en una fila) no entra
  cómoda en un ancho de celular — candidata a icon-buttons más grandes o
  swipe.
- Grid de filtros `grid-cols-2 md:grid-cols-4` (Estado/Obra/Desde/Hasta) y
  los 2 KPI de período (`grid-cols-2`) ya son responsive a 2 columnas en
  mobile — aceptable, pero los 5 KPI de estado (`grid-cols-2 sm:grid-cols-5`)
  quedan apretados en 2 columnas con 5 elementos (una fila de 3 + 1 suelto).
- Tabs Asfalto/Hormigón: hoy es una fila de 2 botones de texto con
  `border-b-2` — funciona en mobile tal cual, bajo impacto.
- Modales de "Registrar despacho" (multi-carga asfalto/hormigón): fila de
  carga con `grid-cols-[1fr_1fr_1fr_auto]` (Cantidad/Remito/Patente/Quitar)
  — 4 columnas fijas no van a entrar en un ancho de celular sin volverse
  ilegibles; necesita apilarse a 1 columna en mobile.
- La tabla principal de pedidos (`VTable`, ~10 columnas incl. acciones) es
  el caso más pesado de toda la vista — depende directamente del trabajo en
  `VTable.vue` de arriba.

**Báscula (`BasculaView.vue`, prioridad #2):**
- Puertas abiertas ya son cards apiladas (`grid-cols-1 lg:grid-cols-2`,
  colapsables) — el patrón de card ya existe acá, es el más cercano a
  "mobile-ready" de toda la app hoy; probablemente solo necesite ajustar
  paddings/tamaños de touch, no rediseño estructural.
- Historial de vales usa el mismo `VTable` genérico (misma dependencia que
  Pedidos) con acciones "Imprimir vale"/"Imprimir remito" en `size="sm"`.
- `ValeImprimible.vue`: el modo pantalla ya usa `grid-cols-1 print:grid-cols-2`
  (se apila a 1 columna fuera de impresión, correcto), pero varios bloques
  internos (datos del vale, firmas) son `grid-cols-2` fijo sin variante
  mobile — dentro de un `VModal` (`max-w-lg`) en un celular angosto quedan
  dos columnas de label+valor apretadas. Candidato a `grid-cols-1
  sm:grid-cols-2` interno.

**Maestros/Stock**: no relevados línea por línea en esta pasada (se
priorizó Pedidos/Báscula a pedido explícito) — mismo patrón esperado
(`VTable` + grids de formulario), retomar con el mismo método una vez
resuelto el layout base (`MobileLayout`/breakpoint) y la variante mobile de
`VTable`.

**Siguiente paso concreto, no iniciado todavía**: no se tocó código en este
diagnóstico. Falta decidir con Federico el mecanismo de breakpoint
(CSS-only vs. JS reactivo) y si el reordenamiento de `VTable` va dentro del
mismo componente (prop/slot condicional) o como un componente `VCardList`
nuevo que las vistas elijan según viewport — recién después de esa
decisión arranca la implementación, empezando por Pedidos y Báscula.

## Migración del historial del sistema anterior — COMPLETADA (2026-09-01)

**Ejecutada en producción con autorización explícita de Federico**, el mismo
día de la validación. `supabase/scripts/migracion_historial_v2.sql` corrió
con `commit;` real — el archivo queda como referencia histórica de la
migración ya aplicada, no se debe volver a correr.

**Conteos finales persistidos (verificados con una query nueva, fuera de la
transacción, después del commit — no son solo el resultado de la propia
corrida):** 184 pedidos, 543 eventos de historial, 19 fórmulas, 885 vales
(382 asfalto + 500 ingreso_arido + 3 egreso_arido), 500 ingresos, 780
movimientos de stock, 114 cargas de hormigón, 18 materiales, 8 proveedores,
51 patentes, 16 materiales con saldo en `plantas_stock`.

**Por qué estos números no son los "181/884/779" de la validación de la
mañana**: el sistema legado (`produccion.vialtec.app`) sigue LIVE y en uso
real durante todo el día — escribe directo a `kv_store` de este mismo
proyecto (ver `architecture.md`). Entre el dry-run de validación y el
commit real pasaron varias horas en las que la planta siguió operando: 3
pedidos nuevos + 1 vale de ingreso de áridos nuevo (con su ingreso y
movimiento de stock correspondientes) se cargaron en el legado y quedaron
migrados también — **no es una discrepancia ni un bug**, es exactamente el
comportamiento esperado de migrar un origen que seguía vivo. Verificado
explícitamente: al momento del commit, `vt_p9` tenía 185 pedidos, se migraron
184, y el único excluido sigue siendo el mismo de siempre (`wmcde37`,
`cantidad="-1"`, cancelado) — 185 − 1 = 184, cierra exacto.

**Verificación de integridad post-migración (pedida explícitamente por
Federico):**
- 0 vales con `numero_vale` duplicado (constraint UNIQUE + verificado con
  `group by ... having count(*) > 1`).
- 0 pedidos con el mismo `id` legado insertado dos veces.
- Único pedido sin migrar: `wmcde37` (mismo caso documentado desde el
  primer dry-run, no uno nuevo).
- Única obra sin mapear a `flota_obras`: `cjlmpvj` / Municipalidad
  Exaltación de la Cruz (mismo caso documentado desde el primer dry-run).
- **Secuencia `plantas_vales_numero_vale_seq`**: `last_value = 10493`,
  `is_called = true`, exactamente igual a `max(numero_vale)` real de la
  tabla — sin gap, el próximo vale que se pese en producción va a tomar
  `10494` sin colisión ni salto artificial.

## Migración del historial del sistema anterior — script validado, pendiente de autorización para commit (2026-09-01) — histórico, ver sección de arriba para el resultado final

**Estado actual:** `supabase/scripts/migracion_historial_v2.sql` está escrito,
corregido y **validado end-to-end en dry-run** (transacción completa con
`ROLLBACK`, 0 filas persistidas, secuencia de `plantas_vales.numero_vale`
restaurada a su valor previo — sin ningún rastro en la base compartida).
Reemplaza por completo al `migracion_historial_borrador.sql` anterior (que
asumía un origen externo — ver corrección en `architecture.md`).

Origen real de los datos, confirmado en vivo leyendo `kv_store` de
`ejitztewkpnmrckwmvny`: 182 pedidos, 19 fórmulas, 382 vales de asfalto, 499
ingresos de áridos, 3 egresos de áridos, 678 movimientos de stock, 15
usuarios, 14 obras propias, 18 materiales, 8 proveedores, 32+23 patentes.

**Dos bugs encontrados y corregidos durante la validación:**
1. Orden de la secuencia `numero_vale`: el `setval()` de sincronización
   corría *después* de que `ingreso_arido` ya había repartido números
   nuevos vía `nextval()` — con la secuencia todavía desincronizada de los
   números reales de asfalto (9582–9993), esos `nextval()` iban a colisionar
   contra vales reales ya insertados. Se reordenó: `asfalto` → `egreso_arido`
   (ambos con número real) → `setval()` → recién ahí `ingreso_arido` reparte
   números nuevos.
2. Fallback `fecha`+`hora` de `vt_m9` (movimientos de stock): en 130 de 678
   registros `hora` viene vacío y el fallback real es `fechaHora`, que a
   diferencia de `hora` en el resto del legado **no es una hora suelta sino
   un timestamp ISO completo** (`"2026-08-24T18:01:23.563Z"`) — concatenarlo
   con `fecha` como si fuera solo la hora rompía el cast a `timestamptz`.
   Se corrigió con un `case` que castea `fechaHora` directo cuando está
   presente. Afecta a los 23 eventos `relevamiento` completos (ninguno se
   hubiera migrado sin este fix) más 103 `ingreso` y 4 `salida`.

**Conteos de la corrida de validación — 100% conformes** contra lo esperado
(detalle completo en la sesión del 2026-09-01): 181 pedidos migrados (182
menos 1 excluido por `cantidad="-1"`, documentado y esperado), 19 fórmulas,
884 vales (382 asfalto + 499 ingreso + 3 egreso, sin colisiones — máximo
`numero_vale` alcanzado en la transacción: 10492), 499 ingresos, 18
materiales, 8 proveedores, 51 patentes (55 brutas − 4 duplicados por casing,
dedupe a propósito), 1 obra sin mapear a `flota_obras` (Municipalidad
Exaltación de la Cruz, esperado), 0 materiales de movimientos sin match.

**Pendiente antes de correr la migración real:** autorización explícita de
Federico para cambiar `rollback;` por `commit;` al final del script (ver
protocolo en `procedimientos.md` — cambio de datos en la instancia
compartida con Flota). El script deja ambas líneas listas (rollback activo,
commit comentado) para que ese cambio sea mínimo y explícito. Fuera de
alcance de esta pasada, documentado en el propio encabezado del script:
`plantas_cargas_asfalto.numero_vale` sin dato real que migrar,
`stock_minimo_kg`/`stock_maximo_kg` vacíos en el legado,
`plantas_clientes_frecuentes` no existe todavía,
`fecha_programada_anterior`/`nueva` de pedidos postergados históricos queda
`NULL`, y `plantas_stock.cantidad_kg` final se toma directo de `vt_s9` (no
es la suma de los movimientos migrados — límite real de qué guardaba el
legado, no un bug).

**Idempotencia (2026-09-01, revisión posterior al dry-run):** se encontraron
y corrigieron 3 `INSERT` sin guarda anti-duplicados (`plantas_pedidos_historial`,
`plantas_cargas_hormigon`, `plantas_stock_movimientos` ×2 bloques) — sin
esto, correr el script dos veces habría duplicado esas filas. Se agregó
columna `datos_legados jsonb` a `plantas_cargas_hormigon` y
`plantas_stock_movimientos` (mismo patrón que ya usaba `plantas_formulas`)
para poder dedupear por el objeto crudo del legado. **Re-validado corriendo
los 3 bloques dos veces dentro de la misma transacción de dry-run**: los
conteos finales fueron idénticos entre una pasada y dos — confirma que el
script es seguro de reintentar si algo falla a mitad de camino.

### Checklist post-migración (para cuando se autorice y corra el `commit;`)

1. Verificar en la UI real (no solo conteos SQL): Pedidos filtra/lista los
   181 migrados, Báscula/Despachos muestran los vales y despachos
   históricos, Stock refleja el saldo de `vt_s9`, Maestros lista
   materiales/proveedores/patentes migrados.
2. ✅ **RESUELTO 2026-09-07** — Federico confirmó crear la obra. Alta en
   `flota_obras` (id 38, "Municipalidad de Exaltación de la Cruz") y
   vinculación de los 3 pedidos (`obra_id = 38`) + sus 9 vales asociados
   (también tenían `obra_id = null`, copiado del pedido al momento de
   migrar). Ver entrada fechada más abajo, "Plan Semanal — pedidos
   despachados sin marcar + obra faltante".
3. Correr `select setval('plantas_vales_numero_vale_seq', (select max(numero_vale) from plantas_vales), true);`
   ya lo hace el propio script antes del `commit;` (sección 7) — no hace
   falta repetirlo a mano, pero confirmar en la UI que "Próximo N° de vale"
   (header de Báscula) da un valor coherente después del commit.
4. Revisar `plantas_usuarios_roles` para los 2 usuarios nuevos que crea el
   script (`angel.moreira@vialtec.com.ar`, `juan.heinrich@vialtec.com.ar`,
   este último inactivo) — confirmar que el rol/obras asignadas quedaron
   como se espera en la UI de gestión de usuarios (todavía no existe un
   módulo dedicado, ver fila #9 de la tabla de módulos).
5. Avisar a Federico el resultado final (conteos reales post-commit) y
   actualizar esta sección de `pending.md` + la fila #13 de
   `modules-status.md` a `LISTO`.
6. Recién después de todo lo anterior, evaluar si corresponde archivar/
   limpiar `supabase/scripts/migracion_historial_v2.sql` o dejarlo como
   referencia histórica del proceso.

## Migración del historial del sistema anterior (prioritaria) — contexto original

El sistema anterior guardaba casi todo como documentos JSON (claves tipo
`vt_usuarios9`, `vt_bak_YYYY-MM-DD`, listados de pedidos/vales/stock como blobs)
en vez de tablas relacionales. Hay que migrar ese historial hacia las nuevas
tablas relacionales `plantas_*` de este proyecto, sin perder trazabilidad.

Incluye, como mínimo:
- Pedidos históricos (con su historial de cambios de estado, no solo el estado
  final).
- Vales de báscula (respetando la numeración nativa desde 9579, sin reordenar ni
  reiniciar la secuencia).
- Ingresos/egresos de áridos por báscula.
- Movimientos de stock (o al menos el stock actual por material en kg, si el
  historial completo de movimientos no es recuperable).
- Fórmulas de mezcla (incluidas las variantes con RAP).
- Maestros: obras, encargados, proveedores, patentes (propias y externas),
  choferes — reconciliando contra lo que ya exista en `flota_*` para no duplicar
  obras/usuarios que el sistema de flota ya tiene.
- Backups históricos, si tienen valor como respaldo adicional.

**Antes de migrar, reportar a Federico** el mapeo propuesto (qué campo del sistema
viejo va a qué tabla/columna `plantas_*`, y qué se reconcilia contra `flota_*`) y
esperar confirmación — ver `procedimientos.md`. La migración toca datos de
producción reales, no es un cambio reversible trivial.

## Scaffold del proyecto

Resuelto: `package.json`, `vite.config.js` (alias `@` -> `./src`), `index.html`,
`src/main.js`, `src/App.vue`, Tailwind (`tailwind.config.js`/`postcss.config.js`)
ya están creados. **Falta correr `npm install`** (dependencias no instaladas
todavía) antes de poder levantar `npm run dev`.

## Tablas legadas sin prefijo detectadas en el proyecto compartido (revisar con Federico)

Al inspeccionar el schema real de Supabase (`ejitztewkpnmrckwmvny`) para la
migración de pedidos, aparecieron tablas **vacías (0 filas), sin prefijo**, que
pisan casi exactamente el dominio de este proyecto: `obras`, `proveedores`,
`encargados`, `usuarios`, `formulas`, `formula_insumos`, `pedidos`,
`pedido_historial`, `stock`, `ingresos`. Además `obras` (uuid) es una tabla
**distinta** de `flota_obras` (bigint, 22 filas, la que usan activamente los
módulos de flota) — hay un FK real `pedidos.obra_id -> obras.id` ya creado.

Hipótesis más probable: son un scaffold de un intento anterior (posiblemente
"vialtec-plantas-v1", ver la discrepancia de nombre ya señalada al iniciar este
proyecto) que quedó sin usar en el mismo proyecto Supabase compartido.

**No las toqué ni las usé.** Este proyecto sigue construyendo sobre `plantas_*`
(con JSONB para insumos en vez de una tabla `formula_insumos` aparte) tal como
definieron los prompts de este proyecto. Pendiente confirmar con Federico:
- ¿Se pueden borrar esas tablas sin prefijo (están vacías) para evitar confusión?
- ¿`flota_obras` es efectivamente la tabla de obras correcta a usar (así se
  usó en `plantas_pedidos.obra_id`), y la `obras` suelta es descartable?

## Migración SQL de Fórmulas y Maestros — escrita, NO aplicada

`supabase/migrations/01_maestros_y_formulas.sql` tiene los `CREATE TABLE` +
índices para `plantas_formulas`, `plantas_encargados`, `plantas_proveedores`,
`plantas_patentes`, `plantas_choferes`. **No se ejecutó contra Supabase** —
requiere revisión y confirmación de Federico antes de aplicarla (protocolo de
`procedimientos.md`). Además queda pendiente definir, antes de aplicar en
producción:
- Políticas de RLS por rol (la migración no las incluye).
- Si `plantas_encargados` es redundante con encargados ya existentes en
  `flota_usuarios` o es un catálogo aparte.

## Migración SQL de Pedidos — escrita, NO aplicada

`supabase/migrations/02_pedidos.sql` crea `plantas_pedidos` (FK a `flota_obras`
y a `plantas_formulas`). Depende de que `01_maestros_y_formulas.sql` se aplique
primero. Simplifica el ciclo de estados del sistema legado a 4 estados
(`solicitado`, `confirmado`, `despachado`, `cancelado`) — **no incluye
`postergado`** (sí documentado en `business-rules.md`). Revisar si hace falta
reintroducirlo antes de aplicar la migración.

## Migración SQL de Báscula/Vales — escrita, NO aplicada

`supabase/migrations/04_bascula_y_vales.sql` crea `plantas_vales` (numeración
nativa desde 9579 vía identity column, FK a `plantas_pedidos` y `flota_obras`).
El número "04" es intencional — el "03" queda reservado para el módulo Stock,
que todavía no existe. Puntos a decidir con Federico antes de aplicarla:
- `tipo_vale` incluye `'hormigon'` porque así lo pidió el prompt de este
  módulo, pero `business-rules.md` documenta que la báscula legada **no** pesa
  hormigón. El código no ofrece ningún flujo para crearlo — el valor queda
  soportado en el schema por si se decide lo contrario.
- Ingreso de áridos (`tipo_vale = 'ingreso_arido'`) ya captura material,
  proveedor, N° de remito y cantidad según remito en la UI — se resolvió en la
  migración 05 (`plantas_ingresos`), no quedó en `plantas_vales`. Ver más abajo.
- **Descuento de stock al pesar**: `registrarPesada()` tiene un TODO explícito
  — no descuenta stock porque el módulo Stock (tabla `plantas_stock`) todavía
  no existe. Es el punto de integración obligado cuando se construya ese
  módulo.

## Migración SQL de Analítica — escrita, NO aplicada

`supabase/migrations/05_analitica_y_vistas.sql` agrega dos tablas que el
Dashboard necesitaba y no existían, más una vista:
- `plantas_ingresos`: fuente única de ingresos de insumos (manual o vía
  báscula). Hoy solo la escribe `bascula.service.js` (`origen='bascula'`) —
  el ingreso manual (`origen='manual'`) queda soportado en el schema pero
  **sin ninguna UI todavía** (le corresponde al módulo Stock, PENDIENTE).
  Hasta que ese módulo exista, la analítica de proveedores del Dashboard solo
  va a reflejar lo que se pesó en báscula, no compras que entren sin pesar.
- `plantas_cargas_hormigon`: **resuelto** — `PedidosView.vue` tiene la acción
  "Registrar carga" (pedidos de hormigón confirmados) que llama a
  `pedidos.service.js#registrarCargaHormigon()`, con remito obligatorio y
  autocompletado de patente/chofer. Columnas ajustadas respecto de como
  habían quedado en la migración 05 original: `volumen_m3` (no `cantidad_m3`),
  `patente_mixer` (no `patente`), y se agregó `chofer` — la migración se
  editó in-place porque todavía no se había aplicado a Supabase.
- Vista `plantas_v_despachos_camion`: UNION de las dos tablas de arriba con
  `numero_remito` garantizado para ambos materiales.

No se puso `UNIQUE` en `numero_remito` de ninguna de las dos tablas nuevas —
el sistema legado valida que no se duplique, pero probablemente esa unicidad
es por proveedor/transportista, no global. Confirmar con Federico antes de
agregar esa restricción.

## Migración del historial legado — mapeo y schema de soporte (avance histórico, ver sección de arriba para el estado vigente)

**Nota 2026-09-01:** las decisiones de mapeo de esta sección siguen vigentes
y ya están reflejadas en `migracion_historial_v2.sql`. Los puntos
"pendientes antes de correr el borrador en serio" que estaban más abajo (ver
al final de esta sección) **quedaron resueltos u obsoletos** una vez
confirmado que el legado vive en `kv_store` de este mismo proyecto (no en
una base externa): no hace falta ETL/CSV ni staging tables — el script v2
lee `kv_store` directo. Se dejan tachados/aclarados in-situ para no perder
el historial de la decisión.

Federico confirmó las siguientes decisiones sobre el mapeo campo a campo
propuesto para migrar pedidos/historial/vales del legado hacia `plantas_*`:

- `plantas_pedidos.obra_id` pasa a nullable (ventas externas sin obra real).
  `plantas_vales.obra_id` ya era nullable, no necesitó cambio.
- `plantas_pedidos` suma columnas operativas (no solo para la migración,
  también para que la UI gestione el ciclo completo del pedido): `encargado`,
  `tipo_pedido` (`obra`/`venta`), `cliente_externo`, `motivo`, `motivo_en`,
  `archivado`, `nro_remito_global`, `nro_vale_global`.
- En vez de columnas de auditoría sueltas por campo, `plantas_pedidos` y
  `plantas_vales` suman `datos_legados jsonb` (objeto crudo del legado
  completo, indexado por `datos_legados->>'id'` en pedidos).
- Se reintroduce el estado `postergado` en el CHECK de `plantas_pedidos.estado`.
- Se crea `plantas_pedidos_historial` (una fila por evento del array
  `historial` del legado).
- Zona horaria fija `America/Argentina/Buenos_Aires` para combinar fecha+hora
  del legado — aplicada como `SET LOCAL` en el script de carga, no como
  config global de la instancia (compartida con flota).

Escrito, **NO aplicado**:
- `supabase/migrations/06_ajustes_pedidos_vales_historial.sql` — patch de
  schema (ALTERs + tabla nueva `plantas_pedidos_historial`). Depende de que
  01/02/04/05 se apliquen antes.
- `supabase/scripts/migracion_historial_borrador.sql` — borrador del script
  de carga de datos (fuera de `migrations/` a propósito, no es schema).
  Corre sobre tablas de staging (`staging_legado_pedidos`,
  `staging_legado_vales`) que **todavía no existen** — el script asume que
  se cargan con el JSON crudo del legado, pero falta resolver de dónde sale
  ese volcado real (ver punto pendiente abajo). Termina en `rollback;` por
  diseño: no persiste nada hasta que se revise a mano y se cambie por
  `commit;`.

Pendiente antes de poder correr el borrador en serio (histórico — ver
sección "estado vigente" al inicio del archivo, 2026-09-01):
- ~~El sistema legado vive en una base/motor externo a Supabase~~ —
  **corregido 2026-09-01**: vive en `kv_store` de este mismo proyecto (ver
  `architecture.md`). No hace falta ETL/CSV ni staging tables — el script
  v2 lee `kv_store` directo con `jsonb_array_elements` en el mismo `SELECT`.
  Este punto y los dos siguientes (formato de export CSV, encoding) quedan
  **obsoletos**, no aplican más.
- ~~Sigue sin definir el formato/estructura exacta del export CSV~~ —
  obsoleto, no hay export, se lee `kv_store` directo (ver arriba).
- Contra qué campo del legado se hace el lookup de `plantas_formulas`:
  **resuelto** en `migracion_historial_v2.sql` — se preserva el `id` legado
  en `plantas_formulas.datos_legados` y el lookup de cada pedido es exacto
  por ese id, no por nombre (mejora respecto de este borrador original).
- `fecha_programada_anterior`/`nueva` en eventos `postergado` del histórico:
  **sigue sin resolver**, confirmado que queda fuera de alcance de la v2
  también (requeriría `lag()`/`lead()` sobre el array `historial` de cada
  pedido) — ver nota de alcance en el encabezado de
  `migracion_historial_v2.sql`. Queda `NULL` en los eventos migrados; no
  bloquea la migración.

## Relevamiento funcional del sistema viejo (produccion.vialtec.app) — CERRADO (Etapa 1) + ampliado (Etapa 3)

Ver `memory/relevamiento-sistema-viejo.md` (los 13 módulos relevados vía
navegación real en Claude in Chrome, 2026-08-27). Contiene una lista
concreta de gaps funcionales confirmados contra producción real (no solo
contra los .rtf), 16 gaps priorizables y 6 preguntas abiertas para Federico.
El hallazgo más importante: **"obra" en el sistema viejo es un catálogo
propio con código, no `flota_obras`** — y también hay catálogos propios de
Materiales/Insumos y Clientes frecuentes que hoy no existen en `plantas_*`.
Esto pone en duda la estrategia de reconciliación de obras ya escrita en la
sección de migración de historial de este mismo archivo — **revisar y
probablemente reescribir ese mapeo antes de tocarlo de nuevo**, incorporando
los 3 catálogos nuevos (`plantas_obras`, `plantas_materiales`,
`plantas_clientes_frecuentes`) al diseño de schema.

**Etapa 3 (2026-08-28)** — pasada minuciosa botón por botón/modal por modal
(alcance acotado a lo operativo, no a lo visual). Confirma con precisión
mayor varios puntos de la Etapa 1 y agrega hallazgos nuevos accionables sin
cambio de schema (Ingreso Áridos: `Proveedor` debería ser select no texto
libre, `N° Remito` debería ser obligatorio; sacar "Chofer" de los forms de
Ingreso/Egreso) y con cambio de schema (Egreso de áridos: `obra_id` en vez
de `destino` texto libre; unificar el despacho de hormigón al patrón
multi-carga de asfalto). Ver la sección "Etapa 3" al final de
`relevamiento-sistema-viejo.md` para el detalle completo y el resumen de
acciones concretas al pie del documento — **todavía no implementado**, queda
para la próxima sesión de trabajo sobre código.

## Maestros — auditoría de `vt_maestros9` + separación Vehículos Propios/Externos (2026-09-01)

`vt_maestros9` tiene 6 arrays: `obras` (14), `clientes` (7), `patentes` (32),
`materiales` (18), `proveedores` (8), `patenteExternas` (23). Estado real
contra `plantas_*`:

- ✅ Obras, materiales, proveedores, patentes: migrados (ver reconciliación
  de la sección de arriba).
- ❌ **`clientes` (7 registros — Municipalidad de Pilar, Colegio Moorlands,
  Corralon Filiberti, etc.) NUNCA se migró — no existe `plantas_clientes_frecuentes`**
  (gap ya documentado desde el relevamiento original, confirmado de nuevo
  acá). Crear esa tabla es un cambio de schema — **necesito tu autorización
  explícita** antes de hacerlo (protocolo de `procedimientos.md`).
- ❌ **No hay catálogo de "choferes" ni "transportistas" en el legado** — el
  nombre del chofer es texto libre dentro de cada patente
  (`chofer_habitual`) y de cada vale/pedido, nunca una entidad propia. Por
  eso `plantas_choferes` está vacía: no hay nada 1:1 para migrar.
  Extraje los nombres únicos de choferes que aparecen en patentes + vales
  (47 variantes de texto) para evaluar poblarla, pero **tienen inconsistencias
  reales de formato** (mismo chofer escrito "Nombre Apellido" en un lado y
  "Apellido Nombre" en otro, alguna variante de tildeo/ortografía —
  ej. "Basabe Alejandro" (34 apariciones) vs. "Alejandro Sanchez"/"Sanchez
  Alejandro" (20+1) probablemente la misma persona en 2 formatos). **No
  las cargué automáticamente** — un merge automático arriesga fusionar dos
  personas distintas o duplicar una sola. Recomiendo cargar los choferes a
  mano desde la tab "Choferes" (ya anda) a medida que se necesiten, en vez
  de un import masivo de datos sucios.
- "Transportista" no es un catálogo aparte del legado — en la práctica es
  el mismo campo que "chofer" (confirmado contra el remito real: el campo
  "TRANSPORTISTA" del papel lleva el nombre de la persona, no de una
  empresa).

**Separación Vehículos Propios/Externos aplicada**: `plantas_patentes` ya
tenía `es_externa` (30 propias / 21 externas reales, deduplicadas de 55
brutas). Antes convivían en una sola tab "Patentes" con una columna
"Origen". Ahora son 2 tabs separadas en Maestros — "Vehículos propios" /
"Vehículos externos" — cada una con su propio service
(`patentesPropiasService`/`patentesExternasService`, mismo
`plantas_patentes`, filtro fijo por `es_externa`, no tablas nuevas). Ya se
reflejaba correctamente en el remito de Báscula (`ValeImprimible.vue`,
campo "Transporte: Propio/Tercero" agregado en la sesión anterior) — sin
cambios ahí, ya estaba resuelto.

## Hallazgos de relevamiento en vivo del sistema viejo (2026-09-01, sesión con acceso real)

Con sesión real logueada en `produccion.vialtec.app` (Federico ya estaba
adentro), se navegó Pedidos, Despachos, Báscula, Fórmulas y Stock a fondo.
Dos hallazgos accionables, no triviales:

1. **2 pedidos reales quedaron con `obra_id = NULL`** por un efecto
   colateral del script de migración: `x882wic` (23,38 tn, despachado,
   16/05/2026) y `fjabb3s` (34,38 tn, despachado, 23/05/2026) referencian la
   obra legado `htfk5kp` (código `PRUEBAS-01`, "PRUEBAS MEZCLA ASFALTO") —
   el script la excluye a propósito asumiendo que es 100% de prueba
   (`delete from stg_obras_legado where codigo = 'PRUEBAS-01'`), pero estos
   2 despachos son reales. No hay forma de inferir la obra real desde acá
   (el legado no guardó ese dato en ningún otro lado) — **pendiente que
   Federico diga a qué obra correspondían en realidad** para un `UPDATE`
   puntual de esos 2 registros.

2. **⚠️ CRÍTICO — el stock migrado (`plantas_stock`, desde `vt_s9`) puede
   estar desactualizado respecto de lo que el sistema viejo muestra HOY en
   vivo**, para al menos 3 de 16 materiales (comparado a mano, pantalla
   Stock del legado vs. el valor guardado en `vt_s9` al momento de migrar):
   - Asfalto AM3 (Autovia): legado en vivo **47,46 t** vs. `vt_s9` (y por lo
     tanto lo migrado) **21,26 t** — diferencia de +26,2 t.
   - Arena 0/6: legado en vivo **2.911,61 t** vs. `vt_s9` **2.616,17 t** —
     diferencia de +295,44 t.
   - Piedra 6/20: legado en vivo **2.398,86 t** vs. `vt_s9` **2.136,86 t** —
     diferencia de +262 t.
   - Los otros 13 materiales sí coincidían exacto entre `vt_s9` y la
     pantalla en vivo del legado.

   No se pudo determinar la causa exacta (`vt_s9` no se actualiza en tiempo
   real con cada ingreso, o el legado calcula el número que muestra en
   pantalla de otra forma que no queda grabada en `vt_s9`) — lo que importa
   es que **nuestro `plantas_stock` recién migrado puede estar
   subestimando el stock real de esos 3 materiales**. Recomendación: antes
   de operar Stock en el sistema nuevo, hacer un **relevamiento real** (ya
   construido, `registrarRelevamiento()`/módulo Stock) contando estos 3
   materiales (y de paso confirmando los otros 13) para corregir vía el
   flujo de ajuste auditado, en vez de confiar en el valor migrado tal cual.

   **✅ RESUELTO 2026-09-01** — corregido vía el flujo auditado real
   (`Relevamiento mensual` en la UI de Stock, no un UPDATE directo):
   `plantas_stock.cantidad_kg` ahora es exacto contra la pantalla del legado
   para los 3 — Arena 0/6: `2.911.613 kg` (2.911,613 t), Piedra 6/20:
   `2.398.861 kg` (2.398,861 t), Asfalto AM3 (Autovia): `47.465 kg`
   (47,465 t). Quedó registrado como 3 movimientos `tipo='ajuste'` en
   `plantas_stock_movimientos` (deltas +295.443,1 kg / +261.996,85 kg /
   +26.200,1 kg respectivamente), `origen`/motivo = "Ajuste por conciliación
   contra sistema legado (auditoría 2026-09-01)", `responsable_email` =
   `federico.mazzeo@vialtec.com.ar` (vía `auth.email()` server-side, RPC
   `registrar_relevamiento_stock` — mismo mecanismo que cualquier
   relevamiento real, con `saveStockGuard` de por medio). Verificado con
   query directa a `plantas_stock` y visualmente en la UI de Stock — los 3
   materiales pasaron a "OK" con el valor exacto del legado.

   **Adicional**: el legado tiene umbrales mín/máx configurados por
   material (visibles como barra de progreso en su pantalla de Stock — ej.
   Arena 0/6 min 100t/máx 200t, Cemento min 8t/máx 15t) que **no existen en
   ningún lado de `kv_store`** (ni en `vt_maestros9.materiales` ni en
   `vt_s9`) — deben estar hardcodeados en el frontend del legado. Quedaron
   NULL en `plantas_materiales.stock_minimo_kg/stock_maximo_kg` tal como ya
   estaba documentado, pero ahora se confirma que si Federico quiere esos
   valores reales, hay que transcribirlos a mano desde la pantalla del
   legado (no hay ningún dato para migrar automáticamente).

Otros puntos relevados, sin acción pendiente (documentados para referencia):
- **Pedidos del legado no filtra por fecha ni pagina**: muestra solo los
  pedidos activos (no despachado/cancelado) agrupados por material
  (Hormigón/Asfalto), sin límite — el archivo ("Archivo") estaba vacío al
  momento de relevar. El historial completo vive en **Despachos** (159
  resultados al momento de revisar), no en Pedidos — confirma que nuestra
  separación Pedidos/Despachos ya replica esa idea, y justifica por qué
  acotar Pedidos por semana (ver módulo Pedidos, ajuste de esta sesión) es
  la solución correcta para nuestro diseño aunque el legado no filtre así.
- **Despachos del legado tiene ícono de eliminar por fila** (🗑) — contradice
  `business-rules.md` ("los pedidos nunca se eliminan"). Deliberadamente
  NO replicado — ya era una decisión tomada en sesiones anteriores.
- **Báscula del legado**: mismo patrón que el nuestro (movimientos del día,
  próximo N° de vale, tabla con Bruto/Tara/Neto/Acum./S-Remito/Dif.) — sin
  gaps nuevos encontrados.
- **Fórmulas del legado**: grid de cards (no tabla) agrupadas por
  Todas/Hormigón/Asfalto con contador, insumos con tag "sin stock" en
  Agua/Purgue — confirma que nuestra regla de exclusión de Agua/Purgue del
  descuento de stock es consistente con el legado. Diseño visual distinto
  (cards vs. tabla) pero sin gap funcional.

## Guía de estilo de Flota (equipos2.vialtec.app) — borrador listo

Ver `memory/guia-estilo-flota.md` — paleta exacta (HEX, tomados de
`getComputedStyle`/clases Tailwind reales, no a ojo), tipografía (Manrope),
layout de sidebar, y spec de botones/badges/tabs/KPI/tablas/modales/inputs,
más una propuesta de `tailwind.config.js` (no aplicada — nuestro
`theme.extend` está vacío hoy, no hay conflicto). Falta decidir con Federico
el naming de los tokens (`success/danger/warning/info` propuesto vs.
calcar `green/red/amber/blue` como en Flota) antes de aplicar el config.
Un valor (`amber-light`) quedó sin confirmar, marcado explícitamente en el
documento.

## ✅ Migración 21 (Usuarios y Permisos por rol) — YA APLICADA, sección anterior desactualizada

**Corrección 2026-09-06**: la sección de abajo (2026-09-03) quedó desactualizada
sin que nadie la actualizara cuando se resolvió — `modules-status.md` fila #9
ya documentaba correctamente "Migración 21 aplicada 2026-09-03 noche", pero
esta sección de `pending.md` seguía pidiendo confirmación para algo que ya
estaba hecho. Verificado hoy en vivo, sin ambigüedad: la policy "admin lee
todos los usuarios" y el RPC `admin_upsert_usuario_rol` existen en producción,
y **probé el flujo completo end-to-end** (alta de usuario de prueba con rol
`encargado` + obra asignada, edición cambiando el rol a `supervisor`, borrado
de limpieza) — las 3 operaciones funcionan correctamente vía RPC. Tab
"Permisos por rol" también verificada, renderiza la matriz de los 7 roles sin
errores. **La tab "Usuarios" está 100% operativa, no hay nada pendiente acá.**
Se conserva el texto original abajo como referencia histórica de la decisión
de diseño, pero ya no es accionable.

### (Histórico, ya resuelto) Confirmación pendiente — Migración 21: Usuarios y Permisos por rol (2026-09-03)

Pedido explícito de Federico: *"MÓDULO DE USUARIOS Y PERMISOS POR ROL: Incluir
la pestaña/tab 'Usuarios' dentro del Módulo de Permisos por Rol para unificar
ahí toda la administración de cuentas y asignación de roles. Restringir el
acceso a este módulo y sus configuraciones exclusivamente a usuarios con rol
Admin."*

Dejé armada la migración 21 como **borrador, sin aplicar**, en
`supabase/migrations/21_admin_gestion_usuarios_roles.sql`:
- Agrega una policy de SELECT: admin puede leer todas las filas (la policy
  de "cada uno lee la suya" sigue intacta).
- Agrega una función `admin_upsert_usuario_rol(...)` (SECURITY DEFINER) que
  valida server-side que quien llama sea admin — única vía de escritura,
  mismo patrón que ya usan Pedidos/Báscula.
- 100% aditivo, no toca datos existentes. Reversible con 2 `drop` (detallado
  al final del archivo).

## ⚠️ Ambigüedad sin resolver — orientación de vale/remito (2026-09-03)

Tu mensaje: *"los vale y remitos imprimibles, los vales la hoja debe estar
horizontal y los vales verticales, aprovechar toda la hoja. remito, 2 hojas
iguales, hoy se imprimen 6"* — el mensaje se contradice a sí mismo ("los
vales... horizontal" y en la misma frase "los vales verticales"), así que
no reinterpreté el rediseño ya confirmado antes en la sesión (ítem 1 de tu
lista de requerimientos: *"orientación VERTICAL"* para vale y remito, que sí
implementé y vos no corregiste en ningún mensaje posterior — al contrario,
más tarde dijiste "la firmas de los vales ya estan bien, no las toques",
dando por bueno ese rediseño).

**Lo que hice**: dejé el vale en vertical (como ya estaba confirmado) y
SOLO tomé como accionable la parte no ambigua — "remito, 2 hojas iguales,
hoy se imprimen 6" — rehaciendo el remito para que sean 2 copias idénticas
apiladas en una sola hoja (mismo patrón que el vale: "Remito original" /
"Remito duplicado" con línea de corte punteada), buscando resolver el "hoy
se imprimen 6" (que entiendo como demasiadas hojas por remito hoy).

**Falta confirmar**:
1. ¿El vale queda en vertical (como ya está) o querías decir que el **remito**
   fuera horizontal y el vale vertical? Con el mensaje tal cual está escrito
   no puedo saber si "los vales" (2ª mención) fue un error de tipeo por
   "los remitos".
2. ~~El remito rediseñado no se verificó visualmente~~ — **verificado
   2026-09-03 de madrugada**: abrí Báscula → Historial, filtré un remito
   real (Nº 1242, AUTOVIA MERCOSUR, 557.44 tn) y revisé el modal "Remito de
   entrega" — las 2 copias (Original/Duplicado) entran completas y legibles
   sin scroll, con la línea de corte punteada entre ambas, igual que el
   vale. Se ve prolijo. No llegué a mandarlo a impresión real (el print
   nativo del navegador abre un diálogo modal que bloquea la extensión de
   Chrome, así que no lo disparé) — si al imprimirlo en papel algo no entra
   bien en la hoja, avisame y lo ajusto.

## 🎯 CORTE COMPLETO — deploy, DNS y smoke test — 2026-09-07

Con la migración real ya aplicada (ver entrada de arriba) y `main` mergeado
+ pusheado a GitHub (`8298e76`), Federico ejecutó el deploy y el cambio de
dominio. Encontré y corregí 2 bugs reales de producción durante el smoke
test — ninguno relacionado con el código migrado, los dos eran gaps de
configuración del deploy en sí (nunca se había hecho un `npx vercel --prod`
real contra este dominio hasta ahora).

**Bug 1 — pantalla en blanco, app no arrancaba en absoluto**: el proyecto
de Vercel (`vialtec-plantas-v2`) no tenía NINGUNA variable de entorno
configurada (`vercel env ls production` → 0 resultados). El build corría
sin `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY`, así que el cliente de
Supabase nunca se inicializaba (`Error: Faltan VITE_SUPABASE_URL /
VITE_SUPABASE_ANON_KEY en las variables de entorno.`, capturado en la
consola del navegador contra el dominio real). Encontrado en el paso 1 del
smoke test (verificación de lectura/sesión), antes de tocar `kv_store`.
**Fix**: `vercel env add VITE_SUPABASE_URL production` y
`vercel env add VITE_SUPABASE_ANON_KEY production --type config` (el
`ANON_KEY` de Supabase es una clave pública por diseño — protegida por
RLS, no por ocultarla — así que va como `config`, no `secret`; con
`--type secret` y sin el prefijo `VITE_` Vite no la habría inlineado en el
bundle del cliente). Autorizado explícitamente por Federico antes de
tocar la config de Vercel.

**Bug 2 — 404 en cualquier ruta que no fuera la raíz**: no existía
`vercel.json` en el repo. El router usa `createWebHistory()` (Vue Router
modo history), que necesita que el servidor reescriba TODAS las rutas a
`index.html` — sin eso, Vercel devuelve 404 nativo de Vercel en cualquier
refresh, deep-link o URL compartida que no sea `/`. Se veía al navegar
directo a `/login` (o a cualquier otra ruta) sin pasar antes por `/`.
**Fix**: `vercel.json` nuevo con `{"rewrites":[{"source":"/(.*)","destination":"/index.html"}]}`,
commiteado al repo (no solo aplicado al deploy — si no, el próximo
`vercel --prod` desde un checkout limpio lo volvería a romper).

Ambos fixes requirieron un segundo y tercer `npx vercel --prod` (el
primero con las env vars ya cargadas resolvió el blank-page; el segundo,
después de agregar `vercel.json`, resolvió el 404). El deploy final quedó
aliasado a `produccion.vialtec.app` correctamente (confirmado por la CLI:
`▲ Aliased https://produccion.vialtec.app`).

**Cierre de la RLS abierta de `kv_store`** (hallazgo de seguridad
pendiente desde el relevamiento inicial, memory/business-rules.md): la
policy `"Acceso publico kv"` (`FOR ALL TO public USING (true)` — cualquiera,
autenticado o no, podía leer Y escribir todo el storage del legado) se
reemplazó por `migración 28` con una sola policy de solo lectura para
`authenticated`. **No se pudo cerrar a cero**: `plantas_v_bascula_viva` y
`plantas_v_stock_movimientos_viva` (las vistas puente de Báscula/Stock)
son `security_invoker = true` y leen `kv_store` con los permisos del
usuario que las consulta desde el cliente — cerrar el SELECT también a
`authenticated` hubiera roto esas 2 pantallas en vivo. Verificado en el
smoke test contra el dominio real después de aplicar la migración: Báscula
(vales/históricos) y Stock (historial de ingresos, filas "(histórico)")
siguen cargando sin errores.

**Smoke test post-corte contra `produccion.vialtec.app` (dominio real, no
localhost)** — sesión de Federico (admin) persistió sola (mismo Supabase
Auth que el legado, localStorage del dominio ya tenía el token):
- Home: carga con datos reales, producción de asfalto 25.566,6 tn total
  (11.916,7 Ammann + 13.649,9 Marini — coincide con lo esperado post-
  migración), producción de hormigón 4.718,8 m³, Gantt de despachos.
- Pedidos: recarga directa en `/pedidos` (antes 404) — OK, filtros y
  listado funcionando.
- Báscula: histórico de vales real, "Próximo N° 00010017" (consistente con
  el `setval()` a 10016 de la migración).
- Stock: stock actual + historial de ingresos con filas "(histórico)"
  desde la vista puente — OK.
- Despachos: cards de producción anual iguales a Home — OK.
- Administración → Roles: matriz de permisos real, 7 roles, contadores de
  usuarios correctos — OK.
- 0 errores de consola en ninguna pantalla revisada.

**Hallazgo menor, no corregido (decisión de Federico)**: en Stock →
Historial de ingresos aparece una fila `6/9/2026, Ingreso manual, Filler,
+1.000 t, motivo "PRUEBA QA - BORRAR", responsable Federico Mazzeo` — por
el motivo, parece un dato de prueba de una sesión anterior que quedó sin
limpiar (no encontré rastro de que Claude la haya creado en esta sesión).
No la borré yo: borrar un movimiento de stock ya aplicado cambia el
balance real de "Filler" (hoy 25,42 tn en Stock actual) y no es una
decisión que corresponda tomar sin confirmar. Si es prueba, avisame y la
revierto con un movimiento de compensación (mismo patrón que el resto de
las limpiezas de esta sesión).

**Pendiente inmediato** (checklist, secciones 8-9 de
`CHECKLIST_CORTE_FINAL.md`): dar de baja el legado como fuente de
escritura (si sigue desplegado en otro lado, hay que apagarlo/quitarle
acceso explícitamente — el cambio de DNS de `produccion.vialtec.app` no
lo apaga solo si vive en otra URL/hosting). Las vistas puente
(`plantas_v_bascula_viva`/`plantas_v_stock_movimientos_viva`) quedan sin
filas "Legado" para mostrar de acá en más (ya no hay delta pendiente) —
opcional simplificarlas más adelante, no bloqueante.

## ✅ Re-verificación pre-corte — 2026-09-07 (dry-run del día anterior a la corrida real)

Pedido de Federico ("avanzamos directamente con la MIGRACIÓN GRANDE"): re-
correr auditoría + dry-run del script de corte, hoy, para confirmar que
sigue vigente antes de la corrida real. Nada tocó producción (todo
lectura + una transacción con `rollback`).

**1) Auditoría del delta** (`supabase/scripts/auditoria_delta_desde_01_09.sql`,
re-ejecutada completa): **resultado IDÉNTICO al de 2026-09-06** — 4 pedidos
pendientes, 18 eventos de historial, 4 cargas de hormigón, 20 vales de
asfalto, 0 egreso_arido, 3 ingresos de áridos, 1 relevamiento nuevo sin
reconciliar (2026-09-03, el mismo de siempre). El legado no acumuló
actividad nueva en el día que pasó — señal de que el equipo ya no está
cargando en `produccion.vialtec.app`. Chequeo crítico de colisión de
`numero_vale`: **0 filas**, igual que ayer.

**2) Dry-run del script de migración** (`supabase/scripts/migracion_final_corte.sql`,
transacción completa con `rollback` al final): baseline pre-corrida
184/543/114/885/500/786 (pedidos/historial/cargas hormigón/vales/
ingresos/stock movimientos) — **exactamente igual al baseline de ayer**.
Resultado del dry-run: 188/561/119/908/503/789 (mismos deltas: +4/+18/+5/
+23/+3/+3). `setval()`: `secuencia_actual` = `max_vale_real` = 10016 en
ambos casos (el `setval` de ayer no se revirtió con el `rollback` —
comportamiento no-transaccional de Postgres para sequences, esperado, no
es un bug). 3 chequeos de integridad: 0 duplicados de `numero_vale`, 0
`id_legado` duplicado, 0 ingresos huérfanos. Post-rollback verificado:
conteos volvieron exactos a 184/543/114/885/500/786, `max_vale_real`
volvió a 9993 (el número real más alto YA migrado, sin contar el delta
pendiente).

**3) Auditoría de consistencia — recuento final por tabla** (a migrar en
la corrida real): Pedidos +4, Pedidos_historial +18, Cargas_hormigón +5
(4 del legado + 1 que es el propio pedido de hormigón recién migrado
trayendo su camión, resuelto dentro de la misma transacción), Vales +23
(20 asfalto + 3 ingreso_arido, numeración real preservada vía
`overriding system value`), Ingresos +3, Stock_movimientos +3.
`plantas_stock` (balance final) sigue **excluido a propósito** — decisión
de Federico pendiente para el día del corte (Opción A: confiar en el
ledger nuevo / Opción B: relevamiento físico fresco, ver
`CHECKLIST_CORTE_FINAL.md` punto 3).

**4) Checklist de deploy final** — ya existía completo desde el 06 en
`supabase/scripts/CHECKLIST_CORTE_FINAL.md` (9 secciones: re-auditar en
vivo, dry-run, decisión de stock, corrida real con commit, `npx vercel
--prod` manual, cambio de DNS de `produccion.vialtec.app` — lo hace
Federico, Claude no tiene acceso al proveedor —, verificación post-corte,
baja del legado, y recién ahí cerrar la RLS abierta de `kv_store`).
Actualizado hoy solo con la nota de esta re-verificación (punto 2 del
checklist).

**Conclusión**: el script y el plan estaban **estables y listos** — dos
corridas de dry-run en días distintos dieron resultados idénticos, sin
ninguna colisión ni inconsistencia.

**Archivos tocados**: solo `supabase/scripts/CHECKLIST_CORTE_FINAL.md`
(nota actualizada) y este archivo. `auditoria_delta_desde_01_09.sql` y
`migracion_final_corte.sql` no necesitaron cambios — se re-ejecutaron tal
cual (el archivo del script sigue terminando en `rollback;` en el repo,
a propósito — la corrida real de abajo se ejecutó pasando la misma
consulta con `commit;` directo, sin modificar el archivo, para que quede
disponible como herramienta de dry-run segura por default si hiciera
falta re-auditar algo más adelante).

## 🎯 MIGRACIÓN REAL EJECUTADA — 2026-09-07, confirmada por Federico

Federico aprobó explícitamente los 3 puntos pendientes y dio la orden de
ejecución real: *"1. Opción de Stock: Seleccionamos la OPCIÓN A... 2.
Ejecución Definitiva: Procede a correr el script de migración final
definitivo (impacto real, sin rollback)... 3. Registro de Git..."*

**1) Decisión de stock — Opción A confirmada**: `plantas_stock` NO se
tocó. El balance final sigue siendo el que el sistema nuevo viene
calculando de forma independiente desde el 01/09 (despachos, báscula,
movimientos manuales) — no se sobreescribió con el snapshot del legado,
tal como estaba planteado en `migracion_final_corte.sql`. El relevamiento
del 2026-09-03 en el legado queda sin reconciliar contra el sistema nuevo
(decisión consciente, no un olvido).

**2) Migración ejecutada con `commit` real** (mismo query que los dos
dry-runs anteriores, palabra por palabra, solo cambiando `rollback;` por
`commit;` al final — ninguna otra diferencia de lógica):

| Tabla | Antes | Después | Delta |
|---|---|---|---|
| `plantas_pedidos` | 184 | **188** | +4 |
| `plantas_pedidos_historial` | 543 | **561** | +18 |
| `plantas_cargas_hormigon` | 114 | **119** | +5 |
| `plantas_vales` | 885 | **908** | +23 (20 asfalto + 3 ingreso_arido) |
| `plantas_ingresos` | 500 | **503** | +3 |
| `plantas_stock_movimientos` | 786 | **789** | +3 |

`setval()` ejecutado: `secuencia_actual` = `max_vale_real` = **10016** —
sincronizado, sin colisión con el bloque sintético 90000001-90000500.
3 chequeos de integridad post-commit: **0** `numero_vale` duplicado,
**0** `id_legado` duplicado en pedidos, **0** ingresos huérfanos.
**Verificado con una consulta independiente después del commit** (no
solo dentro de la misma transacción) — los conteos de arriba persisten:
la migración quedó aplicada de verdad, no es un resultado de dry-run.

Esto captura el delta completo acumulado en el legado desde el 01/09 —
el sistema nuevo ahora tiene el historial completo de pedidos, vales de
báscula (asfalto + áridos) y movimientos de stock hasta el momento del
corte.

**3) Commit de Git**: ver el commit inmediatamente siguiente a esta
entrada en el log — incluye esta actualización de `pending.md` +
`CHECKLIST_CORTE_FINAL.md` (los únicos archivos con cambios pendientes,
la migración en sí vive en Supabase, no en el repo de código).

**Pendiente inmediato** (checklist, secciones 5-9 de
`CHECKLIST_CORTE_FINAL.md`, en orden): `npx vercel --prod` (manual,
Federico lo dispara), cambio de DNS de `produccion.vialtec.app` (lo hace
Federico, sin acceso de Claude al proveedor), smoke test post-corte contra
el dominio real, dar de baja el legado como fuente de escritura, y
**recién ahí** cerrar la RLS abierta de `kv_store` (hallazgo de seguridad
conocido, seguro de resolver solo con el legado ya apagado).

## 2026-09-06 — Hormigón pre-mayo/2026 del Excel sumado al acumulado

Federico preguntó si el hormigón del Excel (ene-abr/2026, mismo archivo que
Ammann 140) ya estaba sumado — no lo estaba, solo había tomado las filas
"Carpeta Asf" para el total de asfalto Ammann. Corregido: `HORMIGON_PRE_MAYO_2026_M3
= 3621.7` (suma de filas "H-xx"/"Mezcla Cemento" del Excel, ene 1371.5 + feb
1325.3 + mar 544.8 + abr 380.1) agregada en
`src/services/despachos.service.js#fetchAcumuladoHistorico()`, sumada al
acumulado en vivo del sistema — sin diferenciar por planta (Federico: "el
hormigón va todo junto"). Afecta el KPI "Total hormigón acumulado" de
Despachos.

**Resuelto** — le pregunté a Federico por "Salida 0/6" (549.6) y "Salida
Arena" (10) del mismo Excel: confirmó que esas dos NO se cuentan en ningún
total (no son producción de mezcla). `AMMANN_2026_TN` queda como estaba
(11916.71 tn, solo "Carpeta Asf").

También agregada la card "Producción de hormigón — año 2026" en Home (1 sola
card, sin diferenciar planta) vía `fetchProduccionAnualHormigon()` en
`dashboard.service.js` — mismo total (histórico Excel + en vivo desde mayo)
que ahora ve Despachos en su KPI "Total hormigón acumulado".

## Otros pendientes

- Definir el mapeo de los 7 roles del sistema anterior (`admin`, `plantista`,
  `encargado`, `supervisor`, `balancero`, `gerencia`, `plantista_hormigon`) contra
  el modelo de roles/usuarios ya existente en `flota_*`.
- Decidir si el flujo de invite de usuarios a Supabase Auth se automatiza en este
  proyecto (en el sistema anterior era manual — problema conocido, nunca
  resuelto).
- Definir el helper `fetchPaginado()` mencionado en `architecture.md` como
  utilidad común antes de escribir el primer service que liste una tabla grande.
