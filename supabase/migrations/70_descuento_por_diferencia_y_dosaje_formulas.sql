-- ============================================================================
-- Migración 70 — corrección de despacho por diferencia + validar dosaje
-- ESTADO: BORRADOR. Dry-run: supabase/scripts/dry_run_migracion_70.sql.
-- Reversión: supabase/scripts/revertir_migracion_70.sql.
-- ============================================================================
--
-- Origen (28/10/2026): la fórmula CAC D19 (AM3) se cargó el 21/10 con 47 % de
-- asfalto en vez de 4,7 %. P-0264 pidió 55.107,5 kg de AM3 y el piso en 0 lo
-- recortó a 25.100. El 27/10, al corregir P-0264 (117,25 → 100,79 tn) con la
-- fórmula todavía en 47 %, plantas_descontar_stock_despacho descontó lo que
-- "debía llevar" menos lo ya aplicado (47.371,3 − 25.100 = 22.271,3 kg) y se
-- llevó el ingreso del camión del 26/10. Stock corregido a mano el 28/10
-- (supabase/scripts/correccion_am3_formula_cac_d19.sql).
--
-- Qué hace:
--   1) plantas_descontar_stock_despacho: una corrección descuenta o devuelve
--      solo la DIFERENCIA de cantidad, fórmula × (nueva − anterior). Ya no
--      cobra lo que el piso en 0 recortó en el despacho original.
--      Se mantiene la protección de la migración 22 (stock fantasma): una
--      devolución nunca supera lo que realmente se descontó a ese pedido en
--      ese material. El primer descuento (desde finalizar_despacho, anterior
--      = 0) queda igual que antes.
--   2) Trigger en plantas_formulas que rechaza dosajes imposibles (gemela de
--      validarDosajeFormula() en src/modules/maestros/services/formulas.service.js):
--        - un ligante (ASFALTO CA30, ASFALTO AM3, AM3 AUTOVIA) en % por encima
--          de 10 %;
--        - cualquier insumo en % por encima de 100 %;
--        - la suma de los insumos en % por encima de 110 %.
--      Hoy la fórmula más alta suma 104,8 % y el ligante más alto es 7 %.
--      Si se renombra un ligante en Maestros, actualizar la lista acá y en
--      formulas.service.js.
--
-- Qué NO hace: no toca finalizar_despacho, corregir_despacho ni ningún dato.
-- El aviso en pantalla cuando el piso recorta es solo de frontend.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Corrección por diferencia
-- ----------------------------------------------------------------------------
create or replace function public.plantas_descontar_stock_despacho(p_pedido_id uuid, p_cantidad_anterior numeric, p_cantidad_nueva numeric)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_pedido          plantas_pedidos;
  v_formula         plantas_formulas;
  v_insumo          jsonb;
  v_material_id     uuid;
  v_tipo            text;
  v_consumo_delta   numeric; -- kg a descontar (+) o devolver (−) por el cambio de cantidad
  v_aplicado_real   numeric; -- kg que YA se descontaron de verdad para este pedido+material
