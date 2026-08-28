# Relevamiento del sistema viejo — produccion.vialtec.app

Relevamiento en vivo (navegación real vía Claude in Chrome, sesión de Federico
como Administrador) del sistema que `vialtec-plantas-v2` reemplaza. Objetivo:
que ninguna funcionalidad real quede afuera del sistema nuevo. Complementa
(y en algunos puntos corrige) lo que ya sabíamos de
`Logica sis. plantas v1.rtf`/`v2.rtf`.

**Estado: COMPLETO — Etapa 1 cerrada (2026-08-27).** Cubre los 13 módulos:
Dashboard, Pedidos, Plan semanal, Stock, Despachos, Fórmulas, Simulador,
Báscula, Maestros (7 catálogos), Usuarios, Permisos por rol, Backups.

---

## 0. Hallazgo estructural — cambia el diseño de "obras"

**"Obra" en el sistema viejo NO es lo mismo que `flota_obras`.** Es su propio
catálogo — Maestros → "Obras / Centros de costo" (14 registros), cada uno con
`nombre` + `código` propio (ej. `CAM-01`, `PV-01`, `PRV-01`). Nuestra
propuesta de migración (memory/pending.md) asumía reconciliar contra
`flota_obras` por nombre — **eso hay que revisarlo**: la fuente real de
verdad de "obra" para Plantas parece ser este catálogo propio del sistema
viejo, no `flota_obras`. Falta decidir con Federico si:
- Se migra esta lista de 14 obras/centros de costo tal cual a una tabla
  `plantas_obras` propia (con su código), en vez de depender de `flota_obras`, o
- Se reconcilia igual contra `flota_obras` y el código (`CAM-01` etc.) se
  guarda como dato adicional.

Además, "Clientes frecuentes" (Maestros, 7 registros: MUNICIPALIDAD DE PILAR,
COLEGIO MOORLANDS, CORRALON FILIBERTI, Lucas Maldonado, G Y C CONSTRUCCIONES
S.A, HV-VIAL S.A, AUTOVIA MERCOSUR) es un catálogo **separado** para
`cliente_externo` en pedidos de venta — no es texto libre como asumimos en
`06_ajustes_pedidos_vales_historial.sql`. Ej: **"AUTOVIA MERCOSUR" y
"MUNICIPALIDAD DE PILAR", que en el listado de Pedidos parecen destinos de
obra, son en realidad ventas externas con cliente de este catálogo** — el
`tipo_pedido='venta'` es mucho más frecuente en producción de lo que
esperábamos (8 de los pedidos de asfalto vistos son de estos dos clientes).

**Materiales / Insumos (18 registros) también es un catálogo propio**, con
`nombre` + `unidad` (TN/kg) + `categoría` (Cemento/Áridos/Aditivo/Asfalto).
Hoy en `plantas_formulas.insumos` (jsonb) y en Stock, el material es texto
libre — en el sistema viejo es una FK a este catálogo. Esto también alimenta
Stock (cada material del catálogo tiene su tarjeta de stock).

---

## 1. Pedidos

**Vista lista** (`/Pedidos`): agrupada por tipo de producción (secciones
"Hormigón" / "Asfalto", cada una con contador). KPIs arriba: SOLICITADO,
CONFIRMADO, DESPACHADO, POSTERGADO, CANCELADO (5 estados confirmados en
producción real — `postergado` se usa). Botón "Archivo" (toggle, no lo
abrimos) y "+ Nuevo pedido".

Cada card de pedido muestra: badge de estado, **destino** (obra o cliente
externo), fórmula, cantidad solicitada (+ "→ real: X" si está despachado),
fecha, ícono de persona + responsable, fecha/hora de creación, link "Ver
historial", y una fila con la **nota/observación** si tiene. Los cancelados
muestran el **motivo** en rojo dentro de la card, no hay que abrir nada para
verlo.

Acciones visibles directo en la card según estado (sin submenu):
- `solicitado`: **Confirmar** (botón violeta), Editar, Postergar, X (cancelar)
- `confirmado`: **Despachar** (botón verde), Editar, Postergar, X
- `despachado`/`cancelado`: solo "Ver historial"

**Modal "Nuevo pedido"** — campos exactos, en este orden:
1. `TIPO DE PEDIDO` — botón "Producción interna" (no logré activar el toggle
   a "Venta externa" por UI en esta sesión — puede estar gateado por rol o
   requerir otra interacción; **pendiente confirmar** cómo se crea una venta
   nueva desde cero, hoy en la práctica parece que las ventas se cargan y
   después se les asigna cliente, o el toggle depende de otro estado previo).
2. `OBRA / CENTRO DE COSTO` — select del catálogo propio (ver §0).
3. `RESPONSABLE DEL PEDIDO` — texto libre, **prellenado con el usuario
   logueado** (editable).
4. `TIPO DE PRODUCCIÓN` — toggle Todas/Hormigón/Asfalto, filtra el combo de
   Mezcla de abajo.
5. `MEZCLA` — select de Fórmulas (19 disponibles).
6. `CANTIDAD (M³)` — numérico (la unidad del label cambia según mezcla:
   m³/tn).
7. `FECHA DE ENTREGA REQUERIDA` — date, **prellenada con hoy**.
8. `NOTAS` (opcional) — textarea.
9. `UBICACIÓN` (opcional) — texto libre, ej. "Acceso norte, km 12...".
   **Campo que no tenemos en `plantas_pedidos` — gap real.**

**Modal "Registrar despacho"** (botón Despachar sobre `confirmado`):
- Header: pedido + fórmula + cantidad solicitada.
- **"CARGAS / CAMIONES"**: una carga por default (cantidad prellenada = total
  del pedido), con botón "+ Agregar carga" para sumar más — cada carga tiene:
  `CANTIDAD (TN) *`, `N° VALE *` (**obligatorio por carga**, incluso para
  asfalto de producción interna — no solo ventas), `PATENTE (opcional)`.
- "Total: X tn" recalculado en vivo.
- `N° REMITO (opcional)` — **uno solo para todo el despacho**, no por carga.
- Esto es MÁS RICO que nuestro `despacharPedido(id, cantidad)` actual — el
  sistema viejo soporta multi-camión con vale por carga en el mismo flujo de
  despacho manual (además de/en paralelo a la báscula). **Gap real en
  `pedidos.service.js`.**

**Modal "Postergar pedido"**: `NUEVA FECHA DE ENTREGA (opcional)` (date,
prellenada con hoy) + `MOTIVO` (textarea, **no obligatorio** — sin asterisco,
a diferencia de Cancelar). Confirma que el motivo de postergar es opcional,
solo el de cancelar es obligatorio.

