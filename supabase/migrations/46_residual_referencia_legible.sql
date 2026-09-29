-- ============================================================================
-- Migración 46: el pedido residual referencia al pedido padre de forma legible
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Pedido de Federico (2026-09-29): al dividir un despacho, la observación del
-- residual mostraba el UUID interno del pedido padre ("... al dividir el
-- despacho del dbc209f0-a0e4-480a-99e4-955845645709"), igual que el motivo
-- del historial ("Residual del pedido <uuid>").
--
-- plantas_pedidos no tiene un número de pedido propio: lo que identifica al
-- padre para el usuario es su fecha, la cantidad pedida y (en asfalto) el N°
-- de remito, que el residual hereda (migración 38). Queda, por ejemplo:
--   "Pedido residual generado automáticamente al dividir el despacho del
--    pedido del 24/09/2026 (550 tn, Remito N° 00030)"
-- El N° de remito se rellena a 5 dígitos, igual que formatearNumeroRemito()
-- (src/services/formato-numeros.js). Hormigón no tiene remito único: solo
-- fecha y cantidad en m³.
--
-- Parte de la definición REAL de producción (pg_get_functiondef, 2026-09-29,
-- idéntica a la migración 38). Solo cambian los 2 textos; misma firma, mismo
-- comportamiento. No toca las filas ya existentes (hay 1 residual con el UUID
-- en observaciones y 1 en el historial) — eso es una corrección de datos aparte.
--
-- Reversión: volver a correr el create or replace de la migración 38.
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
  v_ref      text;
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

    -- "pedido del 24/09/2026 (550 tn, Remito N° 00030)"
    v_ref := 'pedido del ' || to_char(v_pedido.fecha_programada, 'DD/MM/YYYY')
      || ' (' || replace(trim_scale(v_pedido.cantidad_solicitada)::text, '.', ',')
      || case when v_pedido.tipo = 'hormigon' then ' m³' else ' tn' end
      || coalesce(', Remito N° ' || lpad(nullif(v_pedido.nro_remito_global, ''), 5, '0'), '')
      || ')';

    declare
      v_nuevo_id uuid;
    begin
      insert into plantas_pedidos (
        obra_id, formula_id, tipo, cantidad_solicitada, fecha_programada, estado,
        tipo_pedido, cliente_externo, encargado, ubicacion, observaciones, nro_remito_global
      ) values (
        v_pedido.obra_id, v_pedido.formula_id, v_pedido.tipo, v_residual, p_fecha_residual, 'confirmado',
        v_pedido.tipo_pedido, v_pedido.cliente_externo, v_pedido.encargado, v_pedido.ubicacion,
        'Pedido residual generado automáticamente al dividir el despacho del ' || v_ref,
        v_pedido.nro_remito_global
      )
      returning id into v_nuevo_id;

      insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id, motivo)
      values (v_nuevo_id, 'confirmado', now(), auth.uid(), 'Residual del ' || v_ref);
    end;
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id;
  return v_pedido;
end;
$$;

comment on function finalizar_despacho is
  'Cierra un pedido confirmado -> despachado con lo cargado hasta el momento (parcial o completo), genera el residual si corresponde. El residual hereda nro_remito_global del pedido padre (migración 38) y lo referencia por fecha/cantidad/remito, no por UUID (migración 46). nro_remito_global en sí sigue asignándose solo en registrar_carga_asfalto() (migración 36).';

revoke execute on function finalizar_despacho(uuid, boolean, date) from public, anon;
grant execute on function finalizar_despacho(uuid, boolean, date) to authenticated;
