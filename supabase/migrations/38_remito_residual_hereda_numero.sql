-- ============================================================================
-- Migración 38: el pedido residual (despacho parcial + "dividir pedido")
-- hereda el nro_remito_global del pedido padre, no arranca en null
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Diagnóstico 2026-09-14 (pedido de Federico: "todas las pesadas de un mismo
-- pedido tienen que compartir el mismo N° de remito, no incrementar por
-- pesada"). Verificado contra datos reales de producción: registrar_carga_asfalto()
-- (migración 36) YA asigna correctamente UN solo nro_remito_global por
-- pedido — confirmado con 4 pedidos reales con 3 cargas cada uno, las 3
-- comparten el mismo número (el numero_vale de báscula sí es distinto por
-- pesada, y eso es correcto/esperado, es un documento distinto).
--
-- El gap real encontrado está en finalizar_despacho(): cuando un despacho
-- parcial genera un pedido residual (checkbox "Dividir pedido"), el INSERT
-- del pedido nuevo no copia nro_remito_global — queda null y, en su próxima
-- carga, registrar_carga_asfalto() le asigna un número NUEVO de la secuencia
-- (correcto por el coalesce de esa función, pero es un número distinto al
-- del pedido original). Si en la operación real un mismo pedido termina
-- dividiéndose varias veces (parciales sucesivos), cada residual sacaría su
-- propio número — visualmente parece "la numeración sube con cada pesada",
-- aunque técnicamente sube por PEDIDO residual, no por carga individual
-- dentro de un mismo pedido.
--
-- Fix: el INSERT del residual agrega nro_remito_global = v_pedido.nro_remito_global
-- (mismo criterio que ya copia obra_id/formula_id/tipo_pedido/cliente_externo/
-- encargado/ubicacion del padre). Sin cambio de firma ni de comportamiento
-- para hormigón (nro_remito_global no se usa ahí, sigue null siempre).
-- ============================================================================

create or replace function finalizar_despacho(p_pedido_id uuid, p_dividir boolean default false, p_fecha_residual date default null)
returns plantas_pedidos
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_pedido   plantas_pedidos;
  v_residual numeric;
begin
  if not plantas_tiene_permiso('despachos', 'aprobar') then
    raise exception 'Tu rol (%) no puede finalizar un despacho.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.estado <> 'confirmado' then
    raise exception 'El pedido tiene que estar confirmado para finalizar el despacho (estado actual: %).', v_pedido.estado;
  end if;
  if coalesce(v_pedido.cantidad_despachada, 0) <= 0 then
    raise exception 'Todavía no se cargó ninguna carga para este pedido.';
  end if;

  v_residual := v_pedido.cantidad_solicitada - v_pedido.cantidad_despachada;

  update plantas_pedidos set estado = 'despachado' where id = p_pedido_id;

  perform plantas_descontar_stock_despacho(p_pedido_id, 0, v_pedido.cantidad_despachada);

  insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id)
  values (p_pedido_id, 'despachado', now(), auth.uid());

  if p_dividir and v_residual > 0 then
    if p_fecha_residual is null then
      raise exception 'Elegí una fecha para el pedido residual.';
    end if;

    declare
      v_nuevo_id uuid;
    begin
      insert into plantas_pedidos (
        obra_id, formula_id, tipo, cantidad_solicitada, fecha_programada, estado,
        tipo_pedido, cliente_externo, encargado, ubicacion, observaciones, nro_remito_global
      ) values (
        v_pedido.obra_id, v_pedido.formula_id, v_pedido.tipo, v_residual, p_fecha_residual, 'confirmado',
        v_pedido.tipo_pedido, v_pedido.cliente_externo, v_pedido.encargado, v_pedido.ubicacion,
        'Pedido residual generado automáticamente al dividir el despacho del ' || v_pedido.id::text,
        v_pedido.nro_remito_global
      )
      returning id into v_nuevo_id;

      insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id, motivo)
      values (v_nuevo_id, 'confirmado', now(), auth.uid(), 'Residual del pedido ' || v_pedido.id::text);
    end;
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id;
  return v_pedido;
end;
$$;

comment on function finalizar_despacho is
  'Cierra un pedido confirmado -> despachado con lo cargado hasta el momento (parcial o completo), genera el residual si corresponde. El residual hereda nro_remito_global del pedido padre (migración 38) — mismo remito para todo el despacho real, aunque se haya partido en más de un pedido del sistema. nro_remito_global en sí sigue asignándose solo en registrar_carga_asfalto() (migración 36).';

revoke execute on function finalizar_despacho(uuid, boolean, date) from public;
grant execute on function finalizar_despacho(uuid, boolean, date) to authenticated;
