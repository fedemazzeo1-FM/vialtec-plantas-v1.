-- ============================================================================
-- BORRADOR — Migración de datos: historial legado -> plantas_pedidos /
-- plantas_pedidos_historial / plantas_vales
--
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- ¡¡¡ ESTO ES UN BORRADOR, NO UN SCRIPT LISTO PARA CORRER !!!
-- No está numerado junto a supabase/migrations/*.sql a propósito: no es
-- schema, es carga de datos, y no debe ejecutarse como parte de ningún
-- pipeline de migraciones automático. Corre a mano, revisado paso a paso,
-- con Federico presente (memory/procedimientos.md — migración de historial,
-- el caso donde ese protocolo aplica con más fuerza).
--
-- Requisitos antes de poder correr esto en serio (memory/pending.md, sigue
-- sin resolver "de dónde salen los blobs legados exactos"):
--   - Confirmar de dónde se extraen vt_usuarios9 / vt_bak_YYYY-MM-DD /
--     vt_vale_seq9 y en qué formato quedan disponibles acá (export NDJSON,
--     tabla intermedia ya cargada, etc.).
--   - Al menos una muestra real de un pedido y un vale para validar que la
--     estructura de "Logica sis. plantas v1.rtf" §2.2/§2.4 coincide con los
--     datos reales (nombres de campo, tipos, nulos).
--   - Confirmar contra qué campo del legado se hace el lookup de
--     plantas_formulas (el pedido legado trae formulaId, pero esa FK
--     apuntaba al scaffold huérfano que se descartó — hoy este borrador
--     asume un lookup por nombre de fórmula que TODAVÍA no está confirmado,
--     ver el TODO en el paso 2).
--
-- Depende de que la migración 06_ajustes_pedidos_vales_historial.sql (y
-- 01/02/04/05 antes que ella) ya estén aplicadas.
--
-- Este script asume que el legado ya fue volcado en dos tablas de staging,
-- una fila por documento legado, con el JSON crudo completo en `raw jsonb`:
--   staging_legado_pedidos(raw jsonb)
--   staging_legado_vales(raw jsonb)
-- Si el volcado real llega de otra forma (CSV, API, script externo), solo
-- hay que adaptar el paso 0 — el resto no cambia.
--
-- Corre dentro de una transacción con ROLLBACK explícito al final: por
-- diseño, la primera vez que se ejecute este archivo NO debe persistir nada.
-- El COMMIT se hace a mano, después de revisar los chequeos del paso 5.
-- ============================================================================

begin;

-- Zona horaria fija para interpretar fecha+hora del legado (decisión
-- confirmada por Federico). Es SET LOCAL: vale solo para esta transacción,
-- no toca la configuración global de la instancia compartida con flota.
set local timezone to 'America/Argentina/Buenos_Aires';

-- ----------------------------------------------------------------------------
-- 0) Staging (placeholder — reemplazar por la carga real del legado)
-- ----------------------------------------------------------------------------
create temporary table if not exists staging_legado_pedidos (raw jsonb) on commit drop;
create temporary table if not exists staging_legado_vales   (raw jsonb) on commit drop;

-- TODO: carga real, por ejemplo:
--   \copy staging_legado_pedidos (raw) from 'pedidos_legado.ndjson'
--   \copy staging_legado_vales   (raw) from 'vales_legado.ndjson'
-- o vía un insert generado por un script externo que lea los vt_bak_* reales.

-- ----------------------------------------------------------------------------
-- 1) Reconciliación de obras contra flota_obras (por nombre, normalizado)
--    Ver §1 de la propuesta de mapeo. Reporte de no-matches al final del
--    script (paso 5), no bloquea la carga.
-- ----------------------------------------------------------------------------
create temporary table if not exists staging_obras_reconciliadas on commit drop as
select
  raw ->> 'id'                as pedido_id_legado,
  trim(raw ->> 'obra')        as obra_nombre_legado,
  fo.id                       as obra_id
from staging_legado_pedidos sp
left join flota_obras fo
  on upper(trim(fo.nombre)) = upper(trim(sp.raw ->> 'obra'));

-- ----------------------------------------------------------------------------
-- 2) plantas_pedidos
-- ----------------------------------------------------------------------------
insert into plantas_pedidos (
  obra_id, formula_id, tipo, cantidad_solicitada, cantidad_despachada,
  fecha_programada, estado, tipo_pedido, cliente_externo, encargado,
  observaciones, nro_remito_global, nro_vale_global, motivo, motivo_en,
  archivado, created_at, datos_legados
)
select
  reco.obra_id,
  pf.id,                                                    -- formula_id: lookup por nombre contra plantas_formulas ya migradas
  pf.tipo,                                                  -- asfalto/hormigon, inferido de la fórmula (no viene directo en el pedido legado)
  nullif(raw ->> 'cantidad', '')::numeric,
  nullif(raw ->> 'cantidadReal', '')::numeric,
  nullif(raw ->> 'fecha', '')::date,
  case when (raw ->> 'estado') in ('solicitado','confirmado','despachado','postergado','cancelado')
       then raw ->> 'estado'
       else null end,                                        -- estado fuera de catálogo -> null, cae en la cola de revisión (paso 5)
  case when raw ->> 'tipoPedido' = 'venta' then 'venta' else 'obra' end,
  nullif(raw ->> 'clienteExterno', ''),
  nullif(trim(raw ->> 'encargado'), ''),
  nullif(raw ->> 'notas', ''),
  nullif(raw ->> 'nroRemito', ''),
  nullif(raw ->> 'nroVale', ''),
  nullif(raw ->> 'motivo', ''),
  nullif(raw ->> 'motivoEn', '')::timestamptz,
  coalesce((raw ->> 'archivado')::boolean, false),
  coalesce(nullif(raw ->> 'creadoEn', '')::timestamptz, now()),
  raw
from staging_legado_pedidos sp
join staging_obras_reconciliadas reco on reco.pedido_id_legado = sp.raw ->> 'id'
-- TODO: confirmar el campo real de match de fórmula. El pedido legado trae
-- `formulaId`, pero es FK al scaffold huérfano descartado — por ahora este
-- borrador asume que el legado también trae (o se puede derivar) un nombre
-- de fórmula comparable contra plantas_formulas.nombre. Ajustar el join de
-- abajo en cuanto se confirme.
left join plantas_formulas pf
  on upper(trim(pf.nombre)) = upper(trim(sp.raw ->> 'formulaNombre'))
where pf.id is not null                                      -- sin fórmula matcheada, no se inserta (ver cola de revisión, paso 5)
on conflict do nothing;                                      -- idempotencia vía el índice único sobre datos_legados->>'id' (migración 06)

-- ----------------------------------------------------------------------------
-- 3) plantas_pedidos_historial (unnest del array historial)
-- ----------------------------------------------------------------------------
insert into plantas_pedidos_historial (
  pedido_id, estado, fecha_evento, usuario_legado, motivo, datos_legados
)
select
  pp.id,
  evento ->> 'estado',
  nullif(evento ->> 'fecha', '')::timestamptz,
  nullif(evento ->> 'usuario', ''),
  nullif(evento ->> 'motivo', ''),
  evento
from staging_legado_pedidos sp
join plantas_pedidos pp on pp.datos_legados ->> 'id' = sp.raw ->> 'id'
cross join lateral jsonb_array_elements(coalesce(sp.raw -> 'historial', '[]'::jsonb)) as evento;

-- TODO fecha_programada_anterior / fecha_programada_nueva: requiere una
-- segunda pasada con lag()/lead() sobre esta misma tabla, ordenada por
-- (pedido_id, fecha_evento), solo para filas estado='postergado'. Se deja
-- afuera de este borrador hasta confirmar el supuesto contra un dato real
-- (pregunta abierta en la propuesta de mapeo).

-- ----------------------------------------------------------------------------
-- 4) plantas_vales — preserva numero_vale exacto (OVERRIDING SYSTEM VALUE)
--    Solo asfalto: la colección legada "vales" es exclusivamente pesaje de
--    asfalto (memory/business-rules.md — la báscula legada no pesa
--    hormigón). Los "ingresos de áridos" del legado (colección separada,
--    campos material/remito/proveedor/cantidadRemito) van a plantas_ingresos,
--    NO a plantas_vales — no están en el alcance de este script.
-- ----------------------------------------------------------------------------
insert into plantas_vales (
  numero_vale, tipo_vale, pedido_id, obra_id, patente, chofer,
  peso_bruto, tara, peso_neto, unidad, fecha_pesada, datos_legados
)
overriding system value
select
  (sv.raw ->> 'numero')::bigint,
  'asfalto',
  pp.id,                                                     -- null si no matchea ningún pedido migrado (vale sin pedido / despacho de emergencia)
  fo.id,                                                      -- null si obra/cliente no matchea flota_obras (típico en ventas externas)
  nullif(sv.raw ->> 'patente', ''),
  nullif(sv.raw ->> 'chofer', ''),
  (sv.raw ->> 'pesoBruto')::numeric,
  (sv.raw ->> 'tara')::numeric,
  (sv.raw ->> 'pesoNeto')::numeric,
  'tn',
  ((sv.raw ->> 'fecha') || ' ' || coalesce(sv.raw ->> 'hora', '00:00'))::timestamp
    at time zone 'America/Argentina/Buenos_Aires',
  sv.raw
from staging_legado_vales sv
left join plantas_pedidos pp on pp.datos_legados ->> 'id' = sv.raw ->> 'pedidoId'
left join flota_obras fo
  on upper(trim(fo.nombre)) = upper(trim(sv.raw ->> 'obra'))
where not exists (
  select 1 from plantas_vales v where v.numero_vale = (sv.raw ->> 'numero')::bigint
)
order by (sv.raw ->> 'numero')::bigint asc;

-- Resincronizar la secuencia de identity para que los próximos vales nuevos
-- (creados por la app, sin numero_vale explícito) sigan desde el máximo
-- real migrado y no colisionen con 9579:
select setval(
  pg_get_serial_sequence('plantas_vales', 'numero_vale'),
  (select max(numero_vale) from plantas_vales)
);

-- ----------------------------------------------------------------------------
-- 5) Chequeos de cierre — correr y revisar ANTES de cambiar rollback por commit
-- ----------------------------------------------------------------------------

-- 5a) Pedidos legados que no se insertaron (sin fórmula matcheada, fecha/
--     estado inválido, etc.):
--   select sp.raw ->> 'id' as id_legado, sp.raw
--   from staging_legado_pedidos sp
--   where not exists (
--     select 1 from plantas_pedidos pp where pp.datos_legados ->> 'id' = sp.raw ->> 'id'
--   );

-- 5b) Obras del legado sin match en flota_obras:
--   select distinct obra_nombre_legado
--   from staging_obras_reconciliadas
--   where obra_id is null and obra_nombre_legado is not null and obra_nombre_legado <> '';

-- 5c) Vales donde peso_neto no cuadra con bruto - tara (el constraint de la
--     tabla lo va a rechazar igual, pero conviene verlo antes de que el
--     insert falle a mitad de camino):
--   select raw
--   from staging_legado_vales
--   where round(((raw->>'pesoBruto')::numeric - (raw->>'tara')::numeric), 2)
--         <> round((raw->>'pesoNeto')::numeric, 2);

-- 5d) Vales con numero < 9579 (no deberían existir según business-rules.md;
--     si aparecen, frenar y reportar a Federico, no renumerar ni truncar):
--   select raw ->> 'numero' from staging_legado_vales where (raw ->> 'numero')::bigint < 9579;

-- 5e) Conteo final de referencia:
--   select
--     (select count(*) from plantas_pedidos)           as pedidos_migrados,
--     (select count(*) from plantas_pedidos_historial)  as eventos_historial,
--     (select count(*) from plantas_vales)               as vales_migrados;

-- Por diseño, este borrador NO persiste nada la primera vez que se corre.
-- Después de revisar 5a-5e, cambiar la línea de abajo por `commit;` a mano.
rollback;
