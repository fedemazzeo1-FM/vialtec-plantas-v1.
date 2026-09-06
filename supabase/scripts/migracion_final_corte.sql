-- ============================================================================
-- MIGRACIÓN FINAL DE CORTE — delta acumulado en el legado desde el 01/09/2026
-- (Paso 4, memory/pending.md — plan de corte definitivo)
--
-- Reutiliza EXACTAMENTE la misma lógica de inserción que
-- migracion_historial_v2.sql (secciones 5-8, ejecutada el 2026-09-01), que
-- ya es idempotente por diseño (cada INSERT trae su propio `not exists`/
-- anti-join contra el id nativo del legado) — no filtra por fecha porque no
-- hace falta: al procesar TODO el array de cada clave de kv_store y saltear
-- lo ya presente, correr este script en el corte captura automáticamente
-- solo el delta real, sin importar cuántos días pasaron desde la última
-- corrida. Por eso es seguro re-ejecutar este mismo script más de una vez
-- si hiciera falta (ej. si el legado sigue vivo unas horas más después del
-- primer dry-run) — no duplica nada.
--
-- Alcance DELIBERADAMENTE excluido de este script (decisión pendiente de
-- Federico, ver memory/pending.md "Paso 4"):
--   - plantas_stock (balance final): la migración original del 01/09 seteó
--     el valor directo desde vt_s9 (snapshot único de bootstrap). Repetir
--     eso ahora SOBRESCRIBIRÍA el ledger real que plantas_stock viene
--     llevando de forma independiente desde el 01/09 (despachos, báscula,
--     manual) — sería destructivo, no aditivo. Hay 1 relevamiento nuevo en
--     el legado desde el 01/09 (2026-09-03) sin reconciliar — no se migra
--     acá, es una decisión de negocio (¿confiar en el ledger nuevo tal
--     cual, o hacer un relevamiento físico fresco el día del corte vía
--     "Stock → Relevamiento mensual", que sí queda auditado como ajuste?).
--
-- Requiere PostgreSQL con permisos de owner (mismo rol que corrió la
-- migración original) — corre como transacción única: `rollback;` al final
-- para dry-run, cambiar a `commit;` para la corrida real el día del corte.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- Staging: pedidos completos del legado (igual que la migración original,
-- sección 5) — recrea `stg_pedidos_legado` y `stg_obras_mapeadas`.
-- ----------------------------------------------------------------------------

create temporary table stg_obras_mapeadas as
select
  o.value ->> 'id' as obra_id_legado,
  trim(o.value ->> 'nombre') as nombre,
  coalesce(fo_cod.id, fo_nom.id,
    case o.value ->> 'id'
      when 'o1' then 10
      when 'yjscoq2' then 26
      when 'f4stkay' then 2
      else null
    end::bigint) as flota_obra_id
from kv_store,
  lateral jsonb_array_elements(kv_store.value -> 'obras') o(value)
  left join flota_obras fo_cod on fo_cod.codigo is not null
    and upper(trim(fo_cod.codigo)) = upper(nullif(trim(o.value ->> 'codigo'), ''))
  left join flota_obras fo_nom on upper(trim(fo_nom.nombre)) = upper(trim(o.value ->> 'nombre'))
where kv_store.key = 'vt_maestros9';

create temporary table stg_pedidos_legado as
select
  p                     as raw,
  p ->> 'id'             as id_legado,
  p ->> 'obraId'         as obra_id_legado,
  p ->> 'formulaId'      as formula_id_legado
from kv_store, jsonb_array_elements(value) as p
where key = 'vt_p9';

-- ----------------------------------------------------------------------------
-- 1) plantas_pedidos + plantas_pedidos_historial (delta)
-- ----------------------------------------------------------------------------

insert into plantas_pedidos (
  obra_id, formula_id, tipo, cantidad_solicitada, cantidad_despachada,
  fecha_programada, estado, tipo_pedido, cliente_externo, encargado,
  observaciones, ubicacion, nro_remito_global, nro_vale_global,
  motivo, motivo_en, archivado, created_at, datos_legados
)
select
  som.flota_obra_id,
  pf.id,
  pf.tipo,
  nullif(sp.raw ->> 'cantidad', '')::numeric,
  nullif(sp.raw ->> 'cantidadReal', '')::numeric,
  nullif(sp.raw ->> 'fecha', '')::date,
  sp.raw ->> 'estado',
  case when nullif(sp.raw ->> 'tipoPedido', '') = 'venta' then 'venta' else 'obra' end,
  nullif(sp.raw ->> 'clienteExterno', ''),
  nullif(trim(sp.raw ->> 'encargado'), ''),
  nullif(sp.raw ->> 'notas', ''),
  nullif(sp.raw ->> 'ubicacion', ''),
  nullif(sp.raw ->> 'nroRemito', ''),
  nullif(sp.raw ->> 'nroVale', ''),
  nullif(sp.raw ->> 'motivo', ''),
  nullif(sp.raw ->> 'motivoEn', '')::timestamptz,
  false,
  coalesce(nullif(sp.raw ->> 'creadoEn', '')::timestamptz, now()),
  sp.raw
