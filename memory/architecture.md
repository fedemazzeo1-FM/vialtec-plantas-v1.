# architecture.md — Arquitectura técnica

## Stack

- **Vue 3** (Composition API, `<script setup>`)
- **Vite** como bundler/dev server
- **Vue Router** para ruteo (`src/router/index.js`)
- **Pinia** para estado global (stores en `src/stores/`)
- **Tailwind CSS** para estilos
- **Supabase** como backend único (Auth + Postgres + Storage)

## Supabase — instancia única

- Un solo proyecto de Supabase para todo VialTec: `ejitztewkpnmrckwmvny`.
- Se comparte con el sistema de flota existente. **No crear un segundo proyecto.**
- El cliente de Supabase se instancia **una sola vez** en `src/config/supabase.js`
  y se importa desde ahí en todo el resto del código. Nunca instanciar
  `createClient()` en otro archivo.
- Credenciales (URL y anon key) vía variables de entorno (`VITE_SUPABASE_URL`,
  `VITE_SUPABASE_ANON_KEY`), nunca hardcodeadas en el repo.

## Tablas: compartidas vs. relacionales del módulo

- **`flota_*`** — tablas compartidas con el sistema de flota, ya existentes:
  obras, empresas, usuarios, roles. VialTec Plantas **lee y relaciona contra ellas**
  pero no es dueño de su schema. Cualquier cambio a una tabla `flota_*` puede
  romper el sistema de flota — ver protocolo de aviso previo en `procedimientos.md`.
- **`plantas_*`** — tablas propias de este módulo (pedidos, fórmulas, stock, vales,
  báscula, despachos, maestros específicos de planta, etc.). Se relacionan contra
  `flota_*` por foreign key (por ejemplo, `plantas_pedidos.obra_id -> flota_obras.id`).
- El sistema legado (pre-migración) guardaba casi todo como blobs JSON en claves
  tipo `vt_usuarios9`, `vt_bak_YYYY-MM-DD`, etc. La migración a `plantas_*` implica
  pasar de ese modelo documental a tablas relacionales reales. Ver `pending.md`.

**Ubicación del sistema legado (corregido 2026-09-01, confirmado en vivo
leyendo su contenido real):** el dato de 2026-08-27 de abajo era incorrecto
— no se había buscado en el lugar correcto. El legado **sí vive en este
mismo proyecto de Supabase** (`ejitztewkpnmrckwmvny`), dentro de una tabla
genérica `kv_store(key text, value jsonb, updated_at timestamptz)`. No hay
tablas `vt_*` reales (por eso la búsqueda contra `information_schema.tables`
de 2026-08-27 no encontró nada) — son **claves** dentro de `kv_store`:
`vt_p9` (pedidos), `vt_s9` (stock actual), `vt_f9` (fórmulas), `vt_vales9`
(vales de asfalto), `vt_ingaridos9`/`vt_egaridos9` (ingreso/egreso de
áridos), `vt_m9` (movimientos de stock), `vt_usuarios9`, `vt_maestros9`
(obras/materiales/proveedores/patentes propias del legado). No hace falta
ETL cross-motor ni CSV: la migración lee `kv_store` directo con
`jsonb_array_elements` en el mismo `SELECT`. Ver `pending.md` para el
estado de la migración y `supabase/scripts/migracion_historial_v2.sql`
(reemplaza al `migracion_historial_borrador.sql` anterior, que asumía el
origen externo incorrecto — ya no es la referencia vigente).

## REGLA DE PAGINACIÓN CRÍTICA

**Toda query a Supabase que pueda superar las 1,000 filas DEBE usar `fetchPaginado()`
o `.range()`.**

PostgREST/Supabase corta el resultado en 1,000 filas **de forma silenciosa**, sin
error ni warning. Un `.select('*')` sin paginar sobre `plantas_pedidos`,
`plantas_vales`, `plantas_stock_movimientos`, o cualquier tabla de historial que
crezca sin límite, puede devolver datos incompletos sin que se note — y esto es
especialmente peligroso porque este sistema migra años de historial del sistema
anterior.

- Usar el helper `fetchPaginado()` (a definir en un service común) para cualquier
  listado potencialmente grande, o iterar manualmente con `.range(from, to)`
  hasta agotar los resultados.
- Nunca asumir que un `count` chico hoy va a seguir siendo chico — si la tabla es
  de las que acumulan historial (vales, movimientos de stock, pedidos), paginar
  siempre, no "cuando haga falta".

## Capas del código

- `src/config/` — instancia de Supabase y configuración de la app.
- `src/stores/` — Pinia stores (estado global, ej. `auth.store.js`).
- `src/modules/` — un directorio por módulo de negocio (pedidos, stock, báscula,
  fórmulas, maestros, etc.), cada uno con su/sus `*.service.js`.
- `src/services/` — helpers/services **transversales**, no atados a un solo
  módulo: `fetch-paginado.js` (regla de paginación) y `flota.service.js`
  (lecturas de solo lectura sobre tablas `flota_*` compartidas, ej. obras).
  Si dos o más módulos necesitan la misma lectura sobre `flota_*`, va acá, no
  duplicada en cada `modules/<x>/services/`.
- `src/components/shared/` — componentes UI reutilizables entre módulos.
- `src/layouts/` — `DesktopLayout` y `MobileLayout`.
- `src/views/` — vistas ruteadas.
- `src/router/` — definición de rutas.

Ver también `conventions.md` para naming, `modules-status.md` para el estado de
cada módulo y `business-rules.md` para las reglas de negocio que debe respetar
cada service.
