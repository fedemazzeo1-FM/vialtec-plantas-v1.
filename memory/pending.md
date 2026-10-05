# pending.md — Pendientes vigentes

## ▶ RETOMAR AQUÍ (actualizado 2026-10-03, cierre de sesión)

Estado al cerrar: árbol limpio, producción al día con el último commit de
código (deploy `dpl_YpYgcNTjZ57xAkwiyGdWcPqFHMeT`, 2026-10-02). ~35 commits
locales sin push (lo corre Federico: `git push origin main`).

### Auditoría — etapa 1 (migración 51) APLICADA en producción (2026-10-05)

`supabase/migrations/51_funciones_escritura_sin_anon.sql` aplicada con OK de
Federico (`apply_migration`). Antes: dry-run repetido (4 chequeos OK,
revertido) y revisión de los logs de la API de 7 días (28/09 al 05/10): las
llamadas a las 13 RPC fueron todas con rol `authenticated` desde
`produccion.vialtec.app`, ninguna como `anon`. Verificado post-aplicación en
`proacl`: las 13 quedaron con postgres, authenticated y service_role, sin
anon. Sin cambios de frontend, no requiere deploy. Siguen con `anon` a
propósito: helpers de RLS (plantas_rol_actual, plantas_tiene_permiso,
plantas_puede_ver_*), `plantas_etiqueta_vale`, `plantas_buscar_material_id`,
`plantas_calcular_consumo_kg` y `rls_auto_enable`. Sin probar en la app con
sesión real de cada rol (queda para la etapa 6).

### Migración 52 — número correlativo de pedido — APLICADA (2026-10-05)

`plantas_pedidos.numero` (integer, NOT NULL, UNIQUE, secuencia
`plantas_pedidos_numero_seq`) + `plantas_etiqueta_pedido(n)` → 'P-0001'.
Decisiones de Federico: una sola numeración para todos los tipos; el residual
toma número nuevo propio; huecos aceptados (no se reutiliza). Dry-run
(`supabase/scripts/dry_run_migracion_52.sql`, 7 chequeos OK) y aplicada con
OK. Verificado post-aplicación: 229 pedidos P-0001..P-0229 por orden de
creación, sin nulos ni repetidos, secuencia en 229, sin USAGE de la secuencia
para anon/authenticated. No se recreó ninguna función (crear_pedido y el
residual de finalizar_despacho toman el DEFAULT). Sin probar: residual real
(el dry-run no llamó a finalizar_despacho para no consumir un N° de remito).

### Auditoría — etapa 2 (migración 53) APLICADA (2026-10-05)

`plantas_auditoria_entidades` (catálogo, 20 filas), `plantas_auditoria`
(vacía) y `plantas_auditar(tipo_accion, modulo, entidad, entidad_ref,
entidad_label, motivo, antes, despues)`. Decisiones de Federico: trigger que
rechaza UPDATE/DELETE/TRUNCATE (también por SQL directo; para corregir una
fila hay que desactivarlo a propósito); catálogo en tabla; CREAR/ELIMINAR
guardan el registro completo y el resto solo lo cambiado, nunca
`datos_legados`; un EDITAR sin cambios no genera fila (devuelve null).
`plantas_auditar` NO tiene EXECUTE para anon ni authenticated (más estricto
que el plan original): solo la llaman funciones SECURITY DEFINER y triggers
SECURITY DEFINER. Lectura: policy fija rol admin en las dos tablas.
Dry-run (`supabase/scripts/dry_run_migracion_53.sql`, 9 chequeos OK) y
aplicada con OK; verificado post-aplicación (RLS, policies, grants, triggers,
índices, proacl). Lectura probada con admin y plantista; los otros 5 roles
usan la misma policy, sin ejecutar uno por uno. La tabla queda vacía hasta la
etapa 3.

### Cuenta compartida "balanza" — PENDIENTE de Federico (2026-10-05)

`balanza@vialtec.com.ar` (rol balancero) se usa desde 2 dispositivos con 2
sesiones abiertas (logs 28/09–05/10): PC Windows/Chrome por Starlink (sesión
`9c3c70d7-…`, desde 15/09, casi toda la actividad) y celular Android/Chrome
(sesión `675384fd-…`, desde 24/09; usado el 28/09 por red móvil y el 30/09
21:34 desde una conexión fija en Laferrere). El 28/09 hubo 10 minutos de uso
simultáneo. En la auditoría todo figura como "balanza" sin distinguir persona.
**A hacer cuando Federico sepa quiénes son:** crear un usuario individual por
balancero (Supabase Auth + `plantas_usuarios_roles` rol balancero) y dar de
baja la cuenta compartida: cerrar sus sesiones (primero la del celular) y
desactivarla. No hacer nada hasta que Federico pase los nombres.

### Frontend del N° de pedido — EN PRODUCCIÓN (2026-10-05)

Commits `a73e90f` (tarjeta de Pedidos + avisos de WhatsApp), `06523e4`
(buscador por N° en los filtros de Pedidos, solo desktop: busca en todo el
historial e ignora el resto de los filtros), `d7d48ef` (columna N° en
Despachos + Excel del filtro), `f7e7814` (selectores de pedido de Báscula +
línea "Pedido: P-0230" en el remito impreso). Helpers
`formatearNumeroPedido`/`parsearNumeroPedido` en `src/services/formato-numeros.js`.
Deploy `vialtec-plantas-v2-rom11ujvk` (el primer intento dio "Not authorized",
el reintento pasó). Verificado en vivo con sesión admin: Pedidos muestra el
número, el buscador encuentra P-0001, Despachos tiene la columna, el selector
de Báscula lo muestra, sin errores de consola. Sin probar: mensaje de
WhatsApp, remito impreso y Excel abiertos de verdad; el informe mensual NO
lleva el número (no se tocó).

### Auditoría — etapa 3 (migraciones 54 a 59) APLICADA (2026-10-05)

Las 18 RPC registran en `plantas_auditoria` dentro de la misma transacción
(si la auditoría falla, la operación no se hace). Aplicadas en orden con OK
de Federico; verificado después: md5 de las 18 en producción = cuerpos
generados localmente (`supabase/scripts/referencia_funciones_auditadas.sql`),
todas SECURITY DEFINER, con `authenticated` y sin `anon`; helpers sin EXECUTE
para anon/authenticated; `plantas__auditoria_patch` borrada.
- Método: las migraciones no reescriben los cuerpos; parchean
  `pg_get_functiondef` de producción con md5 antes/después. Los 18 cuerpos
  previos coincidían con el repo (2 solo diferían en comentarios).
- Dry-run completo: `supabase/scripts/dry_run_etapa3_auditoria.sql` (27 filas,
  admin/plantista/balancero). Bloquea pedidos/vales/remitos manuales/auditoría
  y devuelve las secuencias; usar ese patrón para cualquier ensayo que llame a
  RPC que consumen numeración.
- Qué registra cada una: pedidos CREAR/EDITAR/CAMBIAR_ESTADO (confirmar,
  postergar, archivar)/ANULAR (cancelar); despacho CAMBIAR_ESTADO (finalizar,
  + CREAR del pedido residual) y CORREGIR/EDITAR; cargas CREAR; vale CREAR
  (con los datos del ingreso de áridos adentro — decisión de Federico, sin
  fila aparte de `ingreso`)/EDITAR/ANULAR/REASIGNAR; movimiento manual CREAR;
  relevamiento UNA fila con la lista de ajustes (kg redondeados a 2
  decimales); remito manual CREAR; usuario_rol CREAR/EDITAR.