from stg_pedidos_legado sp
left join stg_obras_mapeadas som on som.obra_id_legado = sp.obra_id_legado
left join plantas_formulas pf on pf.datos_legados ->> 'id' = sp.formula_id_legado
where pf.id is not null
and coalesce(nullif(sp.raw ->> 'cantidad', '')::numeric, 1) > 0
and not exists (select 1 from plantas_pedidos pp where pp.datos_legados ->> 'id' = sp.id_legado);

insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_legado, motivo, datos_legados)
select
  pp.id,
  evento ->> 'estado',
  nullif(evento ->> 'fecha', '')::timestamptz,
  nullif(evento ->> 'usuario', ''),
  nullif(evento ->> 'motivo', ''),
  evento
from stg_pedidos_legado sp
join plantas_pedidos pp on pp.datos_legados ->> 'id' = sp.id_legado
cross join lateral jsonb_array_elements(coalesce(sp.raw -> 'historial', '[]'::jsonb)) as evento
where (evento ->> 'estado') in ('solicitado','confirmado','despachado','postergado','cancelado')
and not exists (
  select 1 from plantas_pedidos_historial pph
  where pph.pedido_id = pp.id and pph.datos_legados = evento
);

-- ----------------------------------------------------------------------------
-- 2) plantas_cargas_hormigon (delta)
-- ----------------------------------------------------------------------------

insert into plantas_cargas_hormigon (pedido_id, obra_id, numero_remito, volumen_m3, patente_mixer, datos_legados)
select
  pp.id,
  pp.obra_id,
  nullif(camion ->> 'nroRemito', ''),
  (camion ->> 'cantidad')::numeric,
  nullif(camion ->> 'patente', ''),
  camion
from stg_pedidos_legado sp
join plantas_pedidos pp on pp.datos_legados ->> 'id' = sp.id_legado
join plantas_formulas pf on pf.id = pp.formula_id
cross join lateral jsonb_array_elements(coalesce(sp.raw -> 'camiones', '[]'::jsonb)) as camion
where pf.tipo = 'hormigon'
  and (camion ->> 'nroRemito') is not null and camion ->> 'nroRemito' <> ''
  and (camion ->> 'cantidad') is not null
  and not exists (
    select 1 from plantas_cargas_hormigon pch
    where pch.pedido_id = pp.id and pch.datos_legados = camion
  );

-- ----------------------------------------------------------------------------
-- 3) plantas_vales — asfalto + egreso_arido (numero real preservado) +
--    ingreso_arido (numero sintético) + plantas_ingresos (delta).
--
-- IMPORTANTE: correr primero el bloque 4b de
-- supabase/scripts/auditoria_delta_desde_01_09.sql antes de la corrida REAL
-- (no el dry-run) — si da alguna fila, HAY que resolver la colisión de
-- numero_vale a mano antes de seguir. El dry-run de 2026-09-06 dio 0 filas.
-- ----------------------------------------------------------------------------

insert into plantas_vales (
  numero_vale, tipo_vale, pedido_id, obra_id, patente, chofer,
  peso_bruto, tara, peso_neto, unidad, fecha_pesada, temperatura, datos_legados
)
overriding system value
select
  (v ->> 'numero')::bigint,
  'asfalto',
  pp.id,
  coalesce(pp.obra_id, som.flota_obra_id),
  nullif(v ->> 'patente', ''),
  nullif(v ->> 'chofer', ''),
  (v ->> 'pesoBruto')::numeric,
  (v ->> 'tara')::numeric,
  (v ->> 'pesoNeto')::numeric,
  'tn',
  ((v ->> 'fecha') || ' ' || coalesce(nullif(v ->> 'hora', ''), '00:00'))::timestamp
    at time zone 'America/Argentina/Buenos_Aires',
  nullif(v ->> 'temperatura', '')::numeric,
  v
