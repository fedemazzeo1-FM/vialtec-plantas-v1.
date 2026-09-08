-- ============================================================================
-- Migración 33: plantas_v_bascula_viva suma la columna `proveedor`.
-- APLICADA en producción 2026-09-08 (pedido de Federico: "báscula también,
-- sumale columna de proveedor"). Solo lectura, no toca ninguna fila —
-- separada de la migración 34 (que sí corrige datos) porque esta se pudo
-- aplicar directo mientras que la 34 quedó bloqueada por el clasificador de
-- permisos de Claude Code al combinar UPDATE/INSERT en la misma llamada.
--
-- Mismo origen que numero_remito_ingreso (`plantas_ingresos.proveedor`, vía
-- `pi` en `pv_base`) — null para asfalto/egreso_arido/filas legado (no
-- aplica, un ingreso de áridos es el único tipo con proveedor real).
-- ============================================================================

create or replace view plantas_v_bascula_viva
with (security_invoker = true) as
with obras_legado as (
  select
    o ->> 'id' as obra_id_legado,
    trim(o ->> 'nombre') as nombre_legado,
    coalesce(
      fo_cod.id,
      fo_nom.id,
      case o ->> 'id'
        when 'o1' then 10
        when 'yjscoq2' then 26
        when 'f4stkay' then 2
      end
    ) as flota_obra_id
  from kv_store, jsonb_array_elements(value -> 'obras') as o
  left join flota_obras fo_cod
    on fo_cod.codigo is not null and upper(trim(fo_cod.codigo)) = upper(nullif(trim(o ->> 'codigo'), ''))
  left join flota_obras fo_nom
    on upper(trim(fo_nom.nombre)) = upper(trim(o ->> 'nombre'))
  where kv_store.key = 'vt_maestros9'
),
pp_visible as materialized (
  select id, obra_id, cliente_externo, formula_id, datos_legados ->> 'id' as legado_id
  from plantas_pedidos
),
pv_base as materialized (
  select pv.*, pi.material as ing_material, pi.numero_remito as ing_numero_remito, pi.cantidad as ing_cantidad,
         pi.proveedor as ing_proveedor,
         ppv.cliente_externo as pp_cliente_externo
  from plantas_vales pv
  left join plantas_ingresos pi on pi.vale_id = pv.id
  left join pp_visible ppv on ppv.id = pv.pedido_id
),
legado_asfalto as (
  select
    md5('bascula:asfalto:' || (v ->> 'id'))::uuid as id,
    (v ->> 'numero')::bigint as numero_vale,
    'asfalto'::text as tipo_vale,
    pp.id as pedido_id,
    coalesce(pp.obra_id, ol.flota_obra_id) as obra_id,
    nullif(v ->> 'patente', '') as patente,
    nullif(v ->> 'chofer', '') as chofer,
    (v ->> 'pesoBruto')::numeric as peso_bruto,
    (v ->> 'tara')::numeric as tara,
    (v ->> 'pesoNeto')::numeric as peso_neto,
    'tn'::text as unidad,
    ((v ->> 'fecha') || ' ' || coalesce(nullif(v ->> 'hora', ''), '00:00'))::timestamp
      at time zone 'America/Argentina/Buenos_Aires' as fecha_pesada,
    null::text as material,
    nullif(v ->> 'temperatura', '')::numeric as temperatura,
    null::text as responsable_email,
    nullif(v ->> 'operador', '') as responsable_texto_legado,
    null::text as numero_remito_ingreso,
    null::numeric as cantidad_remito_ingreso,
    pp.cliente_externo as cliente_externo,
    null::numeric as acumulado_obra_tn,
    true as pendiente_migracion,
    false as anulado,
    null::text as motivo_anulacion,
    null::text as proveedor
  from kv_store, jsonb_array_elements(value) as v
  left join pp_visible pp on pp.legado_id = v ->> 'pedidoId'
  left join obras_legado ol on ol.nombre_legado = trim(v ->> 'obra')
  where kv_store.key = 'vt_vales9'
    and (v ->> 'fecha')::date >= '2026-09-01'
    and not exists (select 1 from pv_base pv where pv.datos_legados ->> 'id' = v ->> 'id')
),
legado_ingreso as (
  select
    md5('bascula:ingreso:' || (v ->> 'id'))::uuid as id,
    null::bigint as numero_vale,
    'ingreso_arido'::text as tipo_vale,
    null::uuid as pedido_id,
    null::bigint as obra_id,
    nullif(v ->> 'patente', '') as patente,
    null::text as chofer,
    (v ->> 'pesoBruto')::numeric as peso_bruto,
    (v ->> 'tara')::numeric as tara,
    (v ->> 'pesoNeto')::numeric as peso_neto,
    'tn'::text as unidad,
    ((v ->> 'fecha') || ' ' || coalesce(nullif(v ->> 'hora', ''), '00:00'))::timestamp
      at time zone 'America/Argentina/Buenos_Aires' as fecha_pesada,
    trim(v ->> 'material') as material,
    null::numeric as temperatura,
    null::text as responsable_email,
    nullif(v ->> 'responsable', '') as responsable_texto_legado,
    nullif(v ->> 'remito', '') as numero_remito_ingreso,
    (v ->> 'cantidadRemito')::numeric as cantidad_remito_ingreso,
    null::text as cliente_externo,
    null::numeric as acumulado_obra_tn,
    true as pendiente_migracion,
    false as anulado,
    null::text as motivo_anulacion,
    nullif(v ->> 'proveedor', '') as proveedor
  from kv_store, jsonb_array_elements(value) as v
  where kv_store.key = 'vt_ingaridos9'
    and (v ->> 'fecha')::date >= '2026-09-01'
    and not exists (
      select 1 from plantas_ingresos pi
      where pi.numero_remito = nullif(v ->> 'remito', '') and pi.material = trim(v ->> 'material')
    )
),
legado_egreso as (
  select
    md5('bascula:egreso:' || (v ->> 'id'))::uuid as id,
    (v ->> 'numero')::bigint as numero_vale,
    'egreso_arido'::text as tipo_vale,
    null::uuid as pedido_id,
    ol.flota_obra_id as obra_id,
    nullif(v ->> 'patente', '') as patente,
    nullif(v ->> 'chofer', '') as chofer,
    (v ->> 'pesoBruto')::numeric as peso_bruto,
    (v ->> 'tara')::numeric as tara,
    (v ->> 'pesoNeto')::numeric as peso_neto,
    'tn'::text as unidad,
    ((v ->> 'fecha') || ' ' || coalesce(nullif(v ->> 'hora', ''), '00:00'))::timestamp
      at time zone 'America/Argentina/Buenos_Aires' as fecha_pesada,
    nullif(v ->> 'material', '') as material,
    null::numeric as temperatura,
    null::text as responsable_email,
    nullif(v ->> 'responsable', '') as responsable_texto_legado,
    null::text as numero_remito_ingreso,
    null::numeric as cantidad_remito_ingreso,
    null::text as cliente_externo,
    null::numeric as acumulado_obra_tn,
    true as pendiente_migracion,
    false as anulado,
    null::text as motivo_anulacion,
    null::text as proveedor
  from kv_store, jsonb_array_elements(value) as v
  left join obras_legado ol on ol.nombre_legado = trim(v ->> 'destino')
  where kv_store.key = 'vt_egaridos9'
    and (v ->> 'fecha')::date >= '2026-09-01'
    and not exists (select 1 from pv_base pv where pv.datos_legados ->> 'id' = v ->> 'id')
),
migrados as (
  select
    pv.id,
    pv.numero_vale,
    pv.tipo_vale,
    pv.pedido_id,
    pv.obra_id,
    pv.patente,
    pv.chofer,
    pv.peso_bruto,
    pv.tara,
    pv.peso_neto,
    pv.unidad,
    pv.fecha_pesada,
    coalesce(pv.material, pv.ing_material) as material,
    pv.temperatura,
    pv.responsable_email,
    null::text as responsable_texto_legado,
    pv.ing_numero_remito as numero_remito_ingreso,
    pv.ing_cantidad as cantidad_remito_ingreso,
    pv.pp_cliente_externo as cliente_externo,
    pv.acumulado_obra_tn,
    false as pendiente_migracion,
    pv.anulado,
    pv.motivo_anulacion,
    pv.ing_proveedor as proveedor
  from pv_base pv
),
combinado as (
  select * from migrados
  union all
  select * from legado_asfalto
  union all
  select * from legado_ingreso
  union all
  select * from legado_egreso
)
select
  id, numero_vale, tipo_vale, pedido_id, obra_id, patente, chofer,
  peso_bruto, tara, peso_neto, unidad, fecha_pesada, material, temperatura,
  responsable_email, responsable_texto_legado, numero_remito_ingreso,
  cantidad_remito_ingreso, cliente_externo, acumulado_obra_tn, pendiente_migracion,
  case
    when tipo_vale = 'asfalto' then
      sum(peso_neto) filter (where tipo_vale = 'asfalto' and not anulado) over (
        partition by coalesce(pedido_id::text, obra_id::text, 'sin-obra'), date_trunc('day', fecha_pesada at time zone 'America/Argentina/Buenos_Aires')
        order by fecha_pesada
      )
    else null::numeric
  end as acumulado_dia_tn,
  anulado,
  motivo_anulacion,
  proveedor
from combinado c;

grant select on plantas_v_bascula_viva to authenticated;
