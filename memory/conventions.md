# conventions.md — Convenciones de código

## Naming de archivos

- **Archivos `.js`**: `kebab-case` (ej. `pedidos.service.js`, `fetch-paginado.js`).
- **Archivos `.vue`**: `PascalCase` (ej. `VCard.vue`, `PedidoDetalle.vue`,
  `DesktopLayout.vue`).
- **Variables y funciones**: `camelCase` (ej. `cantidadReal`, `fetchPedidosDelMes`).
- **Constantes globales/env**: `UPPER_SNAKE_CASE` cuando aplique (ej.
  `SIN_STOCK_MATERIALES`).
- Nombres de tablas Supabase: `snake_case` con prefijo de dominio
  (`plantas_pedidos`, `plantas_vales`, `flota_obras`, `flota_usuarios`).

## Services obligatorios por módulo

- Cada módulo de negocio en `src/modules/<modulo>/` debe tener su propio
  `*.service.js` que encapsule **todo** el acceso a Supabase de ese módulo
  (queries, inserts, updates). Los componentes Vue no llaman a Supabase
  directamente — llaman al service del módulo.
- Un service es responsable de aplicar la regla de paginación
  (`fetchPaginado()`/`.range()`) en cualquier query que pueda superar 1,000 filas
  (ver `architecture.md`).
- Lógica compartida entre módulos (ej. cálculo de consumo de fórmula, conversión
  kg/tn) va en un helper común, no duplicada en cada service.

## Componentes compartidos

- Los componentes reutilizables viven en `src/components/shared/` y se prefijan
  con `V` (ej. `VCard`, `VKpiCard`, `VBadge`, `VTable`, `VSection`, `VModal`,
  `VSemaforo`). Un módulo no debe reimplementar una variante propia de un `V*`
  ya existente.

## Estilo general

- Composition API con `<script setup>` en todos los componentes nuevos.
- Tailwind para estilos; evitar CSS custom salvo casos puntuales no cubiertos por
  utilities.
- Commits claros y acotados — ver protocolo en `procedimientos.md`.