from kv_store, jsonb_array_elements(value) as v
left join plantas_pedidos pp on pp.datos_legados ->> 'id' = v ->> 'pedidoId'
left join stg_obras_mapeadas som on som.nombre = trim(v ->> 'obra')
where key = 'vt_vales9'
and not exists (select 1 from plantas_vales pv where pv.numero_vale = (v ->> 'numero')::bigint);

insert into plantas_vales (
  numero_vale, tipo_vale, obra_id, patente, chofer,
  peso_bruto, tara, peso_neto, unidad, fecha_pesada, material, datos_legados
)
overriding system value
select
  (e ->> 'numero')::bigint,
  'egreso_arido',
  som.flota_obra_id,
  nullif(e ->> 'patente', ''),
  nullif(e ->> 'chofer', ''),
  (e ->> 'pesoBruto')::numeric,
  (e ->> 'tara')::numeric,
  (e ->> 'pesoNeto')::numeric,
  'tn',
  ((e ->> 'fecha') || ' ' || coalesce(nullif(e ->> 'hora', ''), '00:00'))::timestamp
    at time zone 'America/Argentina/Buenos_Aires',
  nullif(e ->> 'material', ''),
  e
from kv_store, jsonb_array_elements(value) as e
left join stg_obras_mapeadas som on som.nombre = trim(e ->> 'destino')
where key = 'vt_egaridos9'
and not exists (select 1 from plantas_vales pv where pv.numero_vale = (e ->> 'numero')::bigint);

-- Sincroniza la secuencia al máximo real recién insertado (asfalto +
-- egreso) ANTES de que ingreso_arido reparta números nuevos — mismo motivo
-- que la migración original: evita que nextval() choque contra un número
-- real que se acaba de insertar arriba. El filtro `< 90000000` excluye el
-- bloque sintético (90000001-90000500, migración de renumeración
-- 2026-09-06) para no arrastrar la secuencia hasta ahí por error.
select setval(
  pg_get_serial_sequence('plantas_vales', 'numero_vale'),
  (select max(numero_vale) from plantas_vales where numero_vale < 90000000),
  true
);

create temporary table stg_ingaridos_legado as
select i as raw
from kv_store, jsonb_array_elements(value) as i
where key = 'vt_ingaridos9';

with insertados_vales as (
  insert into plantas_vales (numero_vale, tipo_vale, patente, peso_bruto, tara, peso_neto, unidad, fecha_pesada, datos_legados)
  overriding system value
  select
    nextval(pg_get_serial_sequence('plantas_vales', 'numero_vale')),
    'ingreso_arido',
    nullif(sil.raw ->> 'patente', ''),
    (sil.raw ->> 'pesoBruto')::numeric,
    (sil.raw ->> 'tara')::numeric,
    (sil.raw ->> 'pesoNeto')::numeric,
    'tn',
    ((sil.raw ->> 'fecha') || ' ' || coalesce(nullif(sil.raw ->> 'hora', ''), '00:00'))::timestamp
      at time zone 'America/Argentina/Buenos_Aires',
    sil.raw
  from stg_ingaridos_legado sil
  where not exists (
    select 1 from plantas_ingresos pi
    where pi.numero_remito = nullif(sil.raw ->> 'remito', '')
      and pi.material = trim(sil.raw ->> 'material')
  )
  returning id, datos_legados
)
insert into plantas_ingresos (material, proveedor, numero_remito, cantidad, unidad, origen, vale_id, fecha_ingreso, observaciones)
select
  trim(iv.datos_legados ->> 'material'),
  trim(iv.datos_legados ->> 'proveedor'),
  nullif(iv.datos_legados ->> 'remito', ''),
  coalesce((iv.datos_legados ->> 'cantidadRemito')::numeric, (iv.datos_legados ->> 'pesoNeto')::numeric),
  'tn',
  'manual',
  iv.id,
  ((iv.datos_legados ->> 'fecha') || ' ' || coalesce(nullif(iv.datos_legados ->> 'hora', ''), '00:00'))::timestamp
    at time zone 'America/Argentina/Buenos_Aires',
  nullif(iv.datos_legados ->> 'observaciones', '')
from insertados_vales iv;

