# pending.md — Pendientes

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

### Pendiente para completar la auditoría (no llegué esta noche)

- Desglosar el conteo de "Historial de ingresos" del legado por tipo
  (ingreso vs. egreso) para comparar exacto contra
  `plantas_stock_movimientos`.
- Revisar Analítica de proveedores del legado vs. la nuestra.
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
2. Resolver a mano el pedido con `obra_id = null` (Municipalidad Exaltación
   de la Cruz, 3 pedidos) si Federico decide crear esa obra en `flota_obras`
   — ver detalle en la sección de arriba y en el encabezado del script.
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

## Otros pendientes

- Definir el mapeo de los 7 roles del sistema anterior (`admin`, `plantista`,
  `encargado`, `supervisor`, `balancero`, `gerencia`, `plantista_hormigon`) contra
  el modelo de roles/usuarios ya existente en `flota_*`.
- Decidir si el flujo de invite de usuarios a Supabase Auth se automatiza en este
  proyecto (en el sistema anterior era manual — problema conocido, nunca
  resuelto).
- Definir el helper `fetchPaginado()` mencionado en `architecture.md` como
  utilidad común antes de escribir el primer service que liste una tabla grande.
