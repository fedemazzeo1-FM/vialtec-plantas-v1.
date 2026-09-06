-- Migración 22: 2 fixes puntuales encontrados en la prueba de flujo total +
-- casos de borde del 2026-09-06 (ver memory/pending.md), aprobados por
-- Federico. 100% reemplazo de funciones existentes (CREATE OR REPLACE), no
-- toca schema ni datos.

-- ---------------------------------------------------------------------------
-- 1) plantas_descontar_stock_despacho(): stock fantasma al corregir un
--    despacho cuando un material había tocado el piso de 0.
--
-- Antes: el ajuste de "corregir_despacho" recalculaba el delta como
-- `fórmula × (cantidad_nueva − cantidad_anterior)`, asumiendo que el
-- despacho original había consumido el 100% de lo que la fórmula indicaba.
-- Si un material estaba en 0 durante el despacho original (piso aplicado —
-- plantas_aplicar_movimiento_stock no deja movimiento cuando el delta
-- aplicado da 0, decisión de Federico de no auditar eso, ver pending.md),
-- la corrección posterior "devolvía" kg que en la realidad nunca habían
-- salido → stock fantasma. Reproducido en vivo: pedido de 6tn con Asfalto
-- CA30 en 0 → corregido a 5.5tn → Asfalto CA30 pasó de 0 a 22.5kg.
--
-- Ahora: en vez de asumir el consumo histórico desde la fórmula, se lee el
-- historial REAL de plantas_stock_movimientos para ese pedido+material
-- (tipos 'egreso_despacho'/'recalculo_despacho', que son los únicos que
-- esta misma función genera) y se calcula el delta contra lo que
-- REALMENTE se aplicó, no contra lo que "debería" haberse aplicado. Esto
-- hace que:
--   - El primer llamado (desde finalizar_despacho, p_cantidad_anterior=0)
--     se comporta idéntico a antes: no hay movimientos previos, el "ya
--     aplicado" da 0, el delta es el consumo total de la fórmula completo.
--   - Cualquier corrección posterior es idempotente y converge al valor
--     correcto sin importar cuántas veces se corrija ni si hubo piso de
--     por medio (si el material sigue en 0, el piso se vuelve a aplicar y
--     no se acredita nada de más).
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
  v_consumo_total   numeric; -- kg que deberían quedar consumidos en total a la cantidad nueva
  v_aplicado_real   numeric; -- kg que YA se removieron de verdad del stock para este pedido+material
  v_delta_adicional numeric; -- diferencia entre lo que debería estar consumido y lo ya aplicado
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

-- ---------------------------------------------------------------------------
-- 2) cancelar_pedido(): pisaba las observaciones originales del pedido.
--
-- Antes: `update ... set observaciones = p_motivo` reemplazaba cualquier
-- nota previa (ej. instrucciones de entrega) por el motivo de cancelación
-- — el motivo ya queda auditado en plantas_pedidos_historial.motivo, así
-- que perder la observación original era innecesario.
--
-- Ahora: concatena "MOTIVO CANCELACIÓN: <motivo>" con la observación
-- previa si existía ("... | OBS: <observación original>").
create or replace function public.cancelar_pedido(p_pedido_id uuid, p_motivo text, p_usuario_legado text default null::text)
 returns plantas_pedidos
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_rol    text;
  v_pedido plantas_pedidos;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista', 'encargado', 'supervisor') then
    raise exception 'Tu rol (%) no puede cancelar pedidos.', coalesce(v_rol, 'sin rol asignado');
  end if;
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'El motivo es obligatorio para cancelar un pedido.';
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.estado not in ('solicitado', 'confirmado', 'postergado') then
    raise exception 'No se puede cancelar un pedido en estado %.', v_pedido.estado;
  end if;

  update plantas_pedidos
    set estado = 'cancelado',
        observaciones = 'MOTIVO CANCELACIÓN: ' || p_motivo ||
          case when v_pedido.observaciones is not null and btrim(v_pedido.observaciones) <> ''
               then ' | OBS: ' || v_pedido.observaciones
               else '' end
    where id = p_pedido_id
    returning * into v_pedido;

  insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id, motivo, usuario_legado)
  values (p_pedido_id, 'cancelado', now(), auth.uid(), p_motivo, coalesce(p_usuario_legado, auth.email()));

  return v_pedido;
end;
$function$;
