-- ============================================================================
-- VISTAS PUENTE: Báscula y Stock — plantas_* (real) + kv_store legado (vivo)
--
-- ¡¡¡ BORRADOR PARA REVISIÓN, NO APLICADO !!! (memory/procedimientos.md:
-- reportar y esperar confirmación de Federico antes de correr contra
-- producción — esto crea objetos nuevos de solo lectura, no toca ninguna
-- tabla existente ni ningún dato, pero de todas formas es un cambio de
-- schema y requiere el mismo protocolo).
--
-- OBJETIVO: que Báscula y Stock (historial de movimientos) del sistema
-- nuevo muestren TODOS los movimientos reales — los ya migrados a
-- plantas_vales/plantas_stock_movimientos MÁS los que el sistema legado
-- sigue cargando en paralelo en kv_store — sin duplicar y sin tocar NINGUNA
-- escritura (las RPC `registrar_pesada_bascula`, `registrar_movimiento_manual`,
-- etc. siguen escribiendo únicamente en plantas_*, sin cambios).
--
-- ES UN PUENTE TEMPORAL, no un cambio de arquitectura permanente (ver
-- memory/pending.md): sigue pendiente definir la fecha de corte real en que
-- el sistema nuevo pasa a ser el único que se usa en planta. Mientras tanto,
-- estas vistas evitan que la UI nueva mienta sobre cuántos movimientos hay.
--
-- Por qué VISTA y no TRIGGER de sincronización (evaluado y descartado por
-- ahora, ver la conversación): una vista de solo lectura no puede
-- desincronizarse (recalcula en vivo en cada consulta) y no corre dentro de
-- la transacción de escritura del sistema legado — cero riesgo de romper el
-- guardado de un vale en produccion.vialtec.app por un bug de código
-- nuestro. Limitación conocida y aceptada: las filas "solo legado" no tienen
-- una fila real en plantas_* detrás, así que no sirven para acciones que
-- necesiten una RPC (imprimir vale con acumulado real, corregir, etc.) — la
-- UI las tiene que tratar como SOLO LECTURA (columna `pendiente_migracion`
-- para que el frontend lo sepa).
--
-- security_invoker = true (Postgres 15+, este proyecto corre PG 17.6): la
-- vista respeta el RLS del usuario que consulta, no el del dueño de la
-- vista — importante para cuando P0.2 (RLS fina por rol, memory/pending.md)
-- se implemente sobre plantas_vales/plantas_stock_movimientos, esta vista
-- no debe convertirse en un bypass silencioso de esas reglas futuras.
--
-- 🔴 HALLAZGO REAL descubierto al aplicar esta vista (2026-09-04, no es un
-- problema de la vista en sí, es preexistente de la migración del 1/9):
-- los 500 `ingreso_arido` migrados recibieron numero_vale SINTÉTICO
-- (nextval) en el rango 9994-10493 porque el legado no los numera. El
-- asfalto real del legado seguía en 9993 al momento de migrar, pero SIGUIÓ
-- avanzando en paralelo (hoy va por 10013) — está entrando en el mismo
-- rango que ya "ocupan" los ingresos sintéticos. Por eso las dos ramas
-- legado_asfalto/legado_egreso de abajo comparan por el id nativo del
-- legado (`datos_legados ->> 'id'`), NO por numero_vale como hace la
-- migración original — comparar por numero_vale da falsos positivos acá
-- (un asfalto real nuevo "parece" ya migrado porque un ingreso sintético ya
-- usa ese mismo número). Esto además implica un riesgo real a futuro: el
-- día que se migre de verdad ese asfalto con su numero_vale real (9994 en
-- adelante), va a chocar contra el UNIQUE de numero_vale — hace falta
-- decidir con Federico cómo resolverlo (renumerar los ingresos sintéticos,
-- o asignarle al asfalto real un numero_vale distinto al de báscula) ANTES
-- de encarar esa migración, no es parte de esta vista de solo lectura.
--
-- Verificado antes de escribir esto: `authenticated` (y `anon`) ya tienen
-- GRANT SELECT sobre kv_store (además de INSERT/UPDATE/DELETE — hallazgo
-- colateral de seguridad preexistente del legado, no tocado acá, avisado a
-- Federico aparte) — la vista no necesita ningún permiso nuevo sobre
-- kv_store, solo el GRANT SELECT propio sobre la vista al final de este
-- archivo.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) BÁSCULA — plantas_v_bascula_viva
--
-- Mismo criterio de "ya migrado" que usa migracion_historial_v2.sql (para
-- no duplicar nunca una fila): asfalto y egreso_arido por el id nativo del
-- legado (`datos_legados ->> 'id'` — NO por numero_vale, ver el hallazgo de
-- colisión de numeración más arriba en este archivo), ingreso_arido por
-- (numero_remito + material) contra plantas_ingresos.
--
-- Columnas ya aplanadas (numero_remito_ingreso, cantidad_remito_ingreso,
-- cliente_externo, material) en vez de depender del embed de PostgREST
-- (`plantas_ingresos(...)`, `plantas_pedidos(...)`) que usa hoy
-- bascula.service.js — las filas "solo legado" no tienen una fila real de
-- plantas_ingresos/plantas_pedidos detrás para que el embed funcione, así
-- que se resuelven acá directo. bascula.service.js ya está adaptado (lee
-- esta vista con un select('*') simple, ver src/modules/bascula/services/bascula.service.js).
--
-- Fix de performance 2026-09-04 (memory/pending.md: "canceling statement
-- due to statement timeout" reproducido en vivo con un filtro de fecha
-- amplio — 1.13s medido en EXPLAIN ANALYZE como el rol `authenticated` real,
-- que tiene statement_timeout=8s):
--   - `plantas_pedidos` tiene RLS por fila (subplan correlado contra
--     plantas_usuarios_roles) — el planner a veces elegía un plan que la
--     reevaluaba UNA VEZ POR CADA fila externa en vez de una sola vez.
--     `pp_visible as materialized` fuerza que se compute una sola vez sin
--     importar qué plan elija el optimizador después — bajó 1.13s a 68ms.
--   - Piso de fecha (`(v->>'fecha')::date >= '2026-09-01'`) en las 3 ramas
--     legado: antes de esa fecha está TODO migrado (0 faltantes, auditado
--     en supabase/scripts/auditoria_historico_vs_legado.sql) — no tiene
--     sentido escanear/procesar esos ítems, nunca van a aparecer como
--     "pendiente" igual. Reduce drásticamente el trabajo para cualquier
--     filtro de fecha que incluya histórico (el caso más común).
--   - `plantas_vales` se lee una sola vez (`pv_base as materialized`, antes
--     3 lecturas separadas: una en `migrados`, una por cada anti-join de
--     legado_asfalto/legado_egreso).
-- ----------------------------------------------------------------------------

