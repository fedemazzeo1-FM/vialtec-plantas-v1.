-- ============================================================================
-- Ensayo de la migración 77 (vales manuales). Correr DESPUÉS de 77_vales_manuales.sql,
-- en la misma transacción. Termina SIEMPRE con ERROR "DRYRUN 77 OK — …" (todo revertido).
-- La numeración de remitos (plantas_remitos_numero_seq) no es transaccional: el
-- ensayo la devuelve al valor que tenía, para no dejar un salto en los remitos reales.
-- ============================================================================
do $dry$
declare
  v_ok        text[] := '{}';
  v_seq_antes bigint;
  v_seq_llamada boolean;
  v_obra      bigint := (select id from flota_obras order by id limit 1);
  v_formula   uuid := (select id from plantas_formulas where tipo = 'asfalto' and activo order by nombre limit 1);
  v_no_asf    uuid := (select id from plantas_formulas where tipo <> 'asfalto' limit 1);
  v_prod_antes jsonb;
  v_prod_desp  jsonb;
  v_a         plantas_vales_manuales;
  v_b         plantas_vales_manuales;
  v_r         plantas_vales_manuales;
  v_aud       int;
  v_err       text;
begin
  select last_value, is_called into v_seq_antes, v_seq_llamada from plantas_remitos_numero_seq;

  -- Foto de todo lo que alimenta producción, stock y báscula: no se tiene que mover.
  v_prod_antes := jsonb_build_object(
    'pedidos', (select md5(string_agg(id::text || coalesce(cantidad_despachada::text, '') || estado, ',' order by id)) from plantas_pedidos),
    'vales', (select count(*) from plantas_vales),
    'stock', (select md5(string_agg(material_id::text || cantidad_kg::text, ',' order by material_id)) from plantas_stock),
    'movs', (select count(*) from plantas_stock_movimientos),
    'remitos_man', (select count(*) from plantas_remitos_manuales));

  -- A. Sin sesión (rol nulo): no puede generar.
  begin
    perform generar_vale_manual(now(), v_formula, 30, 12, v_obra);
    raise exception 'A: generó sin rol';
  exception when others then
    if sqlerrm not like '%no puede generar vales manuales%' then raise; end if;
  end;
  v_ok := v_ok || 'A sin rol: rechazado'::text;

  -- Sesión de admin para el resto.
  perform set_config('request.jwt.claims', '{"email":"federico.mazzeo@vialtec.com.ar","role":"authenticated"}', true);

  -- B. Validaciones.
  begin perform generar_vale_manual(now(), v_formula, 30, 12); raise exception 'B1'; exception when others then
    if sqlerrm not like '%obra o un cliente%' then raise; end if; end;
  begin perform generar_vale_manual(now(), v_formula, 30, 12, v_obra, 'CLIENTE X'); raise exception 'B2'; exception when others then
    if sqlerrm not like '%obra o un cliente%' then raise; end if; end;
  begin perform generar_vale_manual(now(), v_formula, 10, 12, v_obra); raise exception 'B3'; exception when others then
    if sqlerrm not like '%mayor que la tara%' then raise; end if; end;
  if v_no_asf is not null then
    begin perform generar_vale_manual(now(), v_no_asf, 30, 12, v_obra); raise exception 'B4'; exception when others then
      if sqlerrm not like '%mezcla de asfalto%' then raise; end if; end;
  end if;
  v_ok := v_ok || 'B validaciones: destino único, bruto>tara, solo asfalto'::text;

  -- C. Genera dos (obra y cliente): numeración propia y neto calculado.
  v_a := generar_vale_manual('2026-11-17 10:30-03', v_formula, 38.5, 14.2, v_obra, null, ' ab 123 cd ', 'Juan', 155, 'Retiro sin pesar');
  v_b := generar_vale_manual(now(), v_formula, 30, 12, null, '  Cliente Ensayo ');
  if v_a.numero <> 1 or v_b.numero <> 2 or v_a.peso_neto <> 24.3 or v_a.patente <> 'AB 123 CD'
     or v_b.cliente_externo <> 'Cliente Ensayo' or v_a.creado_por <> 'federico.mazzeo@vialtec.com.ar' then
    raise exception 'C: %, %', to_jsonb(v_a), to_jsonb(v_b);
  end if;
  if plantas_etiqueta_vale_manual(v_a.numero) <> 'M-00001' then raise exception 'C: etiqueta'; end if;
  v_ok := v_ok || ('C M-00001 neto ' || v_a.peso_neto || ' tn y M-00002 a cliente')::text;

  -- D. Remito: toma el siguiente de la numeración común, una sola vez.
  v_r := generar_remito_vale_manual(v_a.id);
  if v_r.numero_remito <> v_seq_antes + (case when v_seq_llamada then 1 else 0 end) then
    raise exception 'D: remito % (seq estaba en %)', v_r.numero_remito, v_seq_antes;
  end if;
  if (generar_remito_vale_manual(v_a.id)).numero_remito <> v_r.numero_remito then raise exception 'D: no idempotente'; end if;
  v_ok := v_ok || ('D remito ' || v_r.numero_remito || ' (siguiente de la numeración común), reimprimir = mismo número')::text;

  -- E. Anulación: motivo obligatorio, no dos veces, sin remito después.
  begin perform anular_vale_manual(v_b.id, '  '); raise exception 'E1'; exception when others then
    if sqlerrm not like '%motivo%' then raise; end if; end;
  v_b := anular_vale_manual(v_b.id, 'Cargado de prueba');
  if not v_b.anulado or v_b.motivo_anulacion <> 'Cargado de prueba' then raise exception 'E2'; end if;
  begin perform anular_vale_manual(v_b.id, 'otra'); raise exception 'E3'; exception when others then
    if sqlerrm not like '%ya está anulado%' then raise; end if; end;
  begin perform generar_remito_vale_manual(v_b.id); raise exception 'E4'; exception when others then
    if sqlerrm not like '%anulado%' then raise; end if; end;
  v_ok := v_ok || 'E anulación con motivo, una vez, y sin remito'::text;

  -- F. Auditoría: CREAR x2, EDITAR (remito) x1, ANULAR x1.
  select count(*) into v_aud from plantas_auditoria where entidad = 'vale_manual'
   and ((tipo_accion = 'CREAR') or (tipo_accion = 'EDITAR' and entidad_label like '%remito%') or (tipo_accion = 'ANULAR' and motivo = 'Cargado de prueba'))
   and usuario_email = 'federico.mazzeo@vialtec.com.ar';
  if v_aud <> 4 then raise exception 'F: auditoría %', v_aud; end if;
  v_ok := v_ok || ('F auditoría: ' || (select entidad_label from plantas_auditoria where entidad = 'vale_manual' and tipo_accion = 'CREAR' order by id limit 1))::text;

  -- G. Nada de producción, stock, báscula ni remitos manuales se movió.
  v_prod_desp := jsonb_build_object(
    'pedidos', (select md5(string_agg(id::text || coalesce(cantidad_despachada::text, '') || estado, ',' order by id)) from plantas_pedidos),
    'vales', (select count(*) from plantas_vales),
    'stock', (select md5(string_agg(material_id::text || cantidad_kg::text, ',' order by material_id)) from plantas_stock),
    'movs', (select count(*) from plantas_stock_movimientos),
    'remitos_man', (select count(*) from plantas_remitos_manuales));
  if v_prod_desp <> v_prod_antes then raise exception 'G: se movió %', v_prod_desp; end if;
  v_ok := v_ok || 'G pedidos, vales de báscula, stock y movimientos intactos'::text;

  -- H. Sin escritura directa ni acceso anónimo.
  if has_table_privilege('authenticated', 'plantas_vales_manuales', 'insert')
     or has_table_privilege('authenticated', 'plantas_vales_manuales', 'update')
     or has_table_privilege('authenticated', 'plantas_vales_manuales', 'delete')
     or has_table_privilege('anon', 'plantas_vales_manuales', 'select')
     or not has_table_privilege('authenticated', 'plantas_vales_manuales', 'select')
     or has_function_privilege('anon', 'generar_vale_manual(timestamptz, uuid, numeric, numeric, bigint, text, text, text, numeric, text)', 'execute')
     or not has_function_privilege('authenticated', 'anular_vale_manual(uuid, text)', 'execute') then
    raise exception 'H: permisos';
  end if;
  v_ok := v_ok || 'H solo lectura para la app, escritura por RPC, nada para anon'::text;

  -- La numeración de remitos vuelve a donde estaba.
  perform setval('plantas_remitos_numero_seq', v_seq_antes, v_seq_llamada);

  raise exception 'DRYRUN 77 OK — %', array_to_string(v_ok, ' || ');
exception when others then
  -- Cualquier salida (OK o falla) devuelve la numeración de remitos.
  if v_seq_antes is not null then perform setval('plantas_remitos_numero_seq', v_seq_antes, v_seq_llamada); end if;
  raise;
end;
$dry$;
