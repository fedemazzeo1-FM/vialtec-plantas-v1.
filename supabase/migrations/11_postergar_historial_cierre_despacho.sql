-- ============================================================================
-- Migración 11: Pedidos Fase 1 — postergar, historial, cierre parcial +
-- pedido residual del despacho
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Origen: memory/relevamiento-sistema-viejo.md + auditoría de Pedidos contra
-- Logica sis. plantas v1.rtf/v2.rtf. Aprobado por Federico (sesión 2026-08-28).
--
-- Decisión de roles para esta migración (Federico, mismo mensaje de
-- aprobación): "Roles/Visibilidad pospuestos para la etapa global de
-- seguridad." Por eso postergar_pedido() NO valida rol (mismo criterio hoy
-- que confirmarPedido()/cancelarPedido(), que tampoco lo hacen — son updates
-- planos sin RPC). finalizar_despacho() SÍ valida rol porque extiende
-- registrar_carga_asfalto/hormigon, que YA tenían ese check desde la
-- migración 07 — no es una restricción nueva, es no aflojar una que ya
-- existía.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) postergar_pedido — solicitado|confirmado -> postergado, guarda
--    fecha_programada_anterior/nueva en el historial (Logica sis. plantas
--    v1.rtf §2.2, §5: "Postergado: se mueve a otra fecha... el historial
--    guarda fecha original y nueva"). Fecha y motivo opcionales, igual que
--    el modal real (memory/relevamiento-sistema-viejo.md Etapa 3).
-- ----------------------------------------------------------------------------
create or replace function postergar_pedido(
  p_pedido_id   uuid,
  p_fecha_nueva date default null,
  p_motivo      text default null
)
returns plantas_pedidos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido        plantas_pedidos;
  v_fecha_anterior date;
begin
  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  -- 'postergado' incluido a propósito: re-postergar un pedido ya postergado
  -- es una transición válida (memory/business-rules.md: postergado ->
  -- confirmado -> despachado, y la UI permite volver a postergarlo antes de
  -- confirmarlo de nuevo).
  if v_pedido.estado not in ('solicitado', 'confirmado', 'postergado') then
    raise exception 'Solo se puede postergar un pedido solicitado, confirmado o ya postergado (estado actual: %).', v_pedido.estado;
  end if;

  v_fecha_anterior := v_pedido.fecha_programada;

  update plantas_pedidos
    set estado = 'postergado',
        fecha_programada = coalesce(p_fecha_nueva, fecha_programada),
        motivo = p_motivo,
        motivo_en = case when p_motivo is not null then now() else motivo_en end
    where id = p_pedido_id
    returning * into v_pedido;

  insert into plantas_pedidos_historial (
    pedido_id, estado, fecha_evento, fecha_programada_anterior, fecha_programada_nueva, usuario_id, motivo
  ) values (
    p_pedido_id, 'postergado', now(), v_fecha_anterior, p_fecha_nueva, auth.uid(), p_motivo
  );

  return v_pedido;
end;
$$;

comment on function postergar_pedido is
  'Postergar un pedido solicitado/confirmado/ya postergado (re-postergar): cambia estado y opcionalmente fecha_programada, registra el evento en plantas_pedidos_historial con la fecha anterior y la nueva.';

revoke execute on function postergar_pedido(uuid, date, text) from public;
grant execute on function postergar_pedido(uuid, date, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 2) finalizar_despacho — cierra el pedido como 'despachado' con lo cargado
--    hasta ahora (aunque sea menos que cantidad_solicitada — Logica sis.
--    plantas v1.rtf §2.2: "cantidadReal = suma de las cargas", el pedido
--    pasa a despachado igual). Si p_dividir=true y queda saldo, crea
--    automáticamente un pedido nuevo 'confirmado' por el residual, en la
--    fecha indicada ("dividir pedido... nuevo pedido confirmado con la
--    cantidad residual para una fecha futura").
--
--    NOTA: a partir de esta migración, registrar_carga_asfalto y
--    registrar_carga_hormigon YA NO cierran el pedido solas al llegar al
--    100% — solo acumulan cantidad_despachada. finalizar_despacho() es el
--    ÚNICO lugar que hace la transición confirmado -> despachado, se llama
--    siempre al terminar de cargar (sea 1 carga o varias, llegue o no al
--    total) — ver useDespachoAsfalto.js / useCargaHormigon.js.
-- ----------------------------------------------------------------------------
create or replace function finalizar_despacho(
  p_pedido_id      uuid,
  p_dividir        boolean default false,
  p_fecha_residual date default null
)
returns plantas_pedidos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol      text;
  v_pedido   plantas_pedidos;
  v_residual numeric;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista', 'plantista_hormigon') then
    raise exception 'Tu rol (%) no puede finalizar un despacho.', coalesce(v_rol, 'sin rol asignado');
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
        tipo_pedido, cliente_externo, encargado, ubicacion, observaciones
      ) values (
        v_pedido.obra_id, v_pedido.formula_id, v_pedido.tipo, v_residual, p_fecha_residual, 'confirmado',
        v_pedido.tipo_pedido, v_pedido.cliente_externo, v_pedido.encargado, v_pedido.ubicacion,
        'Pedido residual generado automáticamente al dividir el despacho del ' || v_pedido.id::text
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
  'Cierra un pedido confirmado como despachado con lo cargado hasta el momento (parcial o completo), y opcionalmente crea un pedido residual confirmado por el saldo. Única función que transiciona confirmado->despachado desde la migración 11.';

revoke execute on function finalizar_despacho(uuid, boolean, date) from public;
grant execute on function finalizar_despacho(uuid, boolean, date) to authenticated;

-- ----------------------------------------------------------------------------
-- 3) registrar_carga_asfalto / registrar_carga_hormigon: se saca el cierre
--    automático a 'despachado' al llegar al 100% — ahora solo acumulan
--    cantidad_despachada. El cierre lo hace SIEMPRE finalizar_despacho().
-- ----------------------------------------------------------------------------
create or replace function registrar_carga_asfalto(
  p_pedido_id            uuid,
  p_numero_vale          text,
  p_cantidad_tn          numeric,
  p_patente              text default null,
  p_fecha_carga          timestamptz default now(),
  p_observaciones        text default null,
  p_numero_remito_global text default null
)
returns plantas_cargas_asfalto
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol    text;
  v_pedido plantas_pedidos;
  v_carga  plantas_cargas_asfalto;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista') then
    raise exception 'Tu rol (%) no puede registrar cargas de asfalto.', coalesce(v_rol, 'sin rol asignado');
  end if;

  if not (p_cantidad_tn > 0) then
    raise exception 'cantidad_tn debe ser mayor a 0';
  end if;
  if p_numero_vale is null or btrim(p_numero_vale) = '' then
    raise exception 'numero_vale es obligatorio por carga';
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.tipo <> 'asfalto' then
    raise exception 'El pedido no es de asfalto.';
  end if;
  if v_pedido.estado <> 'confirmado' then
    raise exception 'El pedido tiene que estar confirmado.';
  end if;

  insert into plantas_cargas_asfalto (
    pedido_id, obra_id, numero_vale, cantidad_tn, patente, fecha_carga, observaciones
  ) values (
    v_pedido.id, v_pedido.obra_id, btrim(p_numero_vale), p_cantidad_tn, p_patente, p_fecha_carga, p_observaciones
  )
  returning * into v_carga;

  -- Ya no cierra el pedido acá — ver finalizar_despacho() (migración 11).
  update plantas_pedidos
    set cantidad_despachada = coalesce(v_pedido.cantidad_despachada, 0) + p_cantidad_tn,
        nro_remito_global = coalesce(v_pedido.nro_remito_global, p_numero_remito_global)
    where id = p_pedido_id;

  return v_carga;
end;
$$;

comment on function registrar_carga_asfalto is
  'Registra una carga de asfalto (vale por camión) y acumula cantidad_despachada de forma atómica. Desde la migración 11 NO cierra el pedido — eso lo hace finalizar_despacho().';

create or replace function registrar_carga_hormigon(
  p_pedido_id       uuid,
  p_numero_remito   text,
  p_volumen_m3      numeric,
  p_patente_mixer   text default null,
  p_chofer          text default null,
  p_fecha_carga     timestamptz default now(),
  p_observaciones   text default null
)
returns plantas_cargas_hormigon
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol    text;
  v_pedido plantas_pedidos;
  v_carga  plantas_cargas_hormigon;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista', 'plantista_hormigon') then
    raise exception 'Tu rol (%) no puede registrar cargas de hormigón.', coalesce(v_rol, 'sin rol asignado');
  end if;

  if not (p_volumen_m3 > 0) then
    raise exception 'volumen_m3 debe ser mayor a 0';
  end if;
  if p_numero_remito is null or btrim(p_numero_remito) = '' then
    raise exception 'numero_remito es obligatorio';
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.tipo <> 'hormigon' then
    raise exception 'El pedido no es de hormigón.';
  end if;
  if v_pedido.estado <> 'confirmado' then
    raise exception 'El pedido tiene que estar confirmado.';
  end if;

  insert into plantas_cargas_hormigon (
    pedido_id, obra_id, numero_remito, volumen_m3, patente_mixer, chofer, fecha_carga, observaciones
  ) values (
    v_pedido.id, v_pedido.obra_id, btrim(p_numero_remito), p_volumen_m3, p_patente_mixer, p_chofer, p_fecha_carga, p_observaciones
  )
  returning * into v_carga;

  -- Ya no cierra el pedido acá — ver finalizar_despacho() (migración 11).
  update plantas_pedidos
    set cantidad_despachada = coalesce(v_pedido.cantidad_despachada, 0) + p_volumen_m3
    where id = p_pedido_id;

  return v_carga;
end;
$$;

comment on function registrar_carga_hormigon is
  'Registra una carga de hormigón (remito por mixer) y acumula cantidad_despachada de forma atómica. Desde la migración 11 NO cierra el pedido — eso lo hace finalizar_despacho().';
