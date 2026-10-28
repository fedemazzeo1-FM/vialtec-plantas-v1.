-- ============================================================================
-- Dry-run de la migración 70. Pegar DESPUÉS del contenido completo de
-- supabase/migrations/70_descuento_por_diferencia_y_dosaje_formulas.sql, en
-- la misma ejecución. Termina SIEMPRE con ERROR (todo se revierte):
--   "DRYRUN 70 OK — …"  si todos los chequeos pasan.
-- No consume numeración: no crea pedidos ni vales.
-- ============================================================================
do $dry$
declare
  v_am3    uuid := plantas_buscar_material_id('ASFALTO AM3');
  v_p264   uuid := (select id from plantas_pedidos where numero = 264);
  v_p298   uuid := (select id from plantas_pedidos where numero = 298);
  v_s0     numeric;
  v_s      numeric;
  v_ok     text[] := '{}';
  v_err    boolean;
begin
  select cantidad_kg into v_s0 from plantas_stock where material_id = v_am3;

  -- A. Ligante al 47 % → rechazo
  v_err := false;
  begin
    insert into plantas_formulas (nombre, tipo, unidad, activo, insumos)
    values ('DRYRUN 70 A', 'asfalto', 'tn', true,
      '[{"material":"ASFALTO AM3","cantidad":47,"unidad":"%"},{"material":"6/20","cantidad":47,"unidad":"%"},{"material":"0/6","cantidad":53,"unidad":"%"}]');
  exception when check_violation then v_err := true;
  end;
  if not v_err then raise exception 'A: aceptó AM3 al 47 %%'; end if;
  v_ok := v_ok || 'A ligante 47% rechazado'::text;

  -- B. Suma 120 % sin ligante alto → rechazo
  v_err := false;
  begin
    insert into plantas_formulas (nombre, tipo, unidad, activo, insumos)
    values ('DRYRUN 70 B', 'asfalto', 'tn', true,
      '[{"material":"ASFALTO CA30","cantidad":5,"unidad":"%"},{"material":"6/20","cantidad":60,"unidad":"%"},{"material":"0/6","cantidad":55,"unidad":"%"}]');
  exception when check_violation then v_err := true;
  end;
  if not v_err then raise exception 'B: aceptó una suma de 120 %%'; end if;
  v_ok := v_ok || 'B suma 120% rechazada'::text;

  -- C. Editar CAC D19 (AM3) a 47 % → rechazo
  v_err := false;
  begin
    update plantas_formulas
       set insumos = (select jsonb_agg(case when i->>'material' = 'ASFALTO AM3' then jsonb_set(i, '{cantidad}', '47') else i end)
                        from jsonb_array_elements(insumos) i)
     where nombre = 'CAC D19 (AM3)';
  exception when check_violation then v_err := true;
  end;
  if not v_err then raise exception 'C: aceptó editar CAC D19 (AM3) a 47 %%'; end if;
  v_ok := v_ok || 'C edición a 47% rechazada'::text;

  -- D. Todas las fórmulas existentes pasan la validación
  update plantas_formulas set insumos = insumos;
  v_ok := v_ok || ('D ' || (select count(*) from plantas_formulas) || ' fórmulas existentes OK')::text;

  -- E. Corrección que sube 10 tn a P-0298 (SMA19 2, AM3 5,5 %) → −550 kg
  perform plantas_descontar_stock_despacho(v_p298, 232.30, 242.30);
  select cantidad_kg into v_s from plantas_stock where material_id = v_am3;
  if v_s <> v_s0 - 550 then raise exception 'E: AM3 % kg, se esperaba %', v_s, v_s0 - 550; end if;
  v_ok := v_ok || 'E +10 tn descuenta 550 kg'::text;

  -- F. Vuelta atrás (242,30 → 232,30) → +550 kg
  perform plantas_descontar_stock_despacho(v_p298, 242.30, 232.30);
  select cantidad_kg into v_s from plantas_stock where material_id = v_am3;
  if v_s <> v_s0 then raise exception 'F: AM3 % kg, se esperaba %', v_s, v_s0; end if;
  v_ok := v_ok || 'F −10 tn devuelve 550 kg'::text;

  -- G. Stock fantasma (migración 22): bajar P-0264 a 0 devuelve lo aplicado
  --    (4.737,13); repetirlo no devuelve nada más.
  perform plantas_descontar_stock_despacho(v_p264, 100.79, 0);
  select cantidad_kg into v_s from plantas_stock where material_id = v_am3;
  if v_s - v_s0 <> 4737.13 then
    raise exception 'G1: devolvió % kg, se esperaba 4737,13', v_s - v_s0;
  end if;
  perform plantas_descontar_stock_despacho(v_p264, 100.79, 0);
  if (select cantidad_kg from plantas_stock where material_id = v_am3) <> v_s then
    raise exception 'G2: devolvió kg que nunca salieron (stock fantasma)';
  end if;
  v_ok := v_ok || 'G sin stock fantasma'::text;

  -- H. Permisos
  if has_function_privilege('anon', 'plantas_descontar_stock_despacho(uuid,numeric,numeric)', 'execute')
     or has_function_privilege('authenticated', 'plantas_descontar_stock_despacho(uuid,numeric,numeric)', 'execute')
     or has_function_privilege('authenticated', 'plantas_trg_validar_dosaje_formula()', 'execute') then
    raise exception 'H: alguna función quedó ejecutable por anon/authenticated';
  end if;
  v_ok := v_ok || 'H sin EXECUTE para anon/authenticated'::text;

  raise exception 'DRYRUN 70 OK — %', array_to_string(v_ok, ' || ');
end;
$dry$;
