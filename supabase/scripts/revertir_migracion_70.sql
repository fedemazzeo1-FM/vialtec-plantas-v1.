-- ============================================================================
-- Reversión de la migración 70: vuelve plantas_descontar_stock_despacho a la
-- versión de la migración 22 ("lo que debería llevar menos lo ya aplicado",
-- md5 f258884959279008aad414e18831efe9 en producción al 28/10/2026) y saca la
-- validación de dosaje de plantas_formulas. No toca datos.
-- ============================================================================
begin;

drop trigger if exists plantas_validar_dosaje_formula on public.plantas_formulas;
drop function if exists public.plantas_trg_validar_dosaje_formula();

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
  v_consumo_total   numeric;
  v_aplicado_real   numeric;
  v_delta_adicional numeric;
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

    v_consumo_total := plantas_calcular_consumo_kg(v_insumo, coalesce(p_cantidad_nueva, 0));

    select coalesce(sum(-cantidad_kg), 0) into v_aplicado_real
      from plantas_stock_movimientos
      where pedido_id = p_pedido_id
        and material_id = v_material_id
        and tipo in ('egreso_despacho', 'recalculo_despacho');

    v_delta_adicional := v_consumo_total - v_aplicado_real;
    if v_delta_adicional = 0 then
      continue;
    end if;

    perform plantas_aplicar_movimiento_stock(
      v_material_id, v_tipo, -v_delta_adicional, null, null, p_pedido_id, null, null,
      'Fórmula ' || coalesce(v_formula.nombre, '') || ' — pedido ' || p_pedido_id::text
    );
  end loop;
end;
$function$;

revoke execute on function public.plantas_descontar_stock_despacho(uuid, numeric, numeric) from public, anon, authenticated;

-- Debe dar f258884959279008aad414e18831efe9 (si no, revisar antes de commit)
select md5(pg_get_functiondef('plantas_descontar_stock_despacho'::regproc));

commit;
