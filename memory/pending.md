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

## Otros pendientes

- Definir el mapeo de los 7 roles del sistema anterior (`admin`, `plantista`,
  `encargado`, `supervisor`, `balancero`, `gerencia`, `plantista_hormigon`) contra
  el modelo de roles/usuarios ya existente en `flota_*`.
- Decidir si el flujo de invite de usuarios a Supabase Auth se automatiza en este
  proyecto (en el sistema anterior era manual — problema conocido, nunca
  resuelto).
- Definir el helper `fetchPaginado()` mencionado en `architecture.md` como
  utilidad común antes de escribir el primer service que liste una tabla grande.