begin
  if coalesce(p_cantidad_nueva, 0) = coalesce(p_cantidad_anterior, 0) then
    return;
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id;
  if v_pedido.formula_id is null then
    return;
  end if;
  select * into v_formula from plantas_formulas where id = v_pedido.formula_id;
  if v_formula is null then
    return;
  end if;

  v_tipo := case when coalesce(p_cantidad_anterior, 0) = 0 then 'egreso_despacho' else 'recalculo_despacho' end;

  for v_insumo in select * from jsonb_array_elements(coalesce(v_formula.insumos, '[]'::jsonb))
  loop
    if lower(btrim(coalesce(v_insumo->>'material', ''))) in ('agua', 'purgue') then
      continue;
    end if;

    v_material_id := plantas_buscar_material_id(v_insumo->>'material');
    if v_material_id is null then
      continue;
    end if;

    v_consumo_delta := plantas_calcular_consumo_kg(v_insumo, coalesce(p_cantidad_nueva, 0))
                     - plantas_calcular_consumo_kg(v_insumo, coalesce(p_cantidad_anterior, 0));

    -- Migración 22: no devolver kg que nunca salieron (piso en 0 en el
    -- despacho original → stock fantasma).
    if v_consumo_delta < 0 then
      select coalesce(sum(-cantidad_kg), 0) into v_aplicado_real
        from plantas_stock_movimientos
        where pedido_id = p_pedido_id
          and material_id = v_material_id
          and tipo in ('egreso_despacho', 'recalculo_despacho');
      v_consumo_delta := greatest(v_consumo_delta, -greatest(v_aplicado_real, 0));
    end if;

    if v_consumo_delta = 0 then
      continue;
    end if;

    perform plantas_aplicar_movimiento_stock(
      v_material_id, v_tipo, -v_consumo_delta, null, null, p_pedido_id, null, null,
      'Fórmula ' || coalesce(v_formula.nombre, '') || ' — pedido ' || p_pedido_id::text
    );
  end loop;
end;
$function$;

revoke execute on function public.plantas_descontar_stock_despacho(uuid, numeric, numeric) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2) Validación de dosaje en fórmulas
-- ----------------------------------------------------------------------------
create or replace function public.plantas_trg_validar_dosaje_formula()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare
  c_ligantes   constant text[] := array['ASFALTO CA30', 'ASFALTO AM3', 'AM3 AUTOVIA'];
  c_max_ligante constant numeric := 10;
  c_max_suma    constant numeric := 110;
  v_insumo     jsonb;
  v_material   text;
  v_cantidad   numeric;
  v_suma       numeric := 0;
begin
  for v_insumo in select * from jsonb_array_elements(coalesce(new.insumos, '[]'::jsonb))
  loop
    if v_insumo->>'unidad' is distinct from '%' then
      continue;
    end if;
    v_material := upper(btrim(coalesce(v_insumo->>'material', '')));
    v_cantidad := coalesce((v_insumo->>'cantidad')::numeric, 0);

    if v_material = any(c_ligantes) and v_cantidad > c_max_ligante then
      raise exception 'Dosaje imposible en la fórmula "%": % al % %% (un ligante no puede pasar de % %%; ¿quisiste poner %?)',
        new.nombre, v_material, v_cantidad, c_max_ligante, round(v_cantidad / 10, 2)
        using errcode = 'check_violation';
    end if;
    if v_cantidad > 100 then
      raise exception 'Dosaje imposible en la fórmula "%": % al % %% (ningún insumo puede pasar de 100 %%)',
        new.nombre, v_material, v_cantidad
        using errcode = 'check_violation';
    end if;
    v_suma := v_suma + v_cantidad;
  end loop;

  if v_suma > c_max_suma then
    raise exception 'Dosaje imposible en la fórmula "%": los insumos en %% suman % %% (máximo %)',
      new.nombre, v_suma, c_max_suma
      using errcode = 'check_violation';
  end if;

  return new;
end;
$function$;

revoke execute on function public.plantas_trg_validar_dosaje_formula() from public, anon, authenticated;

drop trigger if exists plantas_validar_dosaje_formula on public.plantas_formulas;
create trigger plantas_validar_dosaje_formula
  before insert or update of insumos on public.plantas_formulas
  for each row execute function public.plantas_trg_validar_dosaje_formula();

-- ----------------------------------------------------------------------------
-- Chequeos después de aplicar (correr a mano):
--   select md5(pg_get_functiondef('plantas_descontar_stock_despacho'::regproc)), proacl
--     from pg_proc where proname = 'plantas_descontar_stock_despacho';
--   select tgname from pg_trigger where tgrelid = 'plantas_formulas'::regclass and not tgisinternal;
-- ----------------------------------------------------------------------------