- Sin probar con uso real todavía (la tabla tenía 0 filas al cerrar la
  aplicación); roles encargado/supervisor/gerencia/plantista_hormigon quedan
  para la etapa 6.

### ▶▶ PARA RETOMAR (actualizado 2026-10-05 20:45)

**Estado:** etapas 1 a 4 de Auditoría APLICADAS, y desde hoy 20:35 también
las migraciones 60 y 62 (motivo obligatorio en correcciones y al eliminar en
Maestros) con su frontend EN PRODUCCIÓN (deploy
`vialtec-plantas-v2-kk5rqt0ph`, bundle `index-sU4CBIYR.js`). Antes de aplicar
se revisaron los logs (sin escrituras en 20 min). Verificado: md5 de
`corregir_despacho` `64c25609…` y `corregir_vale_bascula` `f1c5e2d4…` (12
parámetros), `plantas_eliminar_maestro` sin anon; en vivo con sesión admin,
los modales de Maestros (eliminar), Báscula (editar vale) y Despachos
(corregir) piden el motivo y no dejan guardar sin él. No se guardó ninguna
corrección ni eliminación real de prueba. La reversión
(`revertir_migraciones_60_62.sql`) quedó probada pero no hizo falta.

**Etapa 5 — pantalla `/auditoria`: EN PRODUCCIÓN (2026-10-05 noche).**
Federico la revisó en localhost y la aprobó; merge de `auditoria-pantalla` a
main (`554b65b`), deploy `vialtec-plantas-v2-rntb188h2`, bundle
`index-DQkv49EA.js` servido. Solo admin: link y ruta usan el tab 'usuarios'
(candado fijo de `puedeVerTab`), y la base devuelve 0 filas a los otros 6
roles (verificado simulando un usuario de cada rol: admin 1 fila/20
entidades, el resto 0/0). NO verificado en el navegador de producción después
del deploy (la extensión de Chrome se desconectó) ni con sesiones reales de
otros roles: queda para la etapa 6.

**PASO C — etapa 6:** probar con un usuario de cada rol (7) en navegador
limpio — las contraseñas las tiene que ingresar una persona — y revisar
401/403 en logs; agregar a `procedimientos.md` que toda corrección por SQL
lleva su fila de auditoría y que un DELETE por SQL en tablas con trigger
necesita `select set_config('plantas.motivo_eliminacion', '...', true)` en la
misma transacción.

**Otros pendientes de Federico:** usuarios individuales por balancero y baja
de la cuenta `balanza` (abajo). Ensayos que consumen numeración: usar el
patrón de `dry_run_etapa3_auditoria.sql` (lock + setval, con bloque
`exception` que restaura también si falla).

### Detalle del paso A — migraciones 60 y 62 (motivo obligatorio)

- 60 (commit `cd4744d`): `corregir_despacho` rechaza sin notas;
  `corregir_vale_bascula` suma `p_motivo` (drop + create), guarda el motivo en
  `plantas_vales_historial`; siempre CORREGIR; sin cambios no deja fila.
- 62 (commit `367b73b`): `plantas_eliminar_maestro(tabla, id, motivo)`
  (SECURITY INVOKER: valen las policies de RLS) + `plantas_trg_auditar`
  rechaza un DELETE sin motivo en las 10 tablas con trigger.
- Con las migraciones aplicadas y el frontend viejo: no se puede editar
  vales, corregir despachos sin notas ni eliminar en Maestros.

### Auditoría etapa 4 (migración 61) — APLICADA (2026-10-05)

Trigger genérico `plantas_trg_auditar` (SECURITY DEFINER) en fórmulas,
materiales, proveedores, clientes, encargados, choferes, patentes, roles,
permisos y obras_locales. Dry-run `dry_run_migracion_61.sql` (21 filas).
Sin doble registro: se saltea con `pg_trigger_depth() > 1` (renombre de
material → 1 fila); los permisos borrados en cascada con su rol no dejan fila
(el cascade NO cuenta como trigger anidado; se detecta porque el rol ya no
existe). Solo cambia activo/habilitado = CAMBIAR_ESTADO; obras = siempre
CAMBIAR_ESTADO; cambio de `tipo` de fórmula = fila aparte "CAMBIO DE TIPO";
permisos: solo celdas que cambian (al crear un rol, solo las habilitadas).

### Deploy automático de Vercel desde GitHub — DESACTIVADO (2026-10-05)

El push del 05/10 (primero desde una sesión de Claude) disparó un deploy a
producción por la integración de Git (`dpl_CHaippT1HcQu1CHnG6GXaZnQYdgd`,
mismo bundle que el manual, sin efecto visible). Se agregó
`"git": { "deploymentEnabled": false }` a `vercel.json` (commit `802b0c3`);
el push siguiente ya no generó deploy. `npx vercel --prod` sigue funcionando
igual. Si alguna vez reaparece un deploy tras un push, revisar eso primero.
Primera fila real de auditoría: 05/10 16:37, balanza, EDITAR vale I-00607.

### Módulo de Auditoría — plan aprobado (2026-10-03)

Base: spec de auditoría de flota §6 (tabla propia, mejoras de 6.2, checklist
6.3). Objetivo de Federico: que lo vea solo él (admin) y saber quién hizo cada
acción. Tablas `flota_*`: solo lectura.

**Decisiones de Federico:**
1. Lectura solo admin, FIJA en la base (policy por rol admin, no por la matriz
   de permisos editable). Hoy hay 1 admin activo.
2. Triggers: verificar que ninguna de las 17 RPC escriba en tablas que van a
   tener trigger; si alguna lo hace, que el mismo cambio no se registre dos
   veces. Caso ya conocido: `plantas_trg_material_renombrado` (migración 50)
   reescribe `plantas_formulas` al renombrar un material → el trigger de
   fórmulas no debe duplicar el registro del renombre.
3. Número correlativo de pedido (P-0001): traer la PROPUESTA antes de la
   etapa 5 (cambio aparte). Numeración segura ante concurrencia (secuencia),
   asignada a los pedidos existentes por orden de creación, visible en
   pantallas, WhatsApp y remitos. La auditoría tiene que buscar por ese número.
4. Los historiales existentes (`plantas_pedidos_historial`, 679 filas;
   `plantas_vales_historial`, 8) NO se copian. La auditoría arranca vacía y
   los historiales se mantienen.
5. Pantalla con exportar a Excel del listado filtrado: todas las filas del
   filtro (paginado de a 1000, orden fecha_hora, id), no solo la página.

**Diseño (adaptación de 6.2):**
- `plantas_auditoria`: id, fecha_hora, fecha_negocio, usuario_email,
  usuario_id (auth.uid), usuario_nombre, usuario_rol, tipo_accion (CHECK:
  CREAR, EDITAR, CAMBIAR_ESTADO, ANULAR, CORREGIR, REASIGNAR, ELIMINAR),
  modulo/entidad (catálogo cerrado), entidad_ref text, entidad_label, motivo
  (obligatorio por CHECK en ANULAR/CORREGIR/REASIGNAR/ELIMINAR),
  valores_antes/valores_despues jsonb, dispositivo opcional (derivado del
  user-agent de request.headers, no del cliente).
- `plantas_auditar(...)` SECURITY DEFINER, search_path fijo, sin EXECUTE para
  anon: la identidad sale de auth.jwt() + plantas_usuarios_roles + nombre de
  flota_usuarios_email (lectura). Sin sesión (SQL directo) → usuario
  'sistema (SQL)'. Nadie inserta directo en la tabla (sin grants de escritura
  para anon/authenticated; revoke update/delete/truncate).
- Índices: (fecha_hora desc, id desc), (entidad, entidad_ref),
  (usuario_email, fecha_hora desc).
