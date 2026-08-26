-- ============================================================================
-- Migración 02: Pedidos
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- IMPORTANTE (memory/procedimientos.md): este archivo queda guardado para
-- revisión previa de Federico. NO se ejecutó contra Supabase todavía.
--
-- obra_id referencia flota_obras (bigint, tabla compartida y activa del
-- sistema de flota — 22 filas, usada por flota_equipos/flota_pedidos/etc.).
-- OJO: en el proyecto existe además una tabla `obras` (uuid, sin prefijo,
-- vacía) distinta de `flota_obras` — NO es esa la que se referencia acá.
-- Ver la nota completa en memory/pending.md ("Tablas legadas sin prefijo
-- detectadas en el proyecto compartido") antes de aplicar esta migración.
--
-- formula_id referencia plantas_formulas (uuid), creada en
-- 01_maestros_y_formulas.sql — esa migración debe aplicarse antes que esta.
-- ============================================================================

create table if not exists plantas_pedidos (
  id                  uuid primary key default gen_random_uuid(),
  obra_id             bigint not null references flota_obras (id),
  formula_id          uuid not null references plantas_formulas (id),
  tipo                text not null check (tipo in ('asfalto', 'hormigon')),
  cantidad_solicitada numeric not null check (cantidad_solicitada > 0),
  cantidad_despachada numeric check (cantidad_despachada > 0),
  fecha_programada    date not null,
  estado              text not null default 'solicitado'
                       check (estado in ('solicitado', 'confirmado', 'despachado', 'cancelado')),
  observaciones       text,
  created_at          timestamptz not null default now()
);

create index if not exists idx_plantas_pedidos_obra_id on plantas_pedidos (obra_id);
create index if not exists idx_plantas_pedidos_formula_id on plantas_pedidos (formula_id);
create index if not exists idx_plantas_pedidos_estado on plantas_pedidos (estado);
create index if not exists idx_plantas_pedidos_fecha_programada on plantas_pedidos (fecha_programada);

-- Índice compuesto para las queries de Plan Semanal (estado + rango de fecha).
create index if not exists idx_plantas_pedidos_estado_fecha on plantas_pedidos (estado, fecha_programada);

comment on table plantas_pedidos is
  'Pedidos de producción (asfalto/hormigón). Ciclo: solicitado -> confirmado -> despachado, o cancelado. Ver memory/business-rules.md.';

-- NOTA: este ciclo de 4 estados (sin "postergado") es una simplificación
-- deliberada respecto del ciclo de 5 estados del sistema legado documentado en
-- memory/business-rules.md (que incluye postergado -> confirmado). Si se
-- necesita reintroducir "postergado", hay que sumarlo al check de `estado` acá
-- y al servicio pedidos.service.js.
