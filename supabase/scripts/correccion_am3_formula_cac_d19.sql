-- ============================================================================
-- Corrección de datos: stock de ASFALTO AM3 por la fórmula CAC D19 (AM3)
-- cargada con 47 % de asfalto en vez de 4,7 % (21/10 al 27/10/2026).
-- OK de Federico, 2026-10-28 (Felix estima ~19 tn en el tanque).
--
-- Qué hace (3 movimientos, cada uno con su fila de auditoría):
--   1. P-0264: recalculo_despacho +42.634,17 kg. Le quedan descontados
--      100,79 tn × 47 kg = 4.737,13 kg (tenía 47.371,30).
--   2. P-0298: recalculo_despacho −3.139,86 kg. Le quedan descontados
--      232,30 tn × 55 kg = 12.776,50 kg (el piso en 0 le recortó 3.139,86).
--   3. ajuste −19.589,25 kg sobre el relevamiento de Felix del 26/10 (09:03):
--      con 4,7 % el sistema tenía 19.589,25 kg antes del relevamiento, así que
--      el ajuste correcto era +770,75 y no +20.360.
--   4. ajuste −775,06 kg: medición de Felix del 28/10/2026, 19,13 tn exactas
--      (queda como un relevamiento más, con su fila de auditoría).
-- Resultado: ASFALTO AM3 pasa de 0 a 19.130 kg.
--
-- Controla el estado de partida (saldo, lo descontado a cada pedido, dosaje
-- de la fórmula, relevamiento) y el saldo final; si algo no cierra, falla
-- sin dejar nada a medias.
--
-- Dry-run: correr antes, en la misma ejecución,
--   select set_config('plantas.dry_run', 'on', false);
-- y el bloque termina con ERROR "DRYRUN AM3 OK — …" (todo revertido).
-- ============================================================================
do $fix$
declare
  c_motivo   constant text := 'Corrección por fórmula CAC D19 cargada con 47 % en vez de 4,7 %';
  v_dry      boolean := coalesce(current_setting('plantas.dry_run', true), '') = 'on';
  v_mat      uuid := plantas_buscar_material_id('ASFALTO AM3');
  v_formula  plantas_formulas;
  v_insumo   jsonb;
  v_p264     plantas_pedidos;
  v_p298     plantas_pedidos;
  v_f298     plantas_formulas;
  v_saldo0   numeric;
  v_apl264   numeric;
  v_apl298   numeric;
  v_obj264   numeric;
  v_obj298   numeric;
  v_aj_rel   numeric;
  v_aj_ok    numeric;
  v_mov      plantas_stock_movimientos;
  v_ids      uuid[] := '{}';
  c_medido   constant numeric := 19130;
  v_calc     numeric;
  v_saldo1   numeric;
  v_resumen  text;