- Etiqueta por función por entidad ("Vale 10188 — Pedido 30/09 — Obra —
  189,84 tn").

**Etapas (cada una: dry-run, OK de Federico, commit):**
1. ~~Seguridad: migración 51.~~ APLICADA 2026-10-05.
2. ~~Tabla + `plantas_auditar` + catálogos + índices + RLS solo admin + grants
   mínimos.~~ APLICADA 2026-10-05 (migración 53).
3. (APLICADA 2026-10-05, migraciones 54 a 59.) Las 17 RPC auditan adentro, en la misma transacción (si falla la auditoría
   falla la operación). Recrearlas desde `pg_get_functiondef` de producción,
   dry-run por grupo: pedidos/despachos, báscula, stock, remitos, usuarios.
   Las 17: crear/actualizar/confirmar/cancelar/postergar/archivar_pedido,
   finalizar_despacho, corregir_despacho, registrar_carga_asfalto,
   registrar_carga_hormigon, registrar_pesada_bascula, corregir_vale_bascula,
   anular_vale_bascula, reasignar_vale_bascula, registrar_movimiento_manual,
   registrar_relevamiento_stock, generar_remito_manual (+
   admin_upsert_usuario_rol).
4. Triggers AFTER sobre lo que la app escribe directo: `plantas_formulas`
   (cambio de `tipo` marcado aparte: define unidad y circuito; los pedidos
   existentes conservan el tipo copiado al crearlos), maestros vía
   `crudEntidad` (materiales, proveedores, clientes, encargados, choferes,
   patentes), `plantas_roles`, `plantas_permisos`, `plantas_obras_locales`.
   Aplicar la decisión 2 (sin doble registro).
5. Pantalla `/auditoria` (solo admin, solo desktop): filtros en la URL
   (usuario, módulo, acción, desde/hasta, N° de vale/remito/pedido),
   paginación server-side de 50 con desempate por id, detalle antes/después,
   exportar Excel del filtro completo. Antes: propuesta del N° de pedido
   (decisión 3).
6. Prueba con cada rol real en navegador limpio + revisar 401/403 en logs;
   sumar a `procedimientos.md` que toda corrección por SQL lleva su fila de
   auditoría.

**Checklist de entidades:** pedidos/pedido (crear, editar, confirmar,
postergar con fechas, archivar, cancelar con motivo); despachos/despacho
(finalizar con residual, corregir), carga_asfalto, carga_hormigon;
bascula/vale (crear con datos del ingreso, corregir, anular, reasignar),
ingreso; stock/movimiento_manual, relevamiento (los descuentos automáticos se
auditan en la entidad origen); remitos/remito_manual; formulas/formula (crear,
editar insumos y dosajes, cambio de tipo, activar/desactivar);
maestros/material (incluye renombres), cliente, proveedor, chofer, patente,
encargado, obra_local; usuarios/usuario_rol, rol, permiso. Precios/ventas: no
aplica (plantas no tiene columnas de precio; las ventas externas son pedidos
tipo 'venta', auditados como pedido).

**No aplica de la spec de flota:** usuarios PIN / fn_auditoria_pin /
LOGIN_FALLIDO (plantas solo usa email de Supabase Auth); auditService.log
desde el cliente y "falla en silencio" (acá se audita en la transacción);
idParaAuditoria (entidad_ref text); usuario_id de dos orígenes; columna ip;
lectura para cualquier logueado; flota_audit_log.

**Estado actual relevado (2026-10-03):** sin rastro hoy: edición/archivado de
pedidos, cargas, movimientos manuales y relevamientos (solo el movimiento),
fórmulas, maestros, roles, permisos, obras archivadas. Las correcciones por
SQL del 29/09 y 01/10 quedaron en el historial sin usuario (lección 5.5).

---

### Pendientes anteriores (2026-10-01)

**Abierto, en orden:**
1. **Push a GitHub**: ~24 commits locales sin subir. Lo corre Federico
   (`git push origin main`); desde la sesión de Claude el push fue bloqueado
   dos veces por el clasificador de permisos, no reintentar.
2. **Excel de septiembre "antes" vs "después"** (mezcla cemento): Federico
   exportó el "antes" pero no está en `~/Downloads` de esta máquina; falta que
   diga dónde quedó. "Después": `~/Downloads/Informe Plantas prod. SEPTIEMBRE
   2026 (13).xlsx`. Diferencias esperadas: solo hoja "Resumen anual" (columna
   Mezcla cemento con 6,00 en mayo; hormigón de mayo 398,2 → 392,2).
3. **Imágenes para email**: Federico tiene que probar "Copiar imagen" y
   "Descargar PDF" (no probados), y decidir si mezcla cemento se queda en la
   tabla anual y el gráfico (hoy aparece por las 6 tn de mayo).
4. **Consumo de insumos**: Federico compara los valores nuevos de septiembre
   contra sus ajustes manuales. Quedó el criterio A (fórmula × cantidad);
   alternativa B = lo realmente descontado de stock, si lo pide.
5. ~~Fórmula H-13 fuera de catálogo~~ — **resuelto por la migración 50
   (APLICADA 2026-10-02, OK de Federico)**: catálogo unificado con la lista
   oficial (ver `business-rules.md` §Catálogo de materiales). Respaldo del
   estado previo en `plantas_respaldo_mig50` (688 filas). Verificado
   post-aplicación: stock 6.170.964,67 kg y 1.603 movimientos sin cambio;
   fórmulas/ingresos/vales solo con nombres del catálogo; 4 triggers + 2 FK
   activos; helpers sin EXECUTE para anon/authenticated. Dry-run:
   `supabase/scripts/dry_run_migracion_50.sql` (8 chequeos OK). Sin probar en
   la UI con sesión (Báscula/Fórmulas/Stock/Analítica con los nombres nuevos).
   El vale GAS-OIL del 01/10 no movió stock porque estaba en 0 (piso); ahora
   GAS-OIL no controla stock. Nombre corregido a "HORMIGON H-13" (UPDATE directo, OK de Federico, 2026-10-02).
5b. **2026-10-02 (commits `2f1faf2`, `e2161f2`, EN PRODUCCIÓN, deploy `dpl_5cj7n8HU27U7Pbhburk4Det9L7q1`)**: el Excel marca
   insumos fuera del catálogo en "Consumo de insumos"; botón "Copiar las 3
   juntas" en el modal de imágenes para email (HTML con PNG embebidos — sin
   probar pegando en Gmail/Outlook). Auditoría sep/2026: informe = SQL exacto;
   el stock descontado quedó por debajo del teórico (CA30 −12,8 tn: 7 pedidos
   CAC19 del 02 al 11/09 sin movimiento de CA30; 3 pedidos legado sin
   movimiento). Causa del CA30 sin confirmar.
6. **KPI "Asfalto (período)" de Pedidos** suma pedidos cancelados (ver §10).
7. **Optimización de rendimiento — FASE 1 a medio hacer** (§9). Hecho y ya en
   producción: desempate por `id` (`fd79bea`). Siguiente paso: ítems 1+6
   (columnas explícitas en Despachos).

**2026-10-02: acumulado anual mobile + fecha en selector de Báscula — EN
PRODUCCIÓN** (deploy `dpl_YpYgcNTjZ57xAkwiyGdWcPqFHMeT`, commits `b289581`,
`8620bad`). Tarjeta "Acumulado 2026" (asfalto total + Ammann 140 / Marini 180,
hormigón) arriba de Pedidos, solo mobile y solo admin/gerencia
(`ResumenAnualMobile.vue` + `useResumenAnualMobile.js`); en mobile no hay Home
y esos roles aterrizan en Pedidos. Restricción de UI, no de datos. Atada a 2026
(constantes de Ammann/pre-mayo en `dashboard.service.js`): revisar en ene/2027.
Selector de Vale Asfalto: "OBRA — 19.98 tn (confirmado - 02/10/2026)"
(`etiquetaPedidoPesada`). Sin probar en vivo con sesión.