create or replace view plantas_v_bascula_viva
with (security_invoker = true) as
with obras_legado as (
  -- Reconciliación obra legado -> flota_obras: mismo criterio que
  -- migracion_historial_v2.sql sección 1 (codigo exacto, luego nombre
  -- exacto, luego los 3 overrides manuales ya confirmados en esa
  -- migración: 'o1'->10, 'yjscoq2'->26, 'f4stkay'->2). flota_obras es
  -- SOLO LECTURA acá, igual que en la migración (memory/procedimientos.md).
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
-- pp_visible: plantas_pedidos con su RLS evaluada UNA SOLA VEZ (ver nota de
-- performance arriba) — todo lo que necesite resolver un pedido (obra,
-- cliente_externo, fórmula, o el propio id) lee de acá, nunca de
-- plantas_pedidos directo.
pp_visible as materialized (
  select id, obra_id, cliente_externo, formula_id, datos_legados ->> 'id' as legado_id
  from plantas_pedidos
),
pv_base as materialized (
  select pv.*, pi.material as ing_material, pi.numero_remito as ing_numero_remito, pi.cantidad as ing_cantidad,
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
    true as pendiente_migracion
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
    true as pendiente_migracion
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
    true as pendiente_migracion
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
    -- material: para ingreso_arido la migración NO lo guardó en plantas_vales.material
    -- (columna no incluida en ese insert), vive en plantas_ingresos.material — coalesce
    -- cubre asfalto (null en ambos), egreso (pv.material) e ingreso (pv.ing_material).
    coalesce(pv.material, pv.ing_material) as material,
    pv.temperatura,
    pv.responsable_email,
    null::text as responsable_texto_legado,
    pv.ing_numero_remito as numero_remito_ingreso,
    pv.ing_cantidad as cantidad_remito_ingreso,
    pv.pp_cliente_externo as cliente_externo,
    pv.acumulado_obra_tn,
    false as pendiente_migracion
  from pv_base pv
)
select * from migrados
union all
select * from legado_asfalto
union all
select * from legado_ingreso
union all
select * from legado_egreso;

grant select on plantas_v_bascula_viva to authenticated;

-- 2) STOCK — plantas_v_stock_movimientos_viva
--
-- Mismo criterio. ALCANCE: tipos de movimiento SIMPLES (ingreso/egreso/
-- salida) — 'relevamiento' queda FUERA de esta vista a propósito.
--
-- Columna `material_nombre` ya aplanada (join directo a plantas_materiales)
-- en vez del embed `plantas_materiales(nombre)` que usa hoy stock.service.js
-- — PostgREST arma ese embed a partir de una FK real, que una VIEW no
-- expone; se resuelve acá adentro para las dos ramas (migrados y legado).
--
-- Por qué 'relevamiento' queda afuera: se migra como DELTA contra el
-- relevamiento inmediato anterior del MISMO material (migracion_historial_v2.sql
-- sección 8b, con lag() sobre TODA la cadena cronológica de ese material).
-- Calcular ese delta en vivo exige conocer el último valor real conocido de
-- cada material, que puede venir de un relevamiento YA migrado — mezclar
-- ambas fuentes en un lag() en vivo, correcto en todos los casos borde
-- (primer relevamiento sin base, relevamiento migrado seguido de uno nuevo,
-- etc.), es la parte de mayor riesgo de tener un bug sutil de todo lo
-- evaluado. Como además 'relevamiento' es un evento mensual (no el flujo
-- diario que causó el reporte de Báscula), se deja explícitamente fuera de
-- esta tanda — si aparece uno nuevo en el legado mientras dure el puente,
-- no se va a reflejar acá hasta que se migre a mano o se llegue a la fecha
-- de corte.
-- ----------------------------------------------------------------------------

