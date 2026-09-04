-- ============================================================================
-- AUDITORÍA: histórico legado (kv_store) vs. plantas_* — SOLO LECTURA
--
-- Objetivo: verificar que todo lo migrado por migracion_historial_v2.sql
-- (2026-09-01) siga cuadrando 1:1 contra el legado para datos ANTERIORES al
-- 01/09/2026 — Báscula, Pedidos, Fórmulas, Stock (movimientos + cargas de
-- hormigón). No escribe nada. Ejecutado y verificado 2026-09-04 (ver
-- memory/pending.md para el resumen de resultados de esa corrida).
--
-- Cómo leer los resultados: cada bloque compara "legado_pre_sept" (cantidad
-- de registros reales en kv_store con fecha < 2026-09-01) contra "migrados"
-- (cuántos de esos tienen su fila espejo en plantas_*, matcheando por
-- `datos_legados ->> 'id'` — el id nativo del legado, preservado tal cual en
-- cada insert de la migración). Cualquier "FALTANTES" > 0 requiere revisar
-- el detalle antes de asumir que es un bug — ver casos ya explicados abajo.
--
-- NO cubre datos posteriores al 01/09/2026: esos son un problema aparte y ya
-- documentado (el sistema legado sigue en uso real en paralelo, escribiendo
-- directo a kv_store, sin sync automático hacia plantas_* — no es un bug de
-- código, es un tema de proceso/adopción, ver memory/pending.md "AUDITORÍA
-- CRÍTICA" y la sesión de Báscula 2026-09-04).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Báscula (plantas_vales) — asfalto + ingreso_arido + egreso_arido
--    Resultado 2026-09-04: 884/884 migrados (382+499+3), 0 faltantes,
--    totales en tn idénticos (diferencia 0.0000 en los 3 tipos).
-- ----------------------------------------------------------------------------
with legado as (
  select 'asfalto' as tipo, v->>'id' as id_legado, (v->>'fecha')::date as fecha
  from kv_store, jsonb_array_elements(value) as v where key = 'vt_vales9'
  union all
  select 'ingreso_arido', v->>'id', (v->>'fecha')::date
  from kv_store, jsonb_array_elements(value) as v where key = 'vt_ingaridos9'
  union all
  select 'egreso_arido', v->>'id', (v->>'fecha')::date
  from kv_store, jsonb_array_elements(value) as v where key = 'vt_egaridos9'
)
select
  l.tipo,
  count(*) filter (where l.fecha < '2026-09-01') as legado_pre_sept,
  count(*) filter (where l.fecha < '2026-09-01' and pv.id is not null) as migrados_pre_sept,
  count(*) filter (where l.fecha < '2026-09-01' and pv.id is null) as faltantes_pre_sept
from legado l
left join plantas_vales pv on pv.datos_legados ->> 'id' = l.id_legado
group by l.tipo
order by l.tipo;

-- ----------------------------------------------------------------------------
-- 2) Pedidos (plantas_pedidos) — Resultado 2026-09-04: 178/179 migrados, el
--    único faltante es `wmcde37` (cantidad="-1", cancelado — sin valor real
--    que migrar, CHECK cantidad_solicitada > 0 lo impide a propósito, mismo
--    caso documentado desde el primer dry-run de la migración).
-- ----------------------------------------------------------------------------
with legado as (
  select v->>'id' as id_legado, (v->>'fecha')::date as fecha
  from kv_store, jsonb_array_elements(value) as v where key = 'vt_p9'
)
select
  count(*) filter (where fecha < '2026-09-01') as legado_pre_sept,
  count(*) filter (where fecha < '2026-09-01' and pp.id is not null) as migrados_pre_sept,
  count(*) filter (where fecha < '2026-09-01' and pp.id is null) as faltantes_pre_sept
from legado l
left join plantas_pedidos pp on pp.datos_legados ->> 'id' = l.id_legado;