**2026-10-01: informe mensual — EN PRODUCCIÓN** (deploy
`dpl_7faWdK4My1udebzp6zmWHVn1bs4V`). Verificado en vivo: el Excel de
septiembre da Arena 0/6 2.766,58 / Piedra 6/20 2.590,65 / total 5.729,68 tn
(igual al cálculo contra la base) y el resto del archivo no cambió; el modal
"Imágenes para email" genera las 3 piezas (2700 px). Sin probar: copiar al
portapapeles y Descargar PDF. Push a GitHub pendiente (lo corre Federico).
Detalle de los dos cambios:
- `4837c83` Consumo de insumos = fórmula × cantidad despachada de los pedidos
  del mes (`fetchConsumoInsumosDelMes`, usa la fórmula vigente al exportar).
  Antes sumaba movimientos `egreso_despacho` por fecha del movimiento: los
  despachos del 30/09 cerrados el 01/10 (~849 tn de insumos) caían en octubre,
  no contaba `recalculo_despacho`, y los pedidos del legado sin movimiento no
  aportaban. Sep/2026 arena 0/6: 2.318 tn (antes) vs 2.766,58 tn (verificado
  en el Excel exportado tras el deploy).
- `6bc49fa` Botón "Imágenes para email" en Despachos → Resumen por obra:
  `ReporteEjecutivoMensual.vue` + `useReporteEjecutivo.js` +
  `src/services/imagen-reporte.js` (html2canvas escala 3, copiar al
  portapapeles, PNG, PDF). Probado en local con datos reales de septiembre en
  una página temporal (ya borrada) y dentro de la app tras el deploy (modal
  con las 3 piezas).
  Lección: el reset de Tailwind `img{display:block}` corre el texto hacia
  abajo en html2canvas; `imagen-reporte.js` lo neutraliza durante la captura
  (`pdf-imprimible.js` no lo hace).

**2026-10-01: leyenda de vales del remito por tramos — EN PRODUCCIÓN**
(deploy `dpl_X2F6VyX5bbvhbTvny1EizeYc81vF`). `leyendaValesRemito()` en
`bascula.service.js`: "correlativos" solo si no hay saltos; con saltos, tramos
("N° 00010165 al 00010167, 00010182 al 00010183, 00010188 (6 pesadas)");
"entre N° X y N° Y (no correlativas)" solo si pasa de 300 caracteres (con
datos reales el máximo son 4 tramos). Verificado en vivo con los remitos de
los vales 10188 y 10189 del 30/09.

**2026-10-01: tercer tipo de producto `mezcla_cemento` — EN PRODUCCIÓN**
(migración 49 + deploy `dpl_Bqg18iWQKVGTqq21mLYnC11TpecY`). Ver §10.
Pendiente: (1) `git push origin main` (lo corre Federico; el push desde la
sesión fue bloqueado), (2) comparar el informe mensual de septiembre "antes"
(lo exportó Federico, falta que diga dónde está) contra el "después"
(`~/Downloads/Informe Plantas prod. SEPTIEMBRE 2026 (13).xlsx`).

**2026-10-01: Fórmulas — insumo con desplegable del catálogo de materiales**
(`4887717`, deployado `dpl_6RoVbmMsR4s4JWfXdDbMtA62oTmJ`; el deploy incluyó
también `fd79bea`). El insumo ya no es texto libre: `datalist` sobre
`plantas_materiales` activos + validación al guardar. Sin probar en vivo con
sesión. **Abierto**: la fórmula "HORMIGON  H-13" tiene 6 insumos que no
existen en el catálogo (AD PLAS, Arena 0-6, Arena silicea, Piedra 6-20,
Piedra 10-30, Cemento CP 40) — no descuenta stock hasta que se corrija
(editándola desde la UI o con UPDATE, previa confirmación de Federico).

- Contraste UI: Federico pidió bajarlo dos veces; valores finales casi
  iguales al original (border `#E6E9EE`, fondo `#FAFBFC`, shadow-sm por
  default). No volver a reforzarlo sin que lo pida.


**2026-09-30: migraciones 47, 48 y 48b APLICADAS + deploy verificado en
vivo** (Stock → Analítica de proveedores y Báscula, con sesión de Federico).
Ver §5e. Además: contraste UI (tokens `border`/`fondo`/`panel` en
`tailwind.config.js` — dos intentos más marcados se descartaron por pesados,
quedó casi igual al original) y barras de scroll horizontal espejo
en `VTable` (arriba + flotante al pie, `useScrollHorizontalEspejo.js`).


**2026-09-29: migración 46 aplicada + corrección de datos de Autovía Mercosur**
(confirmación explícita de Federico). Ver §5c. Sin cambios de frontend, no
requiere deploy. Mismo día: revisión general Resumen vs Detalle de Pesadas en
todas las obras + corrección de vales mal ligados en 4 obras (§5d).


**2026-09-28: migración 45 aplicada + deploy** (confirmación explícita de
Federico). Ver §5b. Deploy `dpl_46GzZuDdboRKhwKmztXNo5AzsunH`,
`produccion.vialtec.app` sirve el bundle nuevo. Incluye también la columna
"Fecha/Hora" del listado de Báscula (`28/09/2026 11:05`, 24 hs) — verificada
en vivo.

**Migraciones 42, 43 y 44 ya aplicadas en producción** (2026-09-22,
confirmación explícita de Federico en cada una — ver §2, §3 y §5 para el
detalle y la verificación post-aplicación de cada una). Deploy corrido y
verificado el mismo día (`npm run build` + `npx vercel --prod`,
`produccion.vialtec.app` responde 200 con el deployment nuevo).

Pendientes para la próxima sesión (requieren confirmación explícita de
Federico donde aplique):
1. Revisar las funciones de flota expuestas a `anon` (§4, alto) — es el
   hallazgo de mayor severidad que sigue abierto de la auditoría del 19/09.
2. Camiones/balancero: Federico reportó que balancero no puede editar en
   Maestros → Camiones, pero la investigación (código + estado real de
   producción: RLS, grants, logs de Edge) no encontró ningún bloqueo — todo
   da correcto. Falta el mensaje de error exacto o el email de prueba para
   poder reproducirlo; no tocar nada ahí sin eso.
3. Verificación en vivo opcional (no bloqueante): Stock → Historial y Báscula
   con un usuario real, para confirmar que la migración 43 no rompió nada de
   la UI (la corrección de seguridad en sí ya está activa y verificada a
   nivel de base).

Detalle completo de la auditoría: `memory/auditoria-2026-09-19.md`.

> Solo lo que está ABIERTO o es estado actual. El historial completo (3100 líneas,
> hasta 2026-09-19: migración de datos, corte legado → nuevo, fixes de Báscula,
> Stock, Pedidos, Mobile, etc.) está archivado sin cambios en
> `memory/archivo/pending-historico-hasta-2026-09-19.md`. Consultarlo con grep
> cuando haga falta el detalle de una decisión; no hace falta leerlo entero.
> Regla: cuando algo se cierra, se saca de acá y su detalle vive en el archivo.

## 1. Migraciones — estado real (verificado contra producción 2026-09-19)