**Modal "Historial del pedido"**: timeline simple — por evento: badge de
estado + fecha/hora a la derecha + responsable (ícono persona + nombre) +
motivo si aplica (con emoji 📝, en texto debajo). Coincide bien con nuestro
diseño de `plantas_pedidos_historial`.

---

## 2. Báscula

Header: **"Báscula — Despachos simultáneos"** — "X puertas abiertas · Próximo
N° 00009949". **La secuencia de vale real hoy está en ~9949** (no en 9579 —
ese es el punto de partida histórico, no el valor actual). Importante para
cuando se migre: el nuevo sistema tiene que arrancar la secuencia desde donde
esté el contador al momento real de la migración, no desde 9579 a secas.

Cada slot de pesaje se llama **"puerta"** (no "slot"). Botón "+ Abrir puerta"
crea una nueva. Cada puerta es una card colapsable (header con selector de
tipo, botón colapsar ▲, botón cerrar ✕).

**Tipo de vale — 3 opciones, no 4 como asumíamos:**
- `Vale Asfalto`
- `Ingreso Áridos`
- **`Vale Salida Áridos`** — **NO EXISTE en nuestro schema** (`plantas_vales.tipo_vale`
  solo tiene `asfalto`/`hormigon`/`ingreso_arido`). Es un egreso pesado de
  áridos (venta/traslado de material, no solo ingreso). Confirma además que
  **no hay "Vale Hormigón"** — hormigón nunca pasa por báscula, tal como
  documenta `business-rules.md`. **Gap real: falta `tipo_vale = 'egreso_arido'`
  (o similar) en el schema y en la RPC `registrar_pesada_bascula`.**

**Form "Vale Asfalto":**
- `Pedido / Obra *` — select — **incluye pedidos `confirmado` Y `despachado`**
  (ej. "AUTOVIA MERCOSUR • CAC D19 (AUTOVIA) • 410 tn (despachado)"). El
  sistema viejo NO filtra por saldo pendiente como hace hoy
  `fetchPedidosAsfaltoConSaldo()` en nuestro v2 — permite seguir pesando
  contra un pedido ya despachado. **Diferencia de comportamiento a decidir
  con Federico**: ¿mantenemos el filtro por saldo (más estricto) o lo
  sacamos para calzar con el viejo?
- `Patente *`, `Chofer` (opcional), `Bruto (tn) *`, `Tara (tn) *`, `Neto`
  (calculado, disabled).
- **`Temperatura (°C)`** (opcional) — **campo que no tenemos**, específico de
  asfalto. Gap real.
- `Fecha` (prellenada hoy).
- Botón "📋 Registrar vale" (disabled hasta completar requeridos).

No pude cambiar el combo a "Ingreso Áridos"/"Vale Salida Áridos" por una
limitación de la automatización del navegador (select nativo) — quedan para
la próxima pasada, pero por lo ya visto en Maestros/Stock es razonable
esperar que "Ingreso Áridos" pida material (del catálogo)/proveedor/remito/
cantidad declarada, igual a como ya lo tenemos.

**Tabla "Movimientos del día"**: filtros Desde/Hasta + botón **"Excel"**
(export que no tenemos). Columnas: HORA, TIPO (`ING`/`VALE`, con E/S =
Entrada/Salida al final), MATERIAL/OBRA, PATENTE, REMITO, RESPONSABLE, VALE,
BRUTO, TARA, **NETO**, **ACUM.** (acumulado dinámico por obra/día — confirma
nuestro `obtenerAcumuladoObraHastaFecha`), **S/REMITO**, **DIF.** (diferencia
neto pesado vs. remito — confirma el concepto de `diferencia` del legado,
que hoy no calculamos/mostramos en ningún lado de v2), acciones: **Imprimir,
Editar, Eliminar** por fila.

**El botón "Eliminar" existe y está habilitado en cada vale/ingreso** — esto
contradice lo que dice `Logica sis. plantas v1.rtf` ("los vales de báscula
nunca se eliminan"). No lo probé (acción destructiva sobre datos reales de
producción, no la iba a ejecutar). Queda como pregunta abierta: ¿la regla de
negocio documentada no se aplica en la práctica, o eliminar tiene alguna
guarda que no vimos (confirmación, permiso especial)?

---

## 3. Despachos (módulo dedicado — mucho más que nuestro Dashboard)

Header: "Historial de despachos — Registro histórico por obra / centro de
costo." Botones: **Eficiencia**, **Resumen mensual**, **Excel período**,
**Por obra**, **Excel completo** (5 vistas/exports — no tenemos ninguna).

KPIs: Asfalto del mes, Hormigón del mes, **Total asfalto acumulado**
(11935.5 tn — histórico completo), **Total hormigón acumulado** (1092.6 m³).
Nuestro Dashboard solo tiene el KPI del mes, no el acumulado histórico.

**"Resumen por obra"**: grid de cards por obra/cliente con total (tn o m³) +
cantidad de despachos, con selector de rango de meses + "Exportar Excel".

**Filtros combinados**: Todos/Hormigón/Asfalto + Mezcla (dropdown) + Obra
(dropdown) + Desde/Hasta — más granular que el Dashboard actual.

**Tabla**: Fecha (+responsable debajo), Obra, Mezcla, Pedido (cantidad
solicitada), Real, **Diferencia** (columna explícita — no la tenemos),
acciones (🚛 detalle de cargas, 👁 ver, 🖨 imprimir, 🗑 eliminar).

**Modal "Detalle del despacho"** (ícono 🚛): lista completa de cargas/camiones
de ese despacho (vimos uno con 10 cargas), cada una con patente + cantidad +
remito, y "Total despachado" al pie. Es exactamente el detalle granular que
nuestra vista `plantas_v_despachos_camion` no expone hoy (solo agrega, no
lista cargas individuales de un mismo despacho agrupado).

**Conclusión: Despachos merece ser un módulo propio en v2** (ya estaba
PENDIENTE en `modules-status.md`), no solo una sección del Dashboard — el
viejo lo trata así y tiene mucha más profundidad (resumen por obra,
eficiencia, exports múltiples, detalle por camión).

---

## 4. Fórmulas

"Fórmulas de mezcla" — 19 fórmulas (9 hormigón, 10 asfalto), tabs
Todas/Hormigón/Asfalto con contador. Grid de cards: nombre + badge tipo +
"POR M³"/"POR TN" + lista de insumos.

- Hormigón: insumos en **kg** por m³.
- Asfalto: insumos en **%** con **kg/tn equivalente entre paréntesis** (ej.
  "Piedra 6/20 47% (470 kg/tn)") — confirma nuestra conversión `% → kg` en
  `calcularConsumoKg()`.