begin
  if v_mat is null then
    raise exception 'No se encontró ASFALTO AM3 en el catálogo';
  end if;

  -- Estado de partida -------------------------------------------------------
  select * into v_formula from plantas_formulas where nombre = 'CAC D19 (AM3)';
  select i into v_insumo from jsonb_array_elements(v_formula.insumos) i where i->>'material' = 'ASFALTO AM3';
  if v_insumo is null or (v_insumo->>'cantidad')::numeric <> 4.7 or v_insumo->>'unidad' <> '%' then
    raise exception 'La fórmula CAC D19 (AM3) no tiene ASFALTO AM3 al 4,7 %%: %', v_insumo;
  end if;

  select * into v_p264 from plantas_pedidos where numero = 264;
  select * into v_p298 from plantas_pedidos where numero = 298;
  if v_p264.formula_id <> v_formula.id or v_p264.estado <> 'despachado' or v_p264.cantidad_despachada <> 100.79 then
    raise exception 'P-0264 no está como se esperaba (fórmula, estado o 100,79 tn)';
  end if;
  select * into v_f298 from plantas_formulas where id = v_p298.formula_id;
  if v_p298.estado <> 'despachado' or v_p298.cantidad_despachada <> 232.30 then
    raise exception 'P-0298 no está como se esperaba (estado o 232,30 tn)';
  end if;

  select cantidad_kg into v_saldo0 from plantas_stock where material_id = v_mat for update;
  if v_saldo0 <> 0 then
    raise exception 'El saldo de ASFALTO AM3 es % kg (se esperaba 0): revisar antes de corregir', v_saldo0;
  end if;

  select coalesce(sum(-cantidad_kg), 0) into v_apl264 from plantas_stock_movimientos
   where pedido_id = v_p264.id and material_id = v_mat and tipo in ('egreso_despacho', 'recalculo_despacho');
  select coalesce(sum(-cantidad_kg), 0) into v_apl298 from plantas_stock_movimientos
   where pedido_id = v_p298.id and material_id = v_mat and tipo in ('egreso_despacho', 'recalculo_despacho');
  if v_apl264 <> 47371.3 or v_apl298 <> 9636.64 then
    raise exception 'Descontado distinto de lo esperado: P-0264 % kg (47371,3), P-0298 % kg (9636,64)', v_apl264, v_apl298;
  end if;

  select (j->>'ajuste_kg')::numeric into v_aj_rel
    from plantas_auditoria a, jsonb_array_elements(a.valores_despues->'ajustes') j
   where a.id = 786 and a.entidad = 'relevamiento' and j->>'material' = 'ASFALTO AM3';
  if v_aj_rel is distinct from 20360 then
    raise exception 'El relevamiento 786 no ajustó ASFALTO AM3 en +20360 kg (dio %)', v_aj_rel;
  end if;

  -- Lo que cada pedido debió descontar con el dosaje correcto ---------------
  v_obj264 := plantas_calcular_consumo_kg(v_insumo, v_p264.cantidad_despachada);
  select plantas_calcular_consumo_kg(i, v_p298.cantidad_despachada) into v_obj298
    from jsonb_array_elements(v_f298.insumos) i where i->>'material' = 'ASFALTO AM3';
  -- Ajuste correcto del relevamiento: 20.360 medidos contra lo que había con
  -- 4,7 % (ingreso del 21/10 menos P-0264 con los 117,25 tn de ese momento).
  v_aj_ok := 20360 - (25100 - plantas_calcular_consumo_kg(v_insumo, 117.25));

  -- 1. P-0264 ---------------------------------------------------------------
  v_mov := plantas_aplicar_movimiento_stock(v_mat, 'recalculo_despacho', v_apl264 - v_obj264, null, null, v_p264.id, null, null,
    c_motivo || ' — P-0264: devuelve lo descontado de más (queda ' || v_obj264 || ' kg)');
  v_ids := v_ids || v_mov.id;
  perform plantas_auditar('CORREGIR', 'despachos', 'despacho', 'P-0264',
    'P-0264 — consumo de ASFALTO AM3', c_motivo,
    jsonb_build_object('asfalto_am3_descontado_kg', v_apl264),
    jsonb_build_object('asfalto_am3_descontado_kg', v_obj264));

  -- 2. P-0298 ---------------------------------------------------------------
  v_mov := plantas_aplicar_movimiento_stock(v_mat, 'recalculo_despacho', v_apl298 - v_obj298, null, null, v_p298.id, null, null,
    c_motivo || ' — P-0298: completa lo que el piso en 0 recortó el 28/10 (queda ' || v_obj298 || ' kg)');
  v_ids := v_ids || v_mov.id;
  perform plantas_auditar('CORREGIR', 'despachos', 'despacho', 'P-0298',
    'P-0298 — consumo de ASFALTO AM3', c_motivo,
    jsonb_build_object('asfalto_am3_descontado_kg', v_apl298),
    jsonb_build_object('asfalto_am3_descontado_kg', v_obj298));

  -- 3. Ajuste sobre el relevamiento del 26/10 -------------------------------
  v_mov := plantas_aplicar_movimiento_stock(v_mat, 'ajuste', v_aj_ok - v_aj_rel, 'Corrección de relevamiento', null, null, null, null,
    c_motivo || ' — relevamiento del 26/10/2026: el ajuste correcto era ' || v_aj_ok || ' kg, no ' || v_aj_rel || ' kg');
  v_ids := v_ids || v_mov.id;
  perform plantas_auditar('CORREGIR', 'stock', 'relevamiento', '2026-10-26 09:03:08',
    'Relevamiento del 26/10/2026 — ASFALTO AM3', c_motivo,
    jsonb_build_object('ajuste_kg', v_aj_rel), jsonb_build_object('ajuste_kg', v_aj_ok));

  -- 4. Medición de Felix (28/10/2026): 19,13 tn exactas -------------------
  select cantidad_kg into v_calc from plantas_stock where material_id = v_mat;
  if v_calc <> 19905.06 then
    raise exception 'Después de los 3 movimientos el saldo es % kg (se esperaba 19905,06)', v_calc;
  end if;
  v_mov := plantas_aplicar_movimiento_stock(v_mat, 'ajuste', c_medido - v_calc, 'Relevamiento', null, null, null, null,
    'Medición de Felix del 28/10/2026: ' || c_medido || ' kg (calculado ' || v_calc || ' kg)');
  v_ids := v_ids || v_mov.id;
  perform plantas_auditar('CREAR', 'stock', 'relevamiento', to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD HH24:MI:SS'),
    'Relevamiento de stock — 1 material(es) ajustado(s)',
    'Medición de Felix del 28/10/2026 después de la corrección de la fórmula CAC D19',
    null,
    jsonb_build_object('ajustes', jsonb_build_array(jsonb_build_object(
      'material', 'ASFALTO AM3', 'antes_kg', v_calc, 'ajuste_kg', c_medido - v_calc, 'despues_kg', c_medido))));

  update plantas_stock_movimientos set responsable_email = 'sistema (SQL)'
   where id = any(v_ids) and responsable_email is null;

  -- Controles finales -------------------------------------------------------
  select cantidad_kg into v_saldo1 from plantas_stock where material_id = v_mat;
  if v_saldo1 <> c_medido or array_length(v_ids, 1) <> 4 or array_position(v_ids, null) is not null then
    raise exception 'Resultado inesperado: saldo % kg, movimientos %', v_saldo1, v_ids;
  end if;
  if exists (select 1 from plantas_stock_movimientos where id = any(v_ids) and observaciones ilike '%stock insuficiente, piso en 0%') then
    raise exception 'Algún movimiento quedó recortado por el piso en 0';
  end if;

  v_resumen := format('saldo %s → %s kg || P-0264 %s → %s kg (%s) || P-0298 %s → %s kg (%s) || ajuste relevamiento %s → %s (%s) || medición %s → %s (%s) || auditoría %s filas',
    v_saldo0, v_saldo1, v_apl264, v_obj264, v_apl264 - v_obj264, v_apl298, v_obj298, v_apl298 - v_obj298,
    v_aj_rel, v_aj_ok, v_aj_ok - v_aj_rel, v_calc, c_medido, c_medido - v_calc,
    (select count(*) from plantas_auditoria where motivo = c_motivo or motivo like 'Medición de Felix del 28/10/2026%'));
  if v_dry then
    raise exception 'DRYRUN AM3 OK — %', v_resumen;
  end if;
  raise notice 'Corrección AM3 aplicada — %', v_resumen;
end;
$fix$;