| N° | Contenido | Estado |
|----|-----------|--------|
| 35 | `plantas_clientes` + tab Clientes en Maestros | **Aplicada** (tabla existe, 3 filas). Este archivo la daba por pendiente: estaba desactualizado. |
| 36 | Remito automático + `plantas_remitos_manuales` | **Aplicada** (tabla existe). |
| 37 | `plantas_remitos_manuales_items` | **Aplicada** (tabla existe). |
| 38–41 | Remito residual hereda N°, remito con origen en Báscula, CRUD camiones, edición de pedidos por creador | Sin verificar una por una. La 40 tiene evidencia (policies de `plantas_patentes` por balancero). |
| 42 | Numeración propia ingreso/egreso de áridos (`I-00001`) | **APLICADA en producción (2026-09-22).** Ver §2. |
| 43 | Seguridad: revoke de helpers de stock + `security_invoker` en 2 vistas | **APLICADA en producción (2026-09-22).** Ver §3. |
| 44 | Ingreso de áridos: `cantidad_remito` obligatoria en `registrar_pesada_bascula` (ya no se sustituye por el peso neto pesado) | **APLICADA en producción (2026-09-22).** Ver §5. |
| 48 | `reasignar_vale_bascula` + `plantas_vales_historial` (reasignación/edición/anulación de vales quedan registradas); 48b: sin TRUNCATE/REFERENCES/TRIGGER para `authenticated` en el historial | **APLICADA en producción (2026-09-30).** Ver §5e. |
| 47 | Editar/Eliminar vales de Báscula según la matriz (`bascula:editar`/`bascula:eliminar`); plantista habilitado en ambas; sin EXECUTE para `anon` | **APLICADA en producción (2026-09-30).** Ver §5e. |
| 46 | Pedido residual referencia al padre por fecha/cantidad/remito, no por UUID; `finalizar_despacho` sin EXECUTE para `anon` | **APLICADA en producción (2026-09-29).** Ver §5c. |
| 45 | Remito Manual: `unidad` por item (Tn/Kg/m³/Lts/Unidades) + `generar_remito_manual` la exige si hay cantidad | **APLICADA en producción (2026-09-28).** Ver §5b. |

## 2. Migración 42 — numeración `I-00001` — APLICADA en producción (2026-09-22)

Pedido de Federico: la numeración de asfalto no se mezcla con la de ingresos.
Ingreso y egreso de áridos comparten `plantas_vales.numero_vale_arido`
(`I-00001`, desde 1); `numero_vale` queda solo para asfalto/hormigón.
- Archivo: `supabase/migrations/42_numeracion_ingreso_egreso_aridos.sql`.
  `numero_vale` deja de ser identity (nullable, secuencia común que conserva su
  posición, próximo asfalto = 10065), renumera los 514 ingresos/egresos
  existentes por fecha guardando el N° previo en `datos_legados->>'numero_vale_previo'`,
  CHECK anti-mezcla, recrea `registrar_pesada_bascula`/`corregir_vale_bascula`/
  `anular_vale_bascula` y `plantas_v_bascula_viva`.
- Estado medido en producción antes de escribirla: asfalto 442 (9581–10064),
  ingreso 508, egreso 6 (3 anulados), secuencia en 10064.
- **Dry-run ejecutado contra producción y revertido (2026-09-22): OK.** Baseline
  al momento de correrlo: asfalto 489 (9581–10115), ingreso 512, egreso 6 (3
  anulados) = 518 áridos totales. Los 10 chequeos dieron OK: separación
  asfalto/hormigón (solo `numero_vale`) vs. áridos (solo `numero_vale_arido`,
  518 filas, denso 1..518, sin duplicados), `numero_vale_previo` guardado en
  las 518, constraint anti-mezcla sin violaciones, secuencia de asfalto
  preservada en 10115, secuencia de áridos en 518, `plantas_v_bascula_viva`
  sigue devolviendo las 1007 filas esperadas, 0 filas perdidas/ganadas.
  Verificado después con `information_schema.columns` que `numero_vale_arido`
  NO existe en producción (el ROLLBACK no dejó nada aplicado). Script:
  `supabase/scripts/dry_run_migracion_42.sql`.
- **Aplicada en producción (2026-09-22, `apply_migration`) — confirmación
  explícita de Federico ("dale, aplicá la migración 42").** Verificado
  post-aplicación: 490 asfalto/hormigón (subió de 489 a 490 entre el dry-run
  y la aplicación real — un vale real más cargado en el medio, no un error),
  518 áridos con `numero_vale_arido` denso 1..518 sin duplicados,
  `numero_vale_previo` guardado en las 518, constraint
  `plantas_vales_numeracion_por_tipo_chk` activa, `plantas_v_bascula_viva`
  responde 1008 filas (490+518, consistente). El header de Báscula ya puede
  consultar `numero_vale_arido` sin error.
- Los 6 egresos con N° de papel del legado también se renumeraron (decisión al
  elegir "ingreso y egreso comparten N°").
- Ya deployado: `npm run build` + `npx vercel --prod` corridos y verificados
  (2026-09-22) — el frontend ya consultaba `numero_vale_arido`, ahora la
  columna existe en producción.

## 3. Migración 43 — seguridad — APLICADA en producción (2026-09-22)

Archivo: `supabase/migrations/43_seguridad_helpers_stock_y_vistas.sql`.
Origen: auditoría del 2026-09-19. Autorizada por Federico.
1. `revoke execute` a public/anon/authenticated de `plantas_aplicar_movimiento_stock`,
   `plantas_descontar_stock_despacho`, `plantas_recalcular_stock_vale`. Eran
   SECURITY DEFINER sin chequeo de rol y ejecutables con la anon key pública:
   permitían mover stock real sin login. Sus 7 llamadores son SECURITY DEFINER
   con dueño postgres, no se rompen.
2. `security_invoker = true` en `plantas_v_stock_movimientos_viva` y
   `plantas_v_despachos_camion`. Sin login se leían 1382 movimientos de stock
   (con `responsable_email`) y 614 despachos por camión.
- **Dry-run ejecutado contra producción y revertido (2026-09-19): OK.** admin ve
  1382/614 (~20 ms), plantista 1382/614, encargado 1382/172 (por la matriz, que
  le da `stock:ver`; es intencional), anon 0/0; `anon` y `authenticated` sin
  EXECUTE en los 3 helpers; `registrar_pesada_bascula` sigue ejecutable.
- **Aplicada en producción (2026-09-22, `apply_migration`) — confirmación
  explícita de Federico.** El bloqueo del clasificador de sesiones anteriores
  ("Protected-Scope IaC Apply") no se repitió. Verificado post-aplicación
  directo en `pg_proc`/`pg_class`: los 3 helpers sin `EXECUTE` para
  `anon`/`authenticated`, las 2 vistas con `security_invoker=true` en
  `reloptions` (mismo criterio que `plantas_v_bascula_viva`, que ya lo tenía).
- Pendiente de verificación en vivo (no crítico, la corrección ya está activa):
  probar Stock → Historial y Báscula con un usuario real logueado para
  confirmar que nada se rompió del lado de la UI.

## 4. Auditoría 2026-09-19 — hallazgos abiertos

**Alto**
- Funciones de flota ejecutables por `anon` (`flota_set_pin`, `hash_pin`,
  `verify_pin`, `flota_auth_login`): SIN analizar, son del sistema de flota
  (tabla/proyecto compartido). Revisar sus cuerpos cuanto antes.
- Además de los 3 helpers de la 43: el resto de las RPC de Plantas siguen
  ejecutables por `anon` (validan rol adentro, pero no hace falta exponerlas);
  `rls_auto_enable()` también.

