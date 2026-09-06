-- Migración 25: hallazgo real durante el smoke-test post-RLS (2026-09-06) —
-- "canceling statement due to statement timeout" al abrir Stock → Historial
-- de ingresos. Causa: la migración 23 le agregó RLS a `plantas_stock_movimientos`
-- (`plantas_puede_ver_stock()`, SECURITY DEFINER, opaca para el planner).
-- `plantas_v_stock_movimientos_viva` la lee dos veces sin materializar
-- (CTE "migrados" + el NOT EXISTS de "legado_movimientos", correlado fila
-- por fila contra ~700+ elementos del array de `vt_m9` en kv_store) — el
-- planner puede elegir un plan que reevalúe esa RLS por cada fila externa
-- en vez de una sola vez (mismo bug, misma causa raíz, que ya se había
-- encontrado y resuelto en `plantas_v_bascula_viva` el 2026-09-04 con una
-- CTE materialized — esa vista no se toca acá porque YA materializa
-- `plantas_vales`/`plantas_ingresos` en `pv_base`, no le afecta este RLS
-- nuevo). Reproducido de forma intermitente (una corrida en vivo dio
-- timeout; el EXPLAIN ANALYZE inmediato después corrió en 144ms con plan
-- hash — exactamente el patrón de inestabilidad de plan ya documentado).
--
-- Fix: la misma solución ya probada — una CTE `psm_visible AS MATERIALIZED`
-- que lee `plantas_stock_movimientos` (con su RLS) UNA sola vez; las dos
-- CTEs de abajo ("migrados" y el NOT EXISTS de "legado_movimientos") pasan
-- a leer de ahí en vez de la tabla real directo.

create or replace view public.plantas_v_stock_movimientos_viva as
with psm_visible as materialized (
  select * from plantas_stock_movimientos
),
legado_movimientos as (
  select
    md5('stock:' || (m.value ->> 'id'))::uuid as id,
    pm.id as material_id,
    pm.nombre as material_nombre,
    case m.value ->> 'tipo'
      when 'ingreso_aridos' then 'ingreso_proveedor'
      when 'ingreso' then 'ingreso_proveedor'
      when 'egreso_aridos' then 'egreso_arido'
      when 'salida' then 'egreso_manual'
      else null
    end as tipo,
    case
      when (m.value ->> 'tipo') = any (array['ingreso_aridos', 'ingreso'])
        then abs(coalesce((m.value ->> 'cantidadKg')::numeric, (m.value ->> 'cantidad')::numeric))
      else -abs(coalesce((m.value ->> 'cantidadKg')::numeric, (m.value ->> 'cantidad')::numeric))
    end as cantidad_kg,
    coalesce(nullif(m.value ->> 'proveedor', ''), nullif(m.value ->> 'motivo', '')) as origen,
    nullif(m.value ->> 'nroRemito', '') as numero_remito,
    nullif(m.value ->> 'observaciones', '') as observaciones,
    case
      when nullif(m.value ->> 'hora', '') is not null
        then (((m.value ->> 'fecha') || ' ' || (m.value ->> 'hora'))::timestamp without time zone) at time zone 'America/Argentina/Buenos_Aires'
      when nullif(m.value ->> 'fechaHora', '') is not null
        then (m.value ->> 'fechaHora')::timestamp with time zone
      else (((m.value ->> 'fecha')::date)::timestamp without time zone) at time zone 'America/Argentina/Buenos_Aires'
    end as fecha_movimiento,
    null::text as responsable_email,
    nullif(m.value ->> 'operador', '') as responsable_texto_legado,
    true as pendiente_migracion
  from kv_store,
    lateral jsonb_array_elements(kv_store.value) m(value)
    join plantas_materiales pm
      on lower(btrim(pm.nombre)) = lower(btrim(coalesce(m.value ->> 'insumo', m.value ->> 'material')))
  where kv_store.key = 'vt_m9'
    and (m.value ->> 'tipo') <> 'relevamiento'
    and coalesce((m.value ->> 'cantidadKg')::numeric, (m.value ->> 'cantidad')::numeric, 0) <> 0
    and not exists (
      select 1 from psm_visible psm
      where psm.material_id = pm.id and psm.datos_legados = m.value
    )
),
migrados as (
  select
    psm.id,
    psm.material_id,
    pm.nombre as material_nombre,
    psm.tipo,
    psm.cantidad_kg,
    psm.origen,
    psm.numero_remito,
    psm.observaciones,
    psm.fecha_movimiento,
    psm.responsable_email,
    psm.datos_legados ->> 'operador' as responsable_texto_legado,
    false as pendiente_migracion
  from psm_visible psm
    join plantas_materiales pm on pm.id = psm.material_id
)
select * from migrados
union all
select * from legado_movimientos;