-- Detalle de faltantes (esperado: solo wmcde37) — correr si el count de arriba > 0:
-- select l.id_legado, l.fecha, l.estado, l.cantidad_cruda from (
--   select v->>'id' as id_legado, (v->>'fecha')::date as fecha, v->>'estado' as estado, v->>'cantidad' as cantidad_cruda
--   from kv_store, jsonb_array_elements(value) as v where key = 'vt_p9'
-- ) l
-- left join plantas_pedidos pp on pp.datos_legados ->> 'id' = l.id_legado
-- where l.fecha < '2026-09-01' and pp.id is null order by l.fecha;

-- ----------------------------------------------------------------------------
-- 3) Historial de pedidos (plantas_pedidos_historial) — Resultado 2026-09-04:
--    531/533 migrados, los 2 faltantes son los 2 eventos de wmcde37 (mismo
--    pedido excluido arriba, su historial no puede migrar sin el pedido).
-- ----------------------------------------------------------------------------
with legado as (
  select p->>'id' as pedido_id_legado, evento
  from kv_store, jsonb_array_elements(value) as p
  cross join lateral jsonb_array_elements(coalesce(p->'historial', '[]'::jsonb)) as evento
  where key = 'vt_p9'
    and (evento->>'estado') in ('solicitado','confirmado','despachado','postergado','cancelado')
    and (nullif(p->>'fecha','')::date) < '2026-09-01'
)
select
  count(*) as legado_pre_sept,
  count(*) filter (where pph.id is not null) as migrados,
  count(*) filter (where pph.id is null) as faltantes
from legado l
left join plantas_pedidos pp on pp.datos_legados ->> 'id' = l.pedido_id_legado
left join plantas_pedidos_historial pph on pph.pedido_id = pp.id and pph.datos_legados = l.evento;

-- ----------------------------------------------------------------------------
-- 4) Fórmulas (plantas_formulas) — Resultado 2026-09-04: 19/19, 0 faltantes.
-- ----------------------------------------------------------------------------
with legado as (
  select v->>'id' as id_legado from kv_store, jsonb_array_elements(value) as v where key = 'vt_f9'
)
select
  count(*) as formulas_legado,
  count(*) filter (where pf.id is not null) as migradas,
  count(*) filter (where pf.id is null) as faltantes
from legado l
left join plantas_formulas pf on pf.datos_legados ->> 'id' = l.id_legado;

-- ----------------------------------------------------------------------------
-- 5) Stock — movimientos "de un evento" (plantas_stock_movimientos, todo
--    salvo 'relevamiento'). Resultado 2026-09-04: 655/655, 0 faltantes en
--    los 4 tipos (ingreso_aridos, ingreso, egreso_aridos, salida).
-- ----------------------------------------------------------------------------
with legado as (
  select v->>'id' as id_legado, (v->>'fecha')::date as fecha, v->>'tipo' as tipo_legado
  from kv_store, jsonb_array_elements(value) as v where key = 'vt_m9'
)
select
  l.tipo_legado,
  count(*) filter (where l.fecha < '2026-09-01') as legado_pre_sept,
  count(*) filter (where l.fecha < '2026-09-01' and psm.id is not null) as migrados_pre_sept,
  count(*) filter (where l.fecha < '2026-09-01' and psm.id is null) as faltantes_pre_sept
from legado l
left join plantas_stock_movimientos psm on psm.datos_legados ->> 'id' = l.id_legado
where l.tipo_legado <> 'relevamiento'
group by l.tipo_legado
order by l.tipo_legado;

-- ----------------------------------------------------------------------------
-- 6) Stock — 'relevamiento' (snapshot mensual, migrado como DELTA contra el
--    relevamiento anterior del mismo material — no matchea 1:1 por id, es
--    esperado que el primer relevamiento de cada material quede sin delta).
--    Resultado 2026-09-04: 23 relevamientos reales pre-01/09 -> 124 filas
--    'ajuste' migradas (16 materiales x 23 relevamientos, menos los que no
--    cambiaron de valor y el primero de cada material sin base anterior).
-- ----------------------------------------------------------------------------
select count(*) as ajustes_relevamiento_migrados_pre_sept
from plantas_stock_movimientos
where datos_legados ->> 'tipo' = 'relevamiento_delta'
  and fecha_movimiento < '2026-09-01';