**Medio**
- `plantas_ingresos.numero_remito` sin UNIQUE: el duplicado solo se valida en la
  RPC (carrera posible entre dos pesadas simultáneas).
- Acciones de `PedidoCard` (8 botones) sin `:disabled`/`:loading`: doble clic
  probablemente muestra un error tras una acción exitosa.
- 68 lugares muestran `e.message` crudo de Postgres vs 30 con mensaje propio;
  29 `Promise.all` sin `allSettled` (una query caída vacía la pantalla).
- 16 materiales con `stock_minimo_kg` null: el semáforo y el banner de alerta de
  Home no pueden alertar bien.
- Vistas puente del legado (`plantas_v_bascula_viva`, `plantas_v_stock_movimientos_viva`):
  sus ramas de `kv_store` devuelven 0 filas hoy (código muerto) y el WindowAgg de
  `acumulado_dia_tn` recorre todo el historial (11 ms con 956 filas, crece lineal).
  Se pueden simplificar y recién ahí cerrar del todo la lectura de `kv_store`.
- `fetchProduccionAnualAsfalto/Hormigon` (Home) sin paginar; `fetchValesDeVariosPedidos`
  y `fetchCargasHormigonDeVariosPedidos` (Informe Mensual) con `.in()` sin
  paginar/lotear. Lejos del límite hoy (`plantas_vales`: 956 filas totales).
- Sin tests automáticos (no hay script `test`).
- Datos a revisar: 36 pedidos de asfalto y 14 de hormigón `despachado` sin
  vales ni cargas; 1 cancelado sin motivo (sin CHECK); 2 pedidos tipo obra sin
  `obra_id` (PRUEBAS-01, ya conocidos).

**Bajo**
- Helpers duplicados (`aTn` ×2, `aFechaISO` ×2, `rangoDelMes` ×3,
  `nombreDestinoPedido` ×2) y el patrón "hormigón m³ / asfalto tn" ×20.
- Exports sin uso: `fetchDetalleDespachosCamion`, `fetchResumenGeneral`,
  `getFormula`, `appConfig`.
- `useBascula.js` con 962 líneas.
- Índices FK faltantes: `plantas_ingresos.vale_id`, `plantas_stock_movimientos.vale_id`
  y `.ingreso_id`, `plantas_usuarios_roles.rol`.
- `plantas_patentes` con 7 policies solapadas; `search_path` mutable en
  `plantas_buscar_material_id` y `plantas_calcular_consumo_kg`; `pg_net` en
  `public`; protección de contraseñas filtradas desactivada.
- Logo de 112 KB mostrado a ~70×30 px.

No medido: tiempos de carga reales en navegador; el flujo de explotación del
punto 1 de la 43 no se probó (habría movido stock real).

## 5. Migración 44 — Cant. s/Remito obligatoria — APLICADA en producción (2026-09-22)

Bug reportado por Federico: en ingresos de proveedores (Báscula), "Cant.
s/Remito" (declarada por el proveedor) terminaba duplicando el peso
neto/bruto pesado por la báscula.

- Causa raíz: el frontend nunca exigía cargar `cantidad_remito` en el alta
  — cuando quedaba vacío, `registrar_pesada_bascula()` lo tapaba con
  `coalesce(p_cantidad_remito, v_neto_tn)` (el peso neto medido).
- Fix de dos capas: `useBascula.js#guardarPesada()`/`guardarEdicion()` ya
  exigen `cantidad_remito > 0` (mismo criterio que `numero_remito`),
  labels "(obligatorio)" en `BasculaView.vue`; y del lado del servidor,
  `supabase/migrations/44_ingreso_arido_cantidad_remito_obligatoria.sql`
  agrega la misma validación en la RPC y saca el `coalesce` (usa
  `p_cantidad_remito` directo tanto en el INSERT a `plantas_ingresos` como
  en el movimiento de stock).
- **Auditoría de datos históricos (2026-09-22, antes de aplicar el fix)**:
  de 512 ingresos desde el arranque del sistema (junio 2026), **487 (95%)
  tienen `cantidad`/`peso_neto` distintos** (correctos, confirma que el
  balancero sí cargaba los dos valores la mayoría de las veces) y **25
  (5%) coinciden exactamente** (hasta el gramo) — estadísticamente
  imposible por azar con pesos de 2 a 37 tn, son los casos reales
  afectados por el bug. Repartidos en todo el período (03/06 al 22/09,
  varios proveedores: Holcim, Avanzar, Cerro del Aguila, Cantera Pompeya,
  Transaridos). **Decisión de Federico: no se corrigen** (no hay forma de
  reconstruir el valor real declarado sin ir remito por remito) — quedan
  tal cual, documentados acá por si en algún momento se consigue el dato
  real y se quiere hacer la corrección manual.
- **Aplicada en producción (2026-09-22, `apply_migration`) — confirmación
  explícita de Federico.** Verificado post-aplicación: la validación nueva
  está presente en `pg_get_functiondef('registrar_pesada_bascula')`.

## 5b. Migración 45 — unidad de medida en Remito Manual — APLICADA (2026-09-28)

- Columna `plantas_remitos_manuales_items.unidad` + CHECK con la lista cerrada
  (misma que `UNIDADES_REMITO_MANUAL` en `remitos-manuales.service.js`).
  `generar_remito_manual` la guarda y rechaza cantidad sin unidad. Se imprime
  junto a la cantidad ("20 Unidades"). Los 11 remitos/17 items previos quedan
  con unidad null (se imprimen como antes).
- Verificado post-aplicación: columna, CHECK, RPC nueva, EXECUTE de
  `authenticated` intacto; en vivo, el selector aparece en el modal con las 5
  opciones. **No se generó un remito real de prueba** (consumiría un N°
  oficial de la secuencia): falta confirmar con el primer remito real que la
  unidad sale impresa.
- Remitos manuales no figuran en ningún Excel/reporte hoy; si se quiere un
  export, definir columnas con Federico.

## 5c. 2026-09-29 — Excel mensual Autovía Mercosur + residual con UUID — APLICADO

**Excel mensual (sep/2026): Resumen 3.848,45 tn vs Detalle de Pesadas 3.674,16 tn.**
No era la query (ambas tablas usan el mismo universo de pedidos); era un dato
mal migrado: las 6 pesadas del 03/09 tarde (vales 10006–10011, 174,26 tn)
estaban ligadas al pedido del 02/09, que quedó con `cantidad_despachada`
350,28 (el legado `vt_p9` id `0ch9y6k` dice 176,02, remito 1246, vale 8983),
mientras el residual del 03/09 (legado `pxee3q6`, 174,26, remito 1247) volvía
a sumar esas mismas 174,26. Único caso en todo el sistema (cruzados todos los
despachados contra `vt_p9`). Corregido con UPDATE directo (Federico):

| Qué | Antes | Después |
|---|---|---|
| Pedido `52a1a0a9-c2cc-4c8b-b9ed-2cf23f0fe41c` (02/09) `cantidad_despachada` | 350.28 | 176.02 |
| mismo pedido `nro_remito_global` / `nro_vale_global` | null / null | 1246 / 8983 |
| Vales asfalto 10006–10011 `pedido_id` | `52a1a0a9-…` | `e239ab86-0465-4938-934c-631e750f3206` (03/09) |

- **Stock NO se tocó** (a propósito, no se usó `corregir_despacho`): el pedido
  del 02/09 conserva sus 3 movimientos `egreso_despacho` (-366.743,16 kg, que
  cubren las 350,28 tn) y el del 03/09 sigue sin movimiento — el total
  descontado es el correcto, solo queda atribuido al pedido del 02/09.