create or replace view plantas_v_stock_movimientos_viva
with (security_invoker = true) as
with legado_movimientos as (
  select
    md5('stock:' || (m ->> 'id'))::uuid as id,
    pm.id as material_id,
    pm.nombre as material_nombre,
    case m ->> 'tipo'
      when 'ingreso_aridos' then 'ingreso_proveedor'
      when 'ingreso'        then 'ingreso_proveedor'
      when 'egreso_aridos'  then 'egreso_arido'
      when 'salida'         then 'egreso_manual'
    end as tipo,
    case
      when (m ->> 'tipo') in ('ingreso_aridos', 'ingreso')
        then abs(coalesce((m ->> 'cantidadKg')::numeric, (m ->> 'cantidad')::numeric))
      else -abs(coalesce((m ->> 'cantidadKg')::numeric, (m ->> 'cantidad')::numeric))
    end as cantidad_kg,
    coalesce(nullif(m ->> 'proveedor', ''), nullif(m ->> 'motivo', '')) as origen,
    nullif(m ->> 'nroRemito', '') as numero_remito,
    nullif(m ->> 'observaciones', '') as observaciones,
    case
      when nullif(m ->> 'hora', '') is not null
        then ((m ->> 'fecha') || ' ' || (m ->> 'hora'))::timestamp at time zone 'America/Argentina/Buenos_Aires'
      when nullif(m ->> 'fechaHora', '') is not null
        then (m ->> 'fechaHora')::timestamptz
      else (m ->> 'fecha')::date::timestamp at time zone 'America/Argentina/Buenos_Aires'
    end as fecha_movimiento,
    null::text as responsable_email,
    nullif(m ->> 'operador', '') as responsable_texto_legado,
    true as pendiente_migracion
  from kv_store, jsonb_array_elements(value) as m
  join plantas_materiales pm
    on lower(trim(pm.nombre)) = lower(trim(coalesce(m ->> 'insumo', m ->> 'material')))
  where kv_store.key = 'vt_m9'
    and (m ->> 'tipo') <> 'relevamiento'
    and coalesce((m ->> 'cantidadKg')::numeric, (m ->> 'cantidad')::numeric, 0) <> 0
    -- mismo criterio de idempotencia que la migración real: material + evento crudo completo
    and not exists (
      select 1 from plantas_stock_movimientos psm
      where psm.material_id = pm.id and psm.datos_legados = m
    )
),
migrados as (
  select
    psm.id, psm.material_id, pm.nombre as material_nombre, psm.tipo, psm.cantidad_kg, psm.origen,
    psm.numero_remito, psm.observaciones, psm.fecha_movimiento,
    -- Preserva el fallback "operador histórico" que ya mostraba stock.service.js
    -- para movimientos migrados del legado sin responsable_email real
    -- (fix 2026-09-03, "(histórico)" en la UI) — antes leía datos_legados
    -- directo en el JS, ahora viene aplanado acá.
    psm.responsable_email, psm.datos_legados ->> 'operador' as responsable_texto_legado,
    false as pendiente_migracion
  from plantas_stock_movimientos psm
  join plantas_materiales pm on pm.id = psm.material_id
)
select * from migrados
union all
select * from legado_movimientos;

grant select on plantas_v_stock_movimientos_viva to authenticated;


-- ----------------------------------------------------------------------------
-- 3) Verificación sugerida DESPUÉS de aplicar (no antes) — comparar contra
--    los conteos ya auditados en supabase/scripts/auditoria_historico_vs_legado.sql
--    y contra el caso puntual reportado (1-4 sept debería dar 24, no 1):
-- ----------------------------------------------------------------------------
-- select count(*), count(*) filter (where pendiente_migracion) as pendientes
-- from plantas_v_bascula_viva
-- where fecha_pesada >= '2026-09-01T03:00:00Z' and fecha_pesada < '2026-09-05T03:00:00Z';
-- -- esperado: 24 total, 23 pendientes (el mismo resultado que la auditoría manual)