-- ----------------------------------------------------------------------------
-- 7) Stock — balance final (plantas_stock vs. kv_store.vt_s9 AHORA MISMO).
--    OJO: esto NO es un chequeo de migración — vt_s9 sigue siendo escrito en
--    vivo por el legado (uso paralelo documentado), así que esta comparación
--    crece con el correr de los días y NO se corrige reconciliando datos
--    viejos. Solo sirve para dimensionar el drift actual entre ambos
--    sistemas. Ver memory/pending.md "AUDITORÍA CRÍTICA" para la decisión
--    pendiente de Federico (cuándo cortar el uso paralelo).
-- ----------------------------------------------------------------------------
select
  pm.nombre,
  round(ps.cantidad_kg / 1000.0, 2) as sistema_nuevo_tn,
  round((kv.value ->> pm.nombre)::numeric / 1000.0, 2) as sistema_viejo_tn_ahora,
  round((ps.cantidad_kg - (kv.value ->> pm.nombre)::numeric) / 1000.0, 2) as diferencia_tn
from plantas_materiales pm
join plantas_stock ps on ps.material_id = pm.id
join kv_store kv on kv.key = 'vt_s9' and kv.value ? pm.nombre
order by abs(ps.cantidad_kg - (kv.value ->> pm.nombre)::numeric) desc;

-- ----------------------------------------------------------------------------
-- 8) Cargas de hormigón (plantas_cargas_hormigon) — OJO con el resultado
--    crudo acá: filtrar SIEMPRE por pf.tipo = 'hormigon' en el legado
--    también, si no aparecen falsos positivos. Resultado 2026-09-04: de los
--    "camiones" con nroRemito+cantidad en pedidos PRE-01/09, TODOS los de
--    hormigón migraron 100%; los que a primera vista parecían faltantes
--    eran 22 camiones de pedidos de ASFALTO (que a propósito NO van a esta
--    tabla, ver comentario de la migración — el detalle de asfalto vive en
--    plantas_vales, ya verificado 100% arriba). Hallazgo colateral, no
--    accionable: esos 22 `nroRemito` de camiones de asfalto NO coinciden con
--    números reales de plantas_vales.numero_vale de ese mismo pedido — el
--    campo parece dato suelto/no confiable del legado para asfalto, no una
--    referencia real a un vale de báscula. No se usa en ningún lado de la
--    UI nueva, no requiere acción.
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
  count(*) filter (where l.fecha < '2026-09-01' and pf.tipo = 'hormigon') as legado_hormigon_pre_sept,
  count(*) filter (where l.fecha < '2026-09-01' and pf.tipo = 'hormigon' and pch.id is not null) as migradas_pre_sept,
  count(*) filter (where l.fecha < '2026-09-01' and pf.tipo = 'hormigon' and pch.id is null) as faltantes_pre_sept
from legado l
left join plantas_pedidos pp on pp.datos_legados ->> 'id' = l.pedido_id_legado
left join plantas_formulas pf on pf.id = pp.formula_id
left join plantas_cargas_hormigon pch on pch.pedido_id = pp.id and pch.datos_legados = l.camion;

-- ----------------------------------------------------------------------------
-- 9) Integridad general — Resultado 2026-09-04: los 4 chequeos en 0.
-- ----------------------------------------------------------------------------
select 'numero_vale duplicado' as chequeo, count(*) as casos from (
  select numero_vale from plantas_vales group by numero_vale having count(*) > 1
) x
union all
select 'pedido id_legado duplicado', count(*) from (
  select datos_legados->>'id' from plantas_pedidos where datos_legados->>'id' is not null group by 1 having count(*) > 1
) x
union all
select 'ingresos huerfanos (vale_id sin vale)', count(*) from plantas_ingresos pi
  where not exists (select 1 from plantas_vales pv where pv.id = pi.vale_id)
union all
select 'vales ingreso_arido sin fila en plantas_ingresos', count(*) from plantas_vales pv
  where pv.tipo_vale = 'ingreso_arido' and not exists (select 1 from plantas_ingresos pi where pi.vale_id = pv.id);