- **Insumos sin stock** (Agua, Purgue) aparecen con tag gris "sin stock" al
  lado del nombre, directo en la card — confirma la regla de negocio, y
  sugiere que en el sistema viejo es un flag por insumo/material (del
  catálogo Materiales), no una constante hardcodeada como
  `app.config.js#materialesSinDescuento` en nuestro v2.

No llegué a abrir "Editar fórmula" en esta pasada — el layout general (%
vs kg, categorías) ya valida bien nuestro diseño actual de
`plantas_formulas.insumos` jsonb.

---

## 5. Maestros — 7 catálogos, no 4

| Catálogo | Cantidad | ¿Existe en v2? |
|---|---|---|
| Obras / Centros de costo | 14 | NO — hoy usamos `flota_obras` (ver §0, gap estructural) |
| Proveedores | 8 | Sí (`plantas_proveedores`) |
| **Materiales / Insumos** | 18 | **NO** — gap real (ver §0) |
| **Clientes frecuentes** | 7 | **NO** — hoy `cliente_externo` es texto libre |
| Patentes / Vehículos propios | 32 | Parcial (`plantas_patentes`, sin distinguir propio/externo) |
| **Camiones externos** | 22 | Están mezclados con patentes propias vía `es_externa` |
| Choferes | 0 (¡vacío en producción!) | Sí (`plantas_choferes`), pero no se usa en la práctica — chofer se tipea libre en cada vale/carga |

Cada catálogo: listado simple (nombre + campos propios) + Editar + X
(eliminar) + "+ Agregar". Nada fuera de lo esperado en la estructura, la
sorpresa es la **cantidad de catálogos** (7 vs. nuestros 4).

---

## 6. Stock (vistazo — PENDIENTE en v2, existe y está maduro acá)

"Stock de insumos" — 3 tabs: **Stock actual**, **Historial de ingresos**,
**Analítica proveedores**. Botones "Excel" y **"Relevamiento"** (conteo
manual/auditoría de stock — funcionalidad que no tenemos ni prevista).

Cada material: card con semáforo real de 3 colores (🟢 OK / 🟠 Ajustado / 🔴
Insuficiente), cantidad en toneladas (+kg chico debajo), **barra de progreso
con min/max configurados por material** (ej. "min 1t ... máx 2t"), toggle
global Toneladas/Kilogramos.

Esto es un sistema de alerta **más simple y distinto** del que describe
`business-rules.md` (que habla de proyección de consumo semanal vs. pedidos
confirmados, para el Dashboard). Acá el semáforo es contra un **min/max fijo
configurado por material**, no contra proyección. Probablemente conviven los
dos: este (stock crudo) y el otro (proyección semanal). `VSemaforo.vue` ya
está construido en v2 y sin usar — encaja con este patrón.

Materiales vistos con stock 0 (🔴 insuficiente) en producción real: CAL,
FRESADO — confirma que el escenario de déficit ya ocurre en la operación
real, no es solo teórico.

---

## 7. Plan semanal

Header "PLAN DE PRODUCCIÓN" (banner morado oscuro con gradiente), navegación
‹ › por semana, rango de fechas, contador "X pedidos activos", botones
**Excel** + toggle **Tabla/Cards**.