- Post-fix: sep/2026 Mercosur Resumen 3.674,194 vs Pesadas 3.674,16. Los 0,034
  restantes son del pedido del 24/09 (511,094 tipeado vs 511,06 pesado), esperable.
- Agosto/2026 sigue con 285,13 tn de diferencia: pedidos del legado 10/08 y
  11/08 con menos vales que el remito. Otra causa, sin tocar.

**Residual con UUID en observaciones.** Migración 46: `finalizar_despacho`
arma "…al dividir el despacho del pedido del 24/09/2026 (550 tn, Remito N°
00030)" (hormigón: solo fecha + m³); el motivo del historial igual. Además
revoca EXECUTE a `anon` (verificado en `proacl`: postgres, authenticated,
service_role). Reescrito el único residual existente (`1824b242-…`, 30/09):
observación y motivo de historial pasaron de "…del dbc209f0-a0e4-480a-99e4-955845645709"
/ "Residual del pedido dbc209f0-…" a "…del pedido del 26/09/2026 (30 tn,
Remito N° 00033)".

## 5d. 2026-09-29 — Revisión general Resumen vs Detalle de Pesadas — APLICADO

Cruce pedido por pedido (`cantidad_despachada` vs suma de vales de asfalto /
cargas de hormigón), validado contra los `camiones` de `vt_p9` (patente +
cantidad). 4 obras con vales ligados al pedido equivocado; corregido en una
transacción con guardas por fila (confirmación explícita de Federico). **Stock
sin tocar** (solo `plantas_vales.pedido_id` + estado del duplicado).

| Obra | Vales | pedido_id antes | pedido_id después |
|---|---|---|---|
| Autovía Mercosur | 9815–9824 (10/08, 285,13 tn) | null | `e5058382-…` (10/08) |
| Autovía Mercosur | 9835, 9840 (11/08, 59,61 tn) | `e5058382-…` (10/08) | `677f19e1-…` (11/08) |
| HV-VIAL | 9782, 9783, 9786 (29/07, 62,94 tn) | null | `eaa1657a-…` (29/07, remito 1211) |
| G y C Construcciones | 9603–9605 (04/06, 123,84 tn) | `d00404a3-…` (03/06) | `4634dcd0-…` (04/06, remito 1169) |
| Previal UTE | 10003–10005 (03/09, 76,62 tn) | `77e8e5ff-…` (viejo) | `734b5545-…` (despachado 10/09, remito 2) |

- Previal: el pedido legado `f2bgrer` se despachó en el legado el 04/09 pero
  quedó `postergado` en plantas (`77e8e5ff-…`, 85 tn, remito 12); Felix lo
  recargó el 10/09 como pedido nuevo `734b5545-…` (el que descontó stock).
  `77e8e5ff-…`: `postergado` → `cancelado`, motivo "Duplicado del pedido del
  03/09 despachado el 10/09 (remito 00002)" + fila en historial. No tenía
  movimientos de stock (chequeado en la transacción).
- Resultado: 0 vales de asfalto sin pedido; desde junio todas las obras/meses
  cuadran salvo diferencias de tipeo (G y C jun -0,06; Mercosur sep 0,034).
- Sin arreglo (falta de dato de origen, no error): mayo/2026 — asfalto sin
  vales (la báscula arranca el 29/05) y hormigón legado sin cargas de mixer
  (Predio Vialtec, Colegio Moorlands, Previal).

## 5e. 2026-09-30 — Analítica por rango, Editar para balancero, reasignar vale

- **Stock → Analítica de proveedores**: selector Mes | Rango de fechas (el
  service ya aceptaba cualquier rango). Excel con el período en el título.
- **Báscula, Editar para balancero (migración 47, APLICADA)**: la matriz ya
  tenía `bascula:editar` para balancero, pero UI y RPC tenían fijo
  admin/plantista (y la matriz decía plantista editar/eliminar = false). Ahora
  UI (`auth.tienePermiso`) y RPC (`plantas_tiene_permiso`) leen la matriz;
  plantista `bascula:editar`/`bascula:eliminar` pasaron a true (antes false)
  para no quitarle nada. Verificado simulando claims: balancero editar sí /
  anular no; plantista y admin ambos; gerencia ninguno. EXECUTE sin `anon`.
- **"Admin no podía editar"**: no hay llamadas fallidas en los logs (24 h) y
  rol/RPC/UI dan bien para admin. Hallazgo: 30/09 11:52 UTC Felix anuló el
  vale 10170 "mal obra" y repesó el mismo camión como 10171 en otro pedido —
  el modal no permitía cambiar el pedido. Es el caso del punto 3.
- **Reasignar vale (migración 48, NO aplicada)**: `reasignar_vale_bascula`
  (bascula:editar, motivo obligatorio, solo asfalto no anulado, origen y
  destino `confirmado`, rechaza si en Pedidos ya hay una carga con ese N° de
  vale en el origen; destino toma remito si no tenía; sin impacto en stock) +
  tabla `plantas_vales_historial` (también la usan ahora corregir/anular).
  Dry-run atómico contra producción (bloque DO con raise final, verificado
  que no persistió nada): 10 chequeos OK, sin consumir la secuencia de
  remitos. Frontend: selector "Pedido" en el modal Editar (pedidos del día de
  la pesada primero), motivo obligatorio si cambia.

## 9. Optimización de rendimiento (2026-09-30) — FASE 1 EN CURSO

Baseline medido con `scripts/medir-rendimiento.js` (pegar en la consola de
produccion.vialtec.app con sesión y correr `await medirRendimiento()`;
navega por el router de la app e intercepta fetch). Medido como admin, SPA.
Ranking por requests/KB/cadenas, no por tiempos (red lenta ese día).

Baseline (requests / KB / filas / niveles en cadena / duplicadas):
Despachos 11/329/713/2/0 · Home 23/100/615/2/4 · Báscula 10/71/167/2/0 ·
Pedidos 7/37/117/3/0 · Simulador 3/25/53/1/0 · Stock actual 5/23/81/2/0 ·
Stock→Analítica 1/8/87 · Plan semanal 4/23/40/1/0 · Fórmulas 1/19/20 ·
Usuarios 6/8/96 · Maestros 1–2 req por tab. Carga en frío: 3 niveles
(index → sesión/rol → ~20 chunks de la ruta → datos).

Hallazgos clave: DB no es el cuello de botella (bascula_viva 17 ms con RLS);
Despachos baja 263 KB (196 pedidos `select *`, 82 % es `datos_legados`) para
"Totales del filtro"; fórmulas (19 KB) se pide ~10 veces por recorrido (Home
×3); Home hace 9 queries por mes para el Resumen anual + 2 anuales. Sistema
viejo (kv_store) sin tráfico (0 requests 24 h, última escritura 06/09).
Flota usada por plantas (solo lectura): `flota_obras` (Maestros→Obras,
Usuarios, vistas `plantas_v_obras_visibles`/`plantas_v_bascula_viva`) y
`flota_usuarios_email` (nombres). Bundle: exceljs/PDF ya son lazy.

FASE 1 (aprobada; un commit por cambio, `npm run build` limpio, no tocar la
lectura de `flota_obras` — por eso NO se toca `fetchPaginado` global):
- [x] Desempate `.order('id')` en Pedidos, Despachos, Báscula y movimientos
  de Stock — `fd79bea` (no deployado).
- [ ] Ítems 1+6: `select('*')` → columnas explícitas en
  `queryDespachosFiltrados` (listado, totales, Excel del filtro, informe
  mensual). Campos que usa Despachos: id, obra_id, formula_id, tipo,
  cantidad_solicitada, cantidad_despachada, fecha_programada, estado,
  encargado, tipo_pedido, cliente_externo, motivo, nro_remito_global,
  nro_vale_global. Sin uso: datos_legados, observaciones, ubicacion,
  created_at, creado_por, motivo_en, archivado. Falta relevar y aplicar lo
  mismo en el listado de Pedidos (`queryPedidos`).
