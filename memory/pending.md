# pending.md — Pendientes

## Migración del historial del sistema anterior (prioritaria)

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

## Migración del historial legado — mapeo y schema de soporte (avance)

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

Pendiente antes de poder correr el borrador en serio:
- **Resuelto en parte (2026-08-27, ver `architecture.md`):** el sistema
  legado vive en una base/motor externo a Supabase, no en este proyecto —
  confirmado por Federico. El borrador asume staging tables (`raw jsonb`) ya
  cargadas en Postgres; con un origen externo real, la carga va a ser vía
  ETL/CSV, no un `insert` directo — el paso 0 del borrador hay que
  reemplazarlo por lo que sea que exporte ese sistema (CSV → `\copy` a una
  tabla intermedia con columnas tipadas, o CSV → jsonb si el export lo
  permite). El resto del script (reconciliación de obras, inserts a
  `plantas_*`) no cambia.
- Sigue sin definir el formato/estructura exacta del export CSV (columnas,
  encoding, cómo vienen los arrays anidados como `historial` o `camiones` en
  un CSV plano) — no hay ninguna muestra real todavía.
- Contra qué campo del legado se hace el lookup de `plantas_formulas` (el
  pedido legado trae `formulaId`, pero es FK al scaffold huérfano ya
  descartado — el borrador asume un lookup por nombre, sin confirmar).
- Validar contra un pedido/vale real si el supuesto de
  `fecha_programada_anterior`/`nueva` en `plantas_pedidos_historial` para
  eventos `postergado` es correcto (el borrador deja ese cálculo fuera,
  como TODO explícito).

## Otros pendientes

- Definir el mapeo de los 7 roles del sistema anterior (`admin`, `plantista`,
  `encargado`, `supervisor`, `balancero`, `gerencia`, `plantista_hormigon`) contra
  el modelo de roles/usuarios ya existente en `flota_*`.
- Decidir si el flujo de invite de usuarios a Supabase Auth se automatiza en este
  proyecto (en el sistema anterior era manual — problema conocido, nunca
  resuelto).
- Definir el helper `fetchPaginado()` mencionado en `architecture.md` como
  utilidad común antes de escribir el primer service que liste una tabla grande.