**"INSUMOS REQUERIDOS — SEMÁFORO DE STOCK"** — la tabla que confirma al 100%
la regla de negocio de `business-rules.md` (proyección semanal, no la
tenemos implementada): columnas INSUMO, STOCK ACTUAL, CONSUMO ESTIMADO,
STOCK PROYECTADO, DÍAS EST., ESTADO. Ejemplo real visto: "ASFALTO AM3
(AUTOVIA)" con 21.48t actual, 19.74t consumo estimado de la semana, 1.74t
proyectado, ≈8 días de cobertura, estado **"Ajustado"** — coincide
exactamente con el banner de alerta que vimos en el Dashboard ("Stock
ajustado: ASFALTO AM3 (AUTOVIA) — Margen bajo para esta semana"). Confirma
que Dashboard y Plan Semanal comparten esta misma alerta.

**Cronograma semanal**: grid de columnas por día con pedidos agrupados,
totales por día (tn/m³), acciones directas (Despachar) en la card del día
actual. **Hallazgo: el grid solo muestra LUN a SÁB (6 columnas), pese a que
el rango de fechas mostrado arriba llega hasta domingo** ("24/08/2026 →
30/08/2026", pero no hay columna de Domingo). Contradice la regla de
`business-rules.md` ("la semana va de lunes a domingo"). No pude determinar
si es un bug del sistema viejo o si Domingo deliberadamente no se muestra
como día operativo — **a confirmar con Federico** antes de decidir si
`obtenerRangoSemana()` en v2 debe replicar esto o mantener los 7 días.

## 8. Simulador

"Simulador de stock — Calculá despachos sin afectar el sistema real."
Simple: `Fórmula` (select) + `Cantidad` + `Etiqueta` (opcional, ej. "Obra
Norte") + "+ Agregar" → arma una lista de despachos simulados (sin tocar
datos reales) para ver el impacto acumulado en stock. Coincide con lo
documentado en el legado, sin sorpresas — pendiente ver el detalle de cómo
muestra el resultado (no llegué a cargar una simulación real).

## 9. Dashboard (a fondo)

Además de los KPIs ya vistos en el primer login: dos **banners de alerta
accionables** arriba de todo — "🟠 Stock ajustado: X — Margen bajo para esta
semana [Ver plan →]" y "📋 N pedidos esperando confirmación [Confirmar →]" —
no son solo indicadores, son links directos a la acción. Ninguno de los dos
existe en nuestro Dashboard v2 hoy.

5 KPIs (no 4): Pedidos activos, Confirmados, Despachos esta semana (dual
unidad tn+m³), **Ajustados** (conteo de materiales en estado "Ajustado") y
**Críticos** (conteo en estado "Insuficiente") — estos dos últimos son el
resumen agregado del semáforo de Stock, no los tenemos.

"Consumo de material": selector de material + gráfico de línea + tabla de
últimas 8 semanas (con autoescala de unidad kg/t según magnitud). "Próximos
despachos": lista de pedidos confirmados con fecha relativa ("Hoy"). "Stock
actual de insumos": preview + link a Stock.

## 10. Usuarios

"Usuarios del sistema — Gestioná los accesos y roles del equipo." Lista de
usuarios reales con avatar (iniciales), nombre, email, **badge de rol**,
Activo/Inactivo, botón Editar. Encargados/Supervisores muestran inline la
**lista de obras asignadas** (🏗 Obra A · Obra B · Obra C) — confirma el
concepto de `obra_ids` por usuario que ya diseñamos en
`plantas_usuarios_roles`.

**Roles reales confirmados en producción** (con su label de UI exacto, no
necesariamente igual al enum interno que definimos en v2):
`Administrador`, `Plantista (Jefe)`, `Gerencia`, `Encargado de obra`,
`Supervisor`, `Balancero`, `Plantista Hormigón`. Mapean 1:1 conceptualmente
a nuestros 7 roles de `business-rules.md`/`auth.store.js`
(`admin/plantista/gerencia/encargado/supervisor/balancero/plantista_hormigon`),
con dos matices:
- **"Plantista (Jefe)"** sugiere que podría existir un "Plantista" sin
  "(Jefe)" como variante — no vimos ningún usuario con ese rol exacto en
  esta pasada, pero el paréntesis es sospechoso. A confirmar.
- El usuario con rol Balancero tiene el email genérico `balanza@vialtec.com.ar`
  — sugiere una cuenta compartida de kiosko para el puesto de báscula, no
  una persona. Relevante para nuestro diseño de auth: si vamos a permitir
  logins compartidos por puesto de trabajo (no 1 login = 1 persona), hay que
  decidirlo explícitamente — hoy nuestro diseño asume email personal.

No se abrió el modal "+ Nuevo usuario" en esta pasada (para no arriesgar
crear un usuario real en producción) — pendiente si hace falta el detalle
exacto de esos campos.

## 11. Permisos por rol

"Permisos por rol — Configurá qué módulos y acciones puede ver cada rol."
Banner de aviso: **"⚠ Los cambios aplican al próximo inicio de sesión. Los
usuarios ya conectados mantienen sus permisos actuales."** — confirma que el
rol/permisos se resuelve una vez por sesión (login), no en tiempo real —
exactamente el mismo modelo que ya implementamos en `auth.store.js`.

Por cada rol (Encargado de obra, Supervisor, Balancero, Plantista (Jefe),
Gerencia — **5 cards, no 7**: no hay card para Administrador ni para
**Plantista Hormigón**, pese a que sí existe un usuario real con ese rol.
Posible inconsistencia del sistema viejo — a confirmar si Plantista Hormigón
tiene permisos hardcodeados en otro lado o es un rol sin configurar) se
muestran dos grupos de checkboxes editables, con botón "Restaurar defaults"
por rol y "Guardar cambios" global:

- **MÓDULOS VISIBLES**: Dashboard, Pedidos, Plan semanal, Stock, Despachos,
  Fórmulas, Simulador, Báscula, Maestros, Backups (10 módulos).
- **PERMISOS DE ACCIÓN**: Crear pedidos, Confirmar pedidos, Despachar, Ver
  ventas externas, Ingresar stock, Exportar datos (6 flags) — coincide
  exactamente con "Flags relevantes" de `business-rules.md` §3
  (`verVentas`, `stockIngresar`, `exportar`, etc.), con la diferencia de que
  acá es una **matriz módulo×acción totalmente editable por el admin desde
  la UI**, no un objeto hardcodeado como nuestro `PERMISOS_POR_ROL` en
  `auth.store.js`. Esto es un argumento fuerte para que el "Roles" ABM
  (PENDIENTE, `modules-status.md` #10) termine siendo una tabla real
  editable (al estilo `flota_rol_permisos`), no una constante JS — mismo
  patrón que ya existe en flota, curiosamente, aunque decidimos no reusar
  esa tabla (ver §0).

Valores reales confirmados por rol (algunos difieren de lo que documenta
`Logica sis. plantas v1.rtf` §3 — la config real en producción pesa más que
el documento):
- Encargado de obra: todos los módulos operativos visibles salvo
  Simulador/Báscula/Maestros/Backups; acciones: Crear pedidos✓, Ver ventas
  externas✓, Exportar✓ (resto ✗).
- Supervisor: Dashboard/Pedidos/Despachos visibles únicamente; Crear
  pedidos✓, Exportar✓ (resto ✗, incluye Plan semanal que el .rtf sí le daba).
- Balancero: Stock/Báscula/Maestros visibles; solo Exportar✓ de acciones.
- Plantista (Jefe): todo visible salvo Backups; todas las acciones✓.
- Gerencia: Dashboard/Pedidos/Plan semanal/Stock/Despachos/Fórmulas
  visibles; solo Exportar✓ — **"Ver ventas externas" aparece DESACTIVADO**,
  a diferencia de lo que documenta el .rtf (que lo daba ✓ para gerencia).
  Puede ser un cambio deliberado post-documentación, o un ajuste manual del
  admin — no asumir el .rtf como fuente de verdad sobre este flag puntual,
  confirmar con Federico cuál es el comportamiento deseado en v2.

## 12. Backups

"Backups del sistema — Snapshots automáticos diarios. Solo visible para
administradores." Botones: **"Reconstruir stock"** (recalcula el stock desde
los movimientos históricos — herramienta de recuperación que no tenemos ni
prevista) y **"Backup ahora"** (trigger manual). No llegué a ver el listado
de snapshots cargado (quedó en "Cargando backups..." al momento de la
captura) — sin más detalle de formato/retención en esta pasada.

---

## Gaps confirmados (para priorizar en el roadmap, no solo P0/P1 ya definidos)

1. Catálogo `plantas_obras`/centros de costo propio — repensar la
   reconciliación contra `flota_obras` (§0).
2. Catálogo `plantas_materiales` (nombre + unidad + categoría) — hoy texto
   libre en fórmulas/stock.
3. Catálogo `plantas_clientes_frecuentes` — hoy `cliente_externo` es texto
   libre.
4. ✅ **RESUELTO (2026-08-28, migración 09)** — Campo `ubicacion` en pedidos
   (texto libre, ej. "Acceso norte, km 12"), en el modal "Nuevo pedido".
5. ✅ **RESUELTO (2026-08-28, migración 09)** — Campo `temperatura` en vales
   de asfalto, en el form de Báscula.
6. ✅ **RESUELTO (2026-08-28, migración 09)** — `tipo_vale = 'egreso_arido'`
   (Vale Salida Áridos): pestaña + campos material/destino en Báscula, RPC
   `registrar_pesada_bascula` extendida. Sin descuento de stock todavía
   (depende del módulo Stock, mismo TODO que ingreso de áridos).
7. ✅ **RESUELTO (2026-08-28, migración 09)** — Despacho multi-carga con
   vale-por-carga (obligatorio) + remito único opcional, desde el modal
   "Registrar despacho" de Pedidos: tabla `plantas_cargas_asfalto` + RPC
   `registrar_carga_asfalto`, composable `useDespachoAsfalto`. El
   `despacharPedido(id, cantidad)` de una sola cantidad total se eliminó.
8. Columna/cálculo de `diferencia` (peso neto vs. remito) expuesto en UI —
   ✅ **RESUELTO (2026-08-28)** para `ingreso_arido` (columna "Dif. s/remito"
   en el historial de Báscula, `calcularDiferencia()` en
   `bascula.service.js`). Pendiente para `egreso_arido`: hoy no hay un valor
   "declarado" contra el cual comparar el peso (no hay remito de origen para
   una salida) — a definir si aplica o si la diferencia solo tiene sentido
   para ingresos.
9. ✅ **RESUELTO (2026-08-28)** — Filtro por saldo pendiente en el selector
   de pedidos de báscula: se sacó (decisión de Federico), calza con el
   comportamiento del viejo. `fetchPedidosAsfaltoConSaldo()` →
   `fetchPedidosAsfaltoParaPesada()` (incluye `confirmado` y `despachado`,
   sin filtrar por saldo).
10. Módulo Despachos dedicado, con resumen por obra, acumulado histórico,
    detalle de cargas por despacho y múltiples exports Excel.
11. Módulo Stock con semáforo por min/max configurado por material +
    "Relevamiento" (conteo manual) + historial de ingresos + analítica de
    proveedores como tabs de una misma vista.
12. ✅ **DECIDIDO (2026-08-28)**: Federico confirmó que NO se agrega botón
    "Eliminar" en vales/despachos — se mantiene la regla de
    `business-rules.md` (nunca se eliminan, solo se anulan/corrigen vía
    ajuste). El comportamiento del viejo (botón habilitado) no se replica acá
    a propósito.
13. **Semáforo de stock proyectado semanal** (Plan semanal + banner de
    Dashboard) — regla de negocio ya documentada, confirmada ahora con datos
    reales, sigue sin implementar en v2.
14. **Permisos por rol como tabla editable** (módulos×acciones, con
    "Restaurar defaults" y aplicación en el próximo login) en vez de la
    constante `PERMISOS_POR_ROL` hardcodeada en `auth.store.js` — insumo
    directo para el futuro módulo "Roles" (P1, `modules-status.md` #10).
15. Herramienta **"Reconstruir stock"** (recalcular desde movimientos) en
    Backups — no prevista, útil como red de seguridad.
16. KPIs "Ajustados"/"Críticos" (conteo agregado del semáforo de stock) en
    el Dashboard.

## Preguntas abiertas para Federico (no asumidas, quedan en el documento)

- ¿El Plan Semanal del sistema viejo excluye Domingo a propósito (6 días,
  no 7) o es un bug? Afecta si replicamos ese comportamiento en
  `obtenerRangoSemana()`.
- ¿Existe un rol "Plantista" liso (sin "Jefe"), distinto de "Plantista
  (Jefe)"? No lo vimos en la lista de usuarios ni en Permisos por rol.
- ¿Gerencia debería poder "Ver ventas externas"? El .rtf dice que sí, la
  configuración real en producción dice que no.
- ¿Por qué "Plantista Hormigón" no tiene card en Permisos por rol pese a
  tener un usuario activo con ese rol? ¿Sus permisos están hardcodeados en
  otro lado?
- ¿El login del Balancero (`balanza@vialtec.com.ar`) es una cuenta
  compartida de kiosko a propósito? Si sí, nuestro modelo de auth (email
  personal por usuario) necesita contemplarlo.
- ¿Cómo se crea una venta externa desde cero en "Nuevo pedido"? El toggle
  "Producción interna" no reaccionó a los clics en esta sesión — puede
  necesitar otra interacción o estar gateado.

## Etapa 1 — CERRADA (2026-08-27)

Los 13 módulos del sistema viejo quedaron relevados. Sigue Etapa 2:
identidad visual de `equipos2.vialtec.app` → `memory/guia-estilo-flota.md`.

---

## Etapa 3 — Relevamiento minucioso de botones/modales/tablas (2026-08-28)

Segunda pasada en vivo (navegación real, sesión de Federico como
Administrador), a pedido explícito: precisión de etiquetas exactas de
botones, orden y obligatoriedad de campos en cada modal, columnas exactas de
tablas, formatos de fecha/número. **Alcance acotado a foco operativo**
(botones/KPIs/funcionalidad) — Federico aclaró en esta misma sesión que el
detalle visual (colores, tipografía) ya está resuelto en la rama de estilo
(`memory/guia-estilo-flota.md`) y no hace falta calcarlo del sistema viejo.

### Colores por estado de pedido (único punto visual que sí vale la pena, porque es semántico)

Confirmado con `getComputedStyle` antes de que se acotara el alcance:
`solicitado` = ámbar (`#B45309`/`#F59E0B`), `confirmado` = azul (`#1D4ED8`/`#3B82F6`),
`despachado` = verde esmeralda (`#065F46`/`#10B981`), **`postergado` = VIOLETA**
(`#5B21B6`/`#8B5CF6` — no ámbar, corrige el mapeo anterior), `cancelado` = rojo
(`#991B1B`/`#EF4444`). Nuestro `VARIANTE_ESTADO` en `PedidosView.vue` hoy
mapea `postergado` a `warning` (ámbar) — mismo color que `solicitado`,
perdiendo la distinción visual que sí tiene el legado. Ajuste sugerido (bajo
impacto, no bloqueante): agregar una variante `postergado`/violeta a
`VBadge` en algún momento, no urgente.

### Pedidos — modal "Nuevo pedido"

Campos, en orden exacto, confirmando obligatoriedad real por la marca
"opcional" que el legado pone al lado del label (todo lo que NO dice
"opcional" es requerido):
1. `TIPO DE PEDIDO` — botón único "Producción interna" (violeta, ancho
   completo). **Confirmado con certeza ahora (no es limitación de la
   automatización): el botón tiene `onclick` real, no está `disabled`, pero
   clickearlo NO cambia nada — nunca aparece "Venta externa".** Es un
   toggle roto/inaccesible en el legado, no solo "no pude probarlo". Sigue
   sin resolverse cómo se originaron los pedidos `tipo_pedido='venta'`
   existentes (AUTOVIA MERCOSUR, MUNICIPALIDAD DE PILAR) — probablemente un
   code path viejo ya no alcanzable desde la UI actual, o carga directa.
   **Para v2: no repliquemos el bug — nuestro toggle Producción
   interna/Venta externa ya funciona bien, dejarlo así.**
2. `OBRA / CENTRO DE COSTO` — select, requerido, 14 opciones con código
   (`CAM-01` etc., confirmado igual que Etapa 1).
3. `RESPONSABLE DEL PEDIDO` — **no es un input editable**: es un texto fijo
   con ícono de persona mostrando el usuario logueado (confirmado por
   accesibilidad: no aparece como `textbox` en el árbol interactivo).
   Corrige la Etapa 1, que lo daba por "editable" sin confirmar. En v2 hoy
   es un `<input>` de texto libre — es MÁS flexible que el legado, no hace
   falta achicarlo.
4. `TIPO DE PRODUCCIÓN` — toggle Todas/Hormigón/Asfalto, requerido (filtra Mezcla).
5. `MEZCLA` — select, requerido, 19 fórmulas.
6. `CANTIDAD (M³)` — requerido (el label cambia de unidad según mezcla).
7. `FECHA DE ENTREGA REQUERIDA` — requerido, prellenado con hoy.
8. `NOTAS` — **opcional** (marcado explícitamente).
9. `UBICACIÓN` — **opcional** (marcado explícitamente), placeholder "Ej:
   Acceso norte, km 12...". Ya migrado a v2 (migración 09).

Botones del footer: "Cancelar" (outline) / "Guardar pedido" (violeta).

### Pedidos — modal "Registrar despacho" (asfalto Y hormigón, mismo modal)

**Hallazgo nuevo importante**: el título del modal es "Registrar despacho"
para AMBOS materiales, no "Registrar carga de hormigón" como asumíamos —
mismo patrón multi-carga en los dos casos, confirmado abriendo ambos en
vivo:

- **Asfalto**: `CANTIDAD (TN) *` (prefill = saldo completo), `N° VALE *`
  (obligatorio por carga), `PATENTE (opcional)`. Botón "+ Agregar carga".
  "Total: X tn" (caja verde). Al final, fuera de la lista de cargas:
  `N° REMITO (OPCIONAL)` — uno solo para todo el despacho. Esto es
  **exactamente** lo que ya implementamos en `useDespachoAsfalto` — sin
  cambios necesarios.
- **Hormigón**: `CANTIDAD (M³) *` (prefill = saldo completo), `N° REMITO *`
  (obligatorio por carga, no vale), `PATENTE (opcional)`. Botón
  "+ Agregar carga", "Total: X m³". **Sin campo de remito global** (tiene
  sentido: para hormigón el remito YA es por carga). **Sin campo chofer.**
  **Gap real**: nuestro `useCargaHormigon`/modal actual solo registra UNA
  carga por apertura de modal (hay que reabrir "Registrar carga" por cada
  mixer) — el legado permite cargar N mixers en una sola sesión del modal,
  igual que asfalto. Vale la pena unificar hormigón al mismo patrón
  multi-carga que ya tiene `useDespachoAsfalto` (un solo modal "Registrar
  despacho" con "+ Agregar carga", reusable para los dos materiales).
- La segunda carga en adelante tiene botón ✕ para quitarla; la primera no
  (no se puede bajar de 1 carga).

### Pedidos — modal "Postergar pedido"

`NUEVA FECHA DE ENTREGA (OPCIONAL)` (prellenada con hoy) + `MOTIVO` (sin
asterisco → opcional, placeholder "Indicá el motivo..."). Confirma Etapa 1.

### Pedidos — modal "Cancelar pedido"

`MOTIVO *` (obligatorio, placeholder "Indicá el motivo..."). Botones
"Cancelar" (vuelve sin acción) / "Cancelar pedido" (outline rojo, no relleno
— dato nuevo). Confirma Etapa 1.

### Pedidos — modal "Historial del pedido"

Timeline: badge de estado + fecha DD/MM/YYYY HH:MM a la derecha + ícono
persona + nombre del usuario debajo. Confirma Etapa 1 exacto.

### Pedidos — nota visible en la card sin abrir nada

Confirmado con un caso real: un pedido `cancelado` muestra el motivo en una
caja con ⚠ dentro de la card ("⚠ Sé cargo dos veces el pedido"). Pedidos
`solicitado` muestran la nota/observación con ícono 📝 directo en la card
también (no solo en el historial).

### Báscula — selector de "Pedido / Obra" (Vale Asfalto)

**Hallazgo nuevo, posible bug del legado a NO replicar**: el combo de
pedidos del form "Vale Asfalto" no filtra por `tipo` — lista TODOS los
pedidos `confirmado`+`despachado` sin importar si son de asfalto o
hormigón. Vi en vivo un pedido "Predio Vialtec • Hormigón H-21 • 1 tn"
disponible para seleccionar dentro de un vale de asfalto. Formato exacto de
cada opción: `"{obra o cliente} • {fórmula} • {cantidad} tn"` + `" (despachado)"`
solo si ya está despachado (sin sufijo = confirmado). **Nuestro v2 ya
filtra correctamente por `tipo='asfalto'`** (`fetchPedidosAsfaltoParaPesada`)
— no replicar el bug del legado acá, es una mejora real que ya tenemos.

Etiqueta exacta del combo de tipo de vale: **"Vale Asfalto" / "Ingreso
Áridos" / "Vale Salida Áridos"** (nosotros decimos "Salida asfalto" /
"Ingreso árido" / "Egreso árido" — funcionalmente igual, wording levemente
distinto, ajuste cosmético opcional).

### Báscula — form "Vale Asfalto" (campos exactos)

`Pedido / Obra *`, `Patente *` (placeholder "Ej: PNZ 460"), `Chofer`
(opcional), `Bruto (tn) *`, `Tara (tn) *`, `Neto` (calculado, disabled),
`Temperatura (°C)` (opcional), `Fecha` (prellenada hoy). Botón "📋 Registrar
vale". Coincide con lo que ya implementamos en la migración 09.

### Báscula — form "Ingreso Áridos" (correcciones reales vs. lo que implementamos)

Campos exactos: `Material *` — **es un SELECT de catálogo**, no texto libre.
`Proveedor *` — **también SELECT**, no texto libre. `Remito (Proveedor) *`
— **REQUERIDO** (nosotros lo tenemos opcional — corregir). `Cantidad según
Remito (tn) *` — requerido. `Patente camión` (opcional). `Fecha`. `Bruto
(tn) *`, `Tara (tn) *`, `Neto` (calculado). **Sin campo chofer** (nuestro
form sí lo muestra para este tipo — de más, no rompe nada pero no está en
el legado). Botón "✓ Registrar ingreso".

**Gaps de datos accionables, en orden de esfuerzo:**
1. `Proveedor` a select: **sin costo** — `plantas_proveedores` ya existe
   como catálogo en v2, solo falta cambiar el `<input>` por un `<select>`
   en `BasculaView.vue`.
2. `N° Remito` a requerido: **sin costo**, es validación de UI + `not null`
   opcional a nivel RPC.
3. `Material` a select: bloqueado por el catálogo `plantas_materiales`, que
   todavía no existe (gap #2 de la Etapa 1, sigue abierto).

### Báscula — form "Vale Salida Áridos" (egreso — corrección real de diseño)

Campos exactos: `Material *` (select), **`Destino (Obra) *` — es un SELECT
de obra, requerido**, no un campo de texto libre como lo implementamos
nosotros (`destino` en migración 09 es una columna de texto). `Patente
camión` (opcional). `Fecha`. `Bruto (tn) *`, `Tara (tn) *`, `Neto`
(calculado). Sin chofer. Botón "🚛 Registrar egreso".

**Gap de diseño a corregir**: `plantas_vales` ya tiene `obra_id` (se usa
para asfalto) — lo correcto es reusar esa misma columna para
`egreso_arido` en vez de la columna `destino` de texto libre que agregamos
en la migración 09. Queda para la próxima pasada de implementación:
deprecar/quitar `destino` como texto libre, usar `obra_id` (select de
`flota_obras`, requerido) para egreso.

### Báscula — tabla "Movimientos del día" (columnas exactas)

`HORA, TIPO, MATERIAL/OBRA, PATENTE, REMITO, RESPONSABLE, VALE, BRUTO, TARA,
NETO, ACUM., S/REMITO, DIF.` + acciones. Confirmado en vivo: **`S/REMITO` y
`DIF.` solo tienen valor en filas `ING` (ingreso) — vacías (`—`) en filas
`VALE` (asfalto)**. Esto valida al 100% nuestra implementación de
`calcularDiferencia()` (devuelve `null` salvo para `ingreso_arido`) — no
hace falta tocar nada ahí.

Numeración de vale real observada en esta sesión: **próximo N° ≈ 9580**
(con alguna inconsistencia transitoria que llegó a mostrar 9961 al abrir
una puerta y volver a 9580 al cerrarla sin guardar — probablemente una
numeración especulativa client-side por puerta abierta, no confirmada al
servidor hasta guardar). No cambia nada de nuestro diseño (identity column
arranca en 9579, correcto), pero confirma que el valor real de producción
ronda los 9580, no los 9949 vistos en la Etapa 1 un día antes — **posible
reset/restauración del entorno de pruebas entre sesiones, a confirmar con
Federico si esto es relevante para la migración de historial** (memory/pending.md).

### Stock (PENDIENTE en v2 — relevado a fondo por primera vez con acciones reales)

- **Tabs**: "Stock actual" (cards semáforo, ya documentado en Etapa 1),
  "Historial de ingresos", "Analítica proveedores". Botones globales:
  "⬇ Excel", "▤ Relevamiento".
- **Historial de ingresos**: filtros MATERIAL/PROVEEDOR/DESDE/HASTA select+date.
  Tabla: `TIPO` (badge INGRESO verde / SALIDA roja), `MATERIAL`,
  `PROVEEDOR / MOTIVO`, `CANTIDAD` (+X t verde / −X t rojo), `REMITO`,
  `RESPONSABLE`, `FECHA` + ícono 🗑 eliminar en cada fila. 592 registros en
  esta sesión. **Confirma que SALIDA (egreso manual) también existe como
  fila en esta misma tabla** — un movimiento "Fuel Oil −37,55 t" sin
  proveedor/remito, responsable "Felix Pereyra". No encontré el botón para
  cargar un ingreso/egreso manual nuevo en esta pasada (puede estar
  gateado por algo que no disparé) — sigue como pregunta abierta.
- **"Relevamiento"** (botón, modal "Relevamiento mensual"): **advertencia
  explícita "⚠ Reemplaza el stock actual."** — un input numérico en
  toneladas por CADA uno de los 16 materiales (prellenado con el valor
  actual, 3 decimales), botones Cancelar/Guardar. Es un overwrite total y
  directo del stock, sin ningún movimiento/auditoría intermedio aparente —
  herramienta de alto riesgo, coincide con gap #15 de Etapa 1 ("Reconstruir
  stock" en Backups es distinto, ahí se recalcula desde movimientos; esto
  reemplaza a mano). No la ejecuté (no toqué "Guardar").
- **Analítica proveedores**: selector MES/AÑO + rango, botón "↓ Descargar
  en Excel". Por proveedor: card con nombre + KPIs (viajes, total tn) +
  tabla insumo/viajes/toneladas con fila TOTAL resaltada. Es básicamente lo
  mismo que ya tenemos en el Dashboard de v2 (`fetchAnaliticaProveedores`),
  pero acá vive como tab de Stock, no del Dashboard — a decidir si
  replicamos esa ubicación cuando construyamos el módulo Stock.
- 16 materiales confirmados en el semáforo (no 18 — ese es el conteo del
  catálogo Maestros completo, incluye materiales sin tarjeta de stock).

### Despachos (PENDIENTE en v2 — botones/columnas exactos confirmados)

Botones exactos (por accesibilidad, sin el emoji que es solo decorativo):
**"Eficiencia", "Resumen mensual", "Excel período", "Por obra", "Excel
completo"**. KPIs: `ASFALTO AGOSTO`, `HORMIGÓN AGOSTO`, `↑ TOTAL ASFALTO
ACUMULADO`, `↑ TOTAL HORMIGÓN ACUMULADO` (4, no 2). "RESUMEN POR OBRA":
selector de mes (no rango de fechas libre, es `<input type="month">`) +
"↓ Exportar Excel" + grid de cards por obra (nombre + total + "N
despachos"). Filtros: pill Todos/Hormigón/Asfalto + Mezcla + Obra +
Desde/Hasta. Tabla: `FECHA` (+ responsable debajo), `OBRA`, `MEZCLA`,
`PEDIDO`, `REAL`, `DIFERENCIA` + 4 acciones exactas (confirmado por
accesibilidad): **"Ver detalle de cargas"**, **"Corregir"** (no "Editar"),
**"Ver remito"** (no "Imprimir"), **"Eliminar despacho y restaurar
stock"** — este último confirma que el delete SÍ revierte el descuento de
stock, no es solo borrar el registro. Sigue en pie la decisión ya tomada:
**v2 no agrega "Eliminar"** (regla de negocio de auditoría).

Modal "Detalle del despacho" (🚛): header obra+fecha+mezcla, lista "Carga N
— {patente} — {cantidad} tn" con "Remito:" debajo de cada una (vacío para
asfalto, que usa vale), footer "Total despachado X tn" (caja verde) + "N°
Vale: 8946/47/48/49/50/51/52." (rango compacto de vales consecutivos).

### Plan semanal — confirmación DEFINITIVA de la exclusión de domingo

Repetido en una sesión distinta, un día después: el banner dice **"24 al 29
de agosto 2026"** (título, hasta sábado) aunque el subtítulo técnico debajo
diga "24/08/2026 → 30/08/2026" (rango real usado para la query, hasta
domingo) y el cronograma semanal solo tenga 6 columnas (LUN a SÁB). **Ya no
es una duda — es un comportamiento estable y deliberado del legado**: el
rango de datos incluye el domingo pero la UI nunca le da columna propia.
**Sigue como decisión abierta para Federico** si `obtenerRangoSemana()` en
v2 debe calzar con esto (6 días visibles) o mantener los 7 días — ahora con
evidencia más sólida de que no es un bug transitorio.

Tabla "INSUMOS REQUERIDOS — SEMÁFORO DE STOCK", columnas exactas:
`INSUMO, STOCK ACTUAL, CONSUMO ESTIMADO, STOCK PROYECTADO, DÍAS EST.,
ESTADO`. Vi valores de `DÍAS EST.` absurdamente altos para materiales con
consumo casi nulo (ej. `≈22628d`) — no hay tope/cap visible, formato crudo
`≈{n}d`.

Toggle "▤ Tabla" / "▭ Cards" (no viene por defecto en Cards como asumíamos
— hay que confirmar cuál es el default real, no lo verifiqué). Botón "↓
Excel" y navegación "‹ ›" por semana. Badge "11 pedidos activos".

### Fórmulas — modal "Editar fórmula" (antes no abierto)

`NOMBRE` (texto), `TIPO` (select Hormigón/Asfalto), `UNIDAD` (select, ej.
"m³ (hormigón)" — cambia con tipo), `COMPONENTES`: lista de filas
"Material — cantidad unidad" con ✕ para quitar, más una fila para agregar
(select de Material del catálogo + input Cant. + select de unidad + botón
"+"). **Confirma otra vez que "Material" es un select de catálogo**, no
texto libre — coherente con Báscula y Stock. Nuestro v2 hoy edita insumos
como texto libre inline en `FormulasView.vue` — mismo gap que venimos
viendo, bloqueado por el catálogo `plantas_materiales` inexistente.

### Maestros — Materiales/Insumos, modal "Editar" (antes no abierto)

`NOMBRE DEL MATERIAL` (texto), `UNIDAD` (texto libre marcado "referencia",
no un enum estricto — ej. "TN"), `CATEGORÍA` (texto libre, "opcional"),
`STOCK MÍNIMO DE ALERTA (KG)` ("avisa si cae por debajo", placeholder "Ej:
5000"). **Pregunta abierta**: el campo de este modal es singular ("stock
mínimo"), pero las cards de Stock muestran min Y máx (ej. "min 8t / máx
15t") — no encontré dónde se configura el máximo; puede vivir en otro
lugar no relevado en esta pasada.

### Usuarios — modal "Nuevo usuario" (antes no abierto, sin crear un usuario real)

Campos exactos: `NOMBRE COMPLETO`, `EMAIL`, `WHATSAPP (código país +
número)` (opcional, placeholder "Ej: 5491123456789"), `ROL` (select),
`OBRAS A CARGO (puede seleccionar más de una)` (checklist de las 14 obras
— presumiblemente solo visible/relevante para encargado/supervisor),
`ESTADO` (select, default Activo), `GESTIÓN DE USUARIOS` → checkbox "Puede
crear y editar usuarios". Banner informativo: *"ℹ En producción el usuario
recibirá un mail para crear su contraseña. En este prototipo el login es
por email solamente."* (confirma el problema conocido documentado en
`pending.md`). **Gap real**: `plantas_usuarios_roles` no tiene un flag
equivalente a "gestión de usuarios" — no bloqueante hoy (el módulo Usuarios
de v2 sigue PENDIENTE), pero a sumar al diseño cuando se construya.

También se vio un usuario `Inactivo` (Juan Martin Heinrich) — la card entera
se atenúa (texto gris) y el botón "Editar" queda deshabilitado.

### Backups — confirmado el mismo comportamiento roto en una sesión distinta

"Cargando backups..." nunca resuelve (ícono de reloj de arena, sin
contenido) — igual que en la Etapa 1, un día después y en una sesión
nueva. Ya no es "no llegué a verlo cargado", es un estado consistente:
**el listado de backups parece no funcionar en este entorno**. Botones
"Reconstruir stock" y "Backup ahora" siguen presentes arriba, no los
ejecuté (acciones potencialmente destructivas/pesadas sobre datos reales).

### Permisos por rol — sin cambios respecto a Etapa 1

Estructura, banner de aviso y valores por rol confirmados idénticos a la
primera pasada. No se relevó de nuevo en detalle porque ya estaba completo.

---

## Resumen de acciones concretas que salen de esta pasada (para la próxima sesión de implementación)

Bajo costo, sin cambio de schema:
1. ✅ **HECHO (2026-08-28, Fase 2 Báscula)** — Báscula → Ingreso Áridos:
   `Proveedor` de `<input>` a `<select>` sobre `plantas_proveedores`.
2. ✅ **HECHO** — Báscula → Ingreso Áridos: `N° Remito` pasa a requerido.
3. ✅ **HECHO** — Báscula → se sacó el campo "Chofer" de los forms de
   Ingreso/Egreso de áridos.
4. `VBadge`: variante nueva para `postergado` (violeta), separada de
   `warning` — **sigue pendiente**, no se tocó en esta tanda (era de
   Pedidos, no de Báscula).

Con cambio de schema (requiere el mismo protocolo de aviso previo):
5. ✅ **HECHO (migración 10)** — Báscula → Egreso de áridos: `destino`
   (texto libre) reemplazado por `obra_id` (select requerido), reusando la
   columna que ya existía en `plantas_vales`. La columna `destino` (agregada
   en la migración 09) se eliminó — no quedó como deuda técnica.
6. Unificar el modal de despacho de hormigón al mismo patrón multi-carga
   que ya tiene asfalto (`useDespachoAsfalto`) — **sigue pendiente**, es de
   Pedidos, no de Báscula, no se tocó en esta tanda.

Ver `memory/modules-status.md` → "Báscula — Fase 1 + Fase 2 de fidelidad
funcional — CERRADA (2026-08-28)" para el detalle completo de lo
implementado en esta sesión (impresión A4 landscape, auto-print, acumulado
por pedido, validación de remito duplicado, header con puertas/próximo N°,
apertura de puerta única con select interno, colapso por puerta).

Preguntas abiertas nuevas para Federico:
- ¿Por qué el "próximo N° de vale" real bajó de ~9949 (2026-08-27) a ~9580
  (2026-08-28)? ¿El entorno de pruebas se resetea entre sesiones?
- ¿Dónde se configura el stock MÁXIMO por material? (el modal de Maestros
  solo tiene un campo de mínimo).
- ¿Hay un botón de ingreso/egreso manual en Stock que no encontré en esta
  pasada, o esos movimientos solo se cargan desde Báscula/Relevamiento?
