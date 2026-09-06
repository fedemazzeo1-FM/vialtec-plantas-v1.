-- ============================================================================
-- AUDITORÍA: delta acumulado en el legado desde el 01/09/2026 — SOLO LECTURA
--
-- Extiende auditoria_historico_vs_legado.sql (que verifica lo YA migrado,
-- fecha < 2026-09-01) para cuantificar lo que el legado sigue acumulando en
-- paralelo desde esa fecha — el "delta" que la migración final (Paso 4,
-- memory/pending.md) tiene que capturar antes del corte de dominio.
--
-- Corrida 2026-09-06 (ver memory/pending.md para el resultado completo y el
-- detalle de colisión de numero_vale, que dio 0 — la renumeración de vales
-- sintéticos del mismo día liberó exactamente el rango 9994-10013 donde cae
-- este delta real).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Pedidos — delta desde 01/09.
-- ----------------------------------------------------------------------------
with legado as (
  select v->>'id' as id_legado, (v->>'fecha')::date as fecha
  from kv_store, jsonb_array_elements(value) as v where key = 'vt_p9'
)
select
  count(*) filter (where fecha >= '2026-09-01') as legado_delta,
  count(*) filter (where fecha >= '2026-09-01' and pp.id is not null) as ya_migrados,
  count(*) filter (where fecha >= '2026-09-01' and pp.id is null) as pendientes
from legado l
left join plantas_pedidos pp on pp.datos_legados ->> 'id' = l.id_legado;

-- Detalle de los pendientes:
-- with legado as (
--   select v->>'id' as id_legado, (v->>'fecha')::date as fecha, v->>'estado' as estado, v->>'cantidad' as cantidad
--   from kv_store, jsonb_array_elements(value) as v where key = 'vt_p9'
-- )
-- select l.* from legado l
-- left join plantas_pedidos pp on pp.datos_legados ->> 'id' = l.id_legado
-- where l.fecha >= '2026-09-01' and pp.id is null order by l.fecha;

-- ----------------------------------------------------------------------------
-- 2) Historial de pedidos — delta desde 01/09.
-- ----------------------------------------------------------------------------
with legado as (
  select p->>'id' as pedido_id_legado, evento, (nullif(evento->>'fecha','')::date) as fecha
  from kv_store, jsonb_array_elements(value) as p
  cross join lateral jsonb_array_elements(coalesce(p->'historial', '[]'::jsonb)) as evento
  where key = 'vt_p9'
    and (evento->>'estado') in ('solicitado','confirmado','despachado','postergado','cancelado')
)
select
  count(*) filter (where fecha >= '2026-09-01') as legado_delta,
  count(*) filter (where fecha >= '2026-09-01' and pph.id is not null) as ya_migrados,
  count(*) filter (where fecha >= '2026-09-01' and pph.id is null) as pendientes
from legado l
left join plantas_pedidos pp on pp.datos_legados ->> 'id' = l.pedido_id_legado
left join plantas_pedidos_historial pph on pph.pedido_id = pp.id and pph.datos_legados = l.evento;

-- ----------------------------------------------------------------------------
-- 3) Cargas de hormigón — delta desde 01/09.
-- ----------------------------------------------------------------------------
with legado as (
  select p->>'id' as pedido_id_legado, (p->>'fecha')::date as fecha, camion
  from kv_store, jsonb_array_elements(value) as p
  cross join lateral jsonb_array_elements(coalesce(p->'camiones', '[]'::jsonb)) as camion
  where key = 'vt_p9'
    and camion->>'nroRemito' is not null and camion->>'nroRemito' <> ''
    and camion->>'cantidad' is not null
)
select
  count(*) filter (where l.fecha >= '2026-09-01' and pf.tipo = 'hormigon') as legado_delta,
  count(*) filter (where l.fecha >= '2026-09-01' and pf.tipo = 'hormigon' and pch.id is not null) as ya_migrados,
  count(*) filter (where l.fecha >= '2026-09-01' and pf.tipo = 'hormigon' and pch.id is null) as pendientes
from legado l
left join plantas_pedidos pp on pp.datos_legados ->> 'id' = l.pedido_id_legado
left join plantas_formulas pf on pf.id = pp.formula_id
left join plantas_cargas_hormigon pch on pch.pedido_id = pp.id and pch.datos_legados = l.camion;