- [ ] Ítem 2: cache por sesión de fórmulas (invalidar al editar); Báscula y
  Despachos piden solo `id, nombre`.
- [ ] Ítem 3: Home sin duplicados (materiales ×2, stock ×2, fórmulas ×3).
- [ ] Ítem 7: Stock → Historial de ingresos lazy al abrir el tab (hoy se
  carga en `iniciar()`); unificar las 2 queries de materiales.
- [ ] Re-medir con el script y armar comparativo Baseline vs Fase 1.
- [ ] Deploy + push (pedir OK).
Fase 2 (SQL, no aprobada aún): RPC de totales de Despachos y de resumen
anual; simplificar `plantas_v_bascula_viva` (sacar ramas kv_store, acumulado
solo sobre el rango); envolver `plantas_rol_actual()` en `(select …)` en la
RLS de pedidos. Fase 3: prefetch del chunk de ruta en paralelo a la sesión,
cache de catálogos, limpieza de índices/políticas duplicadas.

## 6. Pendientes operativos (heredados del histórico, sin confirmar en vivo)

- Impresión física: confirmar con una hoja real el rediseño del remito
  (portrait) y el margen de corte del vale.
- Probar en celular real el roadmap Mobile (nav inferior, columnas secundarias,
  autoscroll de Plan Semanal).
- Probar con un email real el flujo "¿Olvidaste tu contraseña?" del login.
- Probar en vivo Editar/Eliminar (anular) de vales de Báscula con un vale de cada
  tipo y el archivado local de Obras (Maestros → Obras).
- Confirmar que el toast de WhatsApp al crear un pedido abre el chat de Daniel
  Natel, y que el filtro de fecha de Báscula sobrevive a imprimir.
- Exportar un Excel y confirmar que el logo ya no sale estirado.
- Migración 36: la secuencia de remitos arranca en 1; si Federico quería que el
  primero diga 0, es un `alter sequence plantas_remitos_numero_seq restart with 0`.
- Baja del legado como fuente de escritura (checklist del corte, §8) y decidir si
  se cierra del todo `kv_store` (hoy: solo lectura para `authenticated`, migración 28).
- Catálogos: 7 clientes del legado sin migrar (la tabla ya existe); umbrales
  mín/máx de stock a transcribir a mano; patente `AD-648-EA` con columnas
  cruzadas; 3 usuarios sin nombre en `flota_usuarios_email` (angel.moreira,
  balanza, juan.heinrich).
- Decididas para después del corte: módulo Auditoría (pantalla), exports
  faltantes (Excel de Pedidos y 5 botones de Despachos). Backup: NO se desarrolla
  (backups de Supabase + export manual).

## 7. Reglas vigentes que salieron del histórico

- Deploy siempre manual `npx vercel --prod`; nunca auto-deploy (ver `procedimientos.md`).
- Pedidos no tiene vista puente con el legado (decisión de Federico, ya cortado).
- Para stock: el descuento por despacho sale de `plantas_pedidos.cantidad_despachada`
  (Pedidos); Báscula es solo auditoría de asfalto. Ingreso/egreso de áridos mueve
  stock directo desde Báscula (`business-rules.md`).
- Antes de tocar una vista con anti-join contra una tabla con RLS, materializar
  la lectura (lección de la migración 25).
- Al recrear una vista, partir de la definición REAL de producción
  (`pg_get_viewdef`), no de un script del repo (falló con la migración 31).
- `revoke ... from public` NO alcanza en Supabase: `anon` y `authenticated` tienen
  grants propios sobre las funciones nuevas (origen del hallazgo crítico de la 43).
  Toda función SECURITY DEFINER interna debe revocarse también a esos dos roles.

## 10. Tercer tipo de producto: mezcla cemento (2026-10-01)

Pedido de Federico: la mezcla cemento no es asfalto ni hormigón; tipo propio,
siempre independiente en totales y reportes. Sale como el hormigón (remito por
carga, sin báscula) pero se mide en tn. Detalle de la regla en
`business-rules.md` §"Tipos de producto".

- **Migración 49 APLICADA** (dry-run revertido antes,
  `supabase/scripts/dry_run_migracion_49.sql`, 7 chequeos OK): CHECK de
  `plantas_formulas.tipo`/`plantas_pedidos.tipo` + `registrar_carga_hormigon`
  acepta `mezcla_cemento` (roles: admin, plantista, plantista_hormigon) y ya
  no es ejecutable por `anon`. `finalizar_despacho` no se tocó: ya escribía
  ' tn' para todo lo que no es hormigón.
- **Frontend (commits `97a1484`..`4b9690d`, sin deploy)**:
  `src/config/tipos-producto.js` es el único lugar que nombra los tipos
  (circuito báscula/mixer, unidad, total, color). Pedidos, Plan semanal, Home,
  Despachos, Simulador, WhatsApp y los 2 Excel preguntan por circuito/unidad/
  total. Mezcla cemento solo aparece (sección, KPI, columna de Excel) cuando
  hay algo. Las comparaciones que quedan contra 'asfalto'/'hormigon' son de
  `tipo_vale`/tipo de puerta de Báscula (otro concepto).
- **Datos APLICADOS (2026-10-01, OK de Federico)**: fórmula MEZCLA CEMENTO
  80/20 y pedido `072cd55b-…` (27/05) pasaron a `mezcla_cemento`, con fila
  `corregido` en `plantas_pedidos_historial` (tipo anterior/nuevo en
  `datos_legados`). Mayo quedó hormigón 392,2 m³ (26), mezcla cemento 6 tn
  (1), asfalto 2.596,68 tn sin cambio. El solicitado del 02/10 lo canceló
  Federico. Verificado en vivo tras el deploy: Despachos, Home, Pedidos, Plan
  semanal y Fórmulas coinciden con la base, sin errores de consola.
- **Observación sin tocar**: el KPI "Asfalto (período)" de Pedidos suma
  también los pedidos cancelados (1.578,6 vs 1.562,6 de Plan semanal esta
  semana, diferencia = el cancelado de 16). Comportamiento previo a este
  cambio; decidir con Federico si se excluyen.
- Estado previo de los datos (referencia): fórmula `MEZCLA CEMENTO 80/20`
  (`c850efee-…`, hoy tipo asfalto, 800 kg Cemento CPC 40 + 200 kg Arena
  Silicia por tn) pasa a mezcla_cemento. Pedido despachado 27/05
  (`072cd55b-…`, Predio Vialtec, 3 pedidas / 6 reales, remito 12447, guardado
  como hormigón, sin movimientos de stock): reclasificar con auditoría, con OK
  de Federico. Mayo/2026 pasa de hormigón 398,2 m³ a 392,2 m³ + mezcla
  cemento 6 tn. Pedido solicitado 02/10 (`eba49b46-…`, 16, tipo asfalto): lo
  cancela y recarga Federico, no tocar. Histórico ene–abr: no tocar.
- **Verificación hecha**: build limpio en cada commit; 20 chequeos de la
  config con Node (la suma nueva da igual que la lógica vieja sobre los 2
  tipos existentes). **Falta**: ver las pantallas en vivo y comparar el Excel
  del informe mensual de septiembre antes/después (requiere deploy).
- `plantas_v_despachos_camion` (vista, sin uso en la UI) sigue etiquetando las
  cargas de mixer como hormigón; revisar si algún día se vuelve a usar.