-- Ingreso de áridos vía plantas_ingresos también mueve stock (mismo criterio
-- que registrar_pesada_bascula() en vivo — cantidad DECLARADA en el remito,
-- no peso neto, memory/business-rules.md). La migración original del 01/09
-- lo hacía en su sección 8 junto con vt_m9; acá se separa porque
-- plantas_aplicar_movimiento_stock ya well audita esto solo — se deja
-- pendiente de decisión (ver nota de alcance al inicio del archivo): correr
-- esto commitearía cambios a plantas_stock, que es justo lo que se excluye
-- a propósito de este script por ahora.

-- ----------------------------------------------------------------------------
-- 4) plantas_stock_movimientos — delta desde vt_m9 (excluye 'relevamiento',
--    ver nota de alcance al inicio del archivo).
-- ----------------------------------------------------------------------------

insert into plantas_stock_movimientos (material_id, tipo, cantidad_kg, origen, numero_remito, observaciones, fecha_movimiento, responsable_email, datos_legados)
select
  pm.id,
  case m.value ->> 'tipo'
    when 'ingreso_aridos' then 'ingreso_proveedor'
    when 'ingreso' then 'ingreso_proveedor'
    when 'egreso_aridos' then 'egreso_arido'
    when 'salida' then 'egreso_manual'
  end,
  case
    when (m.value ->> 'tipo') = any (array['ingreso_aridos', 'ingreso']) then abs(coalesce((m.value ->> 'cantidadKg')::numeric, (m.value ->> 'cantidad')::numeric))
    else -abs(coalesce((m.value ->> 'cantidadKg')::numeric, (m.value ->> 'cantidad')::numeric))
  end,
  coalesce(nullif(m.value ->> 'proveedor', ''), nullif(m.value ->> 'motivo', '')),
  nullif(m.value ->> 'nroRemito', ''),
  nullif(m.value ->> 'observaciones', ''),
  case
    when nullif(m.value ->> 'hora', '') is not null then (((m.value ->> 'fecha') || ' ' || (m.value ->> 'hora'))::timestamp) at time zone 'America/Argentina/Buenos_Aires'
    when nullif(m.value ->> 'fechaHora', '') is not null then (m.value ->> 'fechaHora')::timestamptz
    else ((m.value ->> 'fecha')::date::timestamp) at time zone 'America/Argentina/Buenos_Aires'
  end,
  null,
  m.value
from kv_store,
  lateral jsonb_array_elements(kv_store.value) m(value)
  join plantas_materiales pm on lower(trim(pm.nombre)) = lower(trim(coalesce(m.value ->> 'insumo', m.value ->> 'material')))
where kv_store.key = 'vt_m9'
  and (m.value ->> 'tipo') <> 'relevamiento'
  and coalesce((m.value ->> 'cantidadKg')::numeric, (m.value ->> 'cantidad')::numeric, 0) <> 0
  and not exists (
    select 1 from plantas_stock_movimientos psm
    where psm.material_id = pm.id and psm.datos_legados = m.value
  );

-- ----------------------------------------------------------------------------
-- 5) Chequeos de cierre — correr y revisar ANTES de cambiar rollback por
--    commit el día del corte real.
-- ----------------------------------------------------------------------------
select
  (select count(*) from plantas_pedidos) as total_pedidos,
  (select count(*) from plantas_pedidos_historial) as total_historial,
  (select count(*) from plantas_cargas_hormigon) as total_cargas_hormigon,
  (select count(*) from plantas_vales) as total_vales,
  (select count(*) from plantas_ingresos) as total_ingresos,
  (select count(*) from plantas_stock_movimientos) as total_stock_movimientos,
  (select numero_vale from plantas_vales where numero_vale = (select max(numero_vale) from plantas_vales where numero_vale < 90000000)) as max_vale_real,
  (select last_value from plantas_vales_numero_vale_seq) as secuencia_actual;

-- Integridad (deben dar 0):
select 'numero_vale duplicado' as chequeo, count(*) as casos from (
  select numero_vale from plantas_vales group by numero_vale having count(*) > 1
) x
union all
select 'pedido id_legado duplicado', count(*) from (
  select datos_legados->>'id' from plantas_pedidos where datos_legados->>'id' is not null group by 1 having count(*) > 1
) x
union all
select 'ingresos huerfanos (vale_id sin vale)', count(*) from plantas_ingresos pi
  where not exists (select 1 from plantas_vales pv where pv.id = pi.vale_id);

-- DRY-RUN: rollback. Para la corrida real el día del corte, cambiar por
-- `commit;` recién después de confirmar con Federico que los chequeos de
-- arriba dieron lo esperado.
rollback;