-- ----------------------------------------------------------------------------
-- 4) Vales (Báscula) — delta desde 01/09, asfalto + egreso_arido (los que
--    conservan numero real). ingreso_arido queda en el bloque 5 (numero
--    sintético, matchea distinto).
-- ----------------------------------------------------------------------------
with legado as (
  select 'asfalto' as tipo, v->>'id' as id_legado, (v->>'fecha')::date as fecha, (v->>'numero')::bigint as numero
  from kv_store, jsonb_array_elements(value) as v where key = 'vt_vales9'
  union all
  select 'egreso_arido', v->>'id', (v->>'fecha')::date, (v->>'numero')::bigint
  from kv_store, jsonb_array_elements(value) as v where key = 'vt_egaridos9'
)
select
  l.tipo,
  count(*) filter (where fecha >= '2026-09-01') as legado_delta,
  count(*) filter (where fecha >= '2026-09-01' and pv.id is not null) as ya_migrados,
  count(*) filter (where fecha >= '2026-09-01' and pv.id is null) as pendientes
from legado l
left join plantas_vales pv on pv.datos_legados ->> 'id' = l.id_legado
group by l.tipo;

-- ----------------------------------------------------------------------------
-- 4b) CRÍTICO — colisión de numero_vale: ¿alguno de los pendientes de arriba
--     ya tiene ese número ocupado por OTRA fila real (asfalto o egreso) en
--     plantas_vales? Si esto da filas, la migración final NO puede insertar
--     ese vale con `overriding system value` tal cual — hay que decidir cómo
--     renumerar antes de correrla de verdad. Resultado 2026-09-06: 0 filas
--     (el rango real pendiente, 9994-10013, quedó liberado por la
--     renumeración de vales sintéticos del mismo día).
-- ----------------------------------------------------------------------------
with legado_pendientes as (
  select v->>'id' as id_legado, (v->>'fecha')::date as fecha, (v->>'numero')::bigint as numero_legado
  from kv_store, jsonb_array_elements(value) as v where key = 'vt_vales9'
  union all
  select v->>'id', (v->>'fecha')::date, (v->>'numero')::bigint
  from kv_store, jsonb_array_elements(value) as v where key = 'vt_egaridos9'
)
select lp.id_legado, lp.fecha, lp.numero_legado, pv.id as colisiona_con_id, pv.tipo_vale as colisiona_tipo
from legado_pendientes lp
left join plantas_vales pv_propio on pv_propio.datos_legados ->> 'id' = lp.id_legado
left join plantas_vales pv on pv.numero_vale = lp.numero_legado
where lp.fecha >= '2026-09-01' and pv_propio.id is null and pv.id is not null;

-- ----------------------------------------------------------------------------
-- 5) Stock movimientos (vt_m9, incl. ingreso_arido con numero sintético) —
--    delta desde 01/09, excluyendo 'relevamiento' (ver bloque 6).
-- ----------------------------------------------------------------------------
with legado as (
  select v->>'id' as id_legado, (v->>'fecha')::date as fecha, v->>'tipo' as tipo_legado
  from kv_store, jsonb_array_elements(value) as v where key = 'vt_m9'
)
select
  l.tipo_legado,
  count(*) filter (where l.fecha >= '2026-09-01') as legado_delta,
  count(*) filter (where l.fecha >= '2026-09-01' and psm.id is not null) as ya_migrados,
  count(*) filter (where l.fecha >= '2026-09-01' and psm.id is null) as pendientes
from legado l
left join plantas_stock_movimientos psm on psm.datos_legados ->> 'id' = l.id_legado
where l.tipo_legado <> 'relevamiento'
group by l.tipo_legado
order by l.tipo_legado;

-- ----------------------------------------------------------------------------
-- 6) Stock — relevamientos nuevos desde 01/09 (si Federico cargó alguno en
--    el legado en paralelo — mismo criterio de delta que el resto, no migra
--    solo, requiere decisión sobre cómo tratar el snapshot final de stock,
--    ver memory/pending.md "Paso 4").
-- ----------------------------------------------------------------------------
select v->>'id' as id_legado, (v->>'fecha')::date as fecha, v->>'motivo' as motivo
from kv_store, jsonb_array_elements(value) as v
where key = 'vt_m9' and v->>'tipo' = 'relevamiento' and (v->>'fecha')::date >= '2026-09-01'
order by fecha;
