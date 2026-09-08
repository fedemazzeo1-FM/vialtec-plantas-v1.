-- ============================================================================
-- Migración 34: 2 correcciones de datos en plantas_stock_movimientos
-- (pedido de Federico 2026-09-08, revisando Stock → Historial de ingresos:
-- "faltan proveedor y remito" + "los pesos están mal, 26 tn aparece como
-- 0.026 tn"). Autorizada por Federico ("si") — QUEDÓ SIN APLICAR: el
-- clasificador de permisos de Claude Code bloqueó la llamada que combinaba
-- el UPDATE + INSERT de acá abajo con el cambio de vista (que sí se aplicó
-- por separado, ver migración 33). Falta que alguien la corra a mano desde
-- el SQL Editor de Supabase, o que Federico la reautorice para reintentar
-- por MCP.
--
-- Diagnóstico completo (consultas de solo lectura contra producción antes
-- de escribir esto, memory/pending.md tiene el detalle):
--
-- 1) BUG DE UNIDADES (552 filas): migracion_historial_v2.sql §8a leía la
--    cantidad de cada evento de `vt_m9` con
--    `coalesce((m->>'cantidadKg')::numeric, (m->>'cantidad')::numeric)` —
--    cuando el evento SÍ tenía `cantidadKg` (103 filas), ese valor ya
--    estaba en kg, correcto (25.150–40.640). Cuando NO lo tenía y caía al
--    fallback `cantidad` (542 ingreso_proveedor + 10 egreso_arido = 552
--    filas), ese campo en el legado estaba en TONELADAS, no en kg, y se
--    insertó tal cual sin multiplicar ×1000 (valores 1–42, imposibles como
--    kg para un ingreso/egreso de planta, perfectamente normales como tn).
--    Confirmado con la propia forma del dato: las 552 filas bugueadas son
--    exactamente las que datos_legados NO tiene la clave 'cantidadKg'.
--    No afecta el stock actual (`plantas_stock.cantidad_kg` se cargó
--    directo desde `vt_s9`, nunca se derivó de estos movimientos — ver
--    comentario en migracion_historial_v2.sql línea ~105) — es una
--    corrección puramente del historial/auditoría.
--
-- 2) PROVEEDOR/REMITO FALTANTES (503 filas para agregar): son dos fuentes
--    del legado que quedaron desconectadas. `vt_m9` (origen de los 645
--    movimientos de arriba) nunca tuvo proveedor/remito — no es que se
--    perdiera al migrar, ese dato no existía ahí. La fuente que SÍ tiene
--    proveedor/remito/cantidad es `vt_ingaridos9`, migrada en su momento a
--    `plantas_ingresos` (503 filas, todas con `vale_id`, ninguna con
--    `plantas_stock_movimientos.ingreso_id` — nunca se les generó el
--    movimiento correspondiente). Se backfillean acá esas 503 filas
--    faltantes, mismo criterio que usa `registrar_pesada_bascula()` para un
--    ingreso nuevo (cantidad × 1000, tipo 'ingreso_proveedor', origen =
--    proveedor, numero_remito, ligado por `ingreso_id`). Verificado antes:
--    las 503 tienen unidad 'tn' y su material matchea un
--    `plantas_materiales` real (0 huérfanas).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Fix de unidades — ×1000 en las 552 filas identificadas.
-- ----------------------------------------------------------------------------
update plantas_stock_movimientos
set cantidad_kg = cantidad_kg * 1000
where tipo in ('ingreso_proveedor', 'egreso_arido')
  and datos_legados is not null
  and not (datos_legados ? 'cantidadKg');

-- ----------------------------------------------------------------------------
-- 2) Backfill de los 503 ingresos de báscula (plantas_ingresos) que nunca
--    tuvieron su plantas_stock_movimientos correspondiente.
-- ----------------------------------------------------------------------------
insert into plantas_stock_movimientos (
  material_id, tipo, cantidad_kg, origen, numero_remito, ingreso_id, observaciones, fecha_movimiento, datos_legados
)
select
  plantas_buscar_material_id(pi.material),
  'ingreso_proveedor',
  pi.cantidad * (case when pi.unidad = 'kg' then 1 else 1000 end),
  pi.proveedor,
  pi.numero_remito,
  pi.id,
  pi.observaciones,
  pi.fecha_ingreso,
  jsonb_build_object('backfill_2026_09_08', true, 'motivo', 'plantas_ingresos sin movimiento de stock desde la migración original')
from plantas_ingresos pi
where not exists (select 1 from plantas_stock_movimientos psm where psm.ingreso_id = pi.id)
  and plantas_buscar_material_id(pi.material) is not null;
