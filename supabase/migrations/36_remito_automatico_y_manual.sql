-- ============================================================================
-- Migración 36: Numeración automática de remitos + Remito Manual/Blanco
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Pedido explícito de Federico (2026-09-09), 2 mensajes seguidos:
--   1. El remito de un despacho de asfalto (plantas_pedidos.nro_remito_global)
--      dejaba de ser un campo manual/opcional que el operador tipeaba en el
--      modal de despacho — pasa a ser AUTOMÁTICO. Aclaración explícita de
--      Federico sobre CUÁNDO se asigna: es 1 solo N° de remito POR PEDIDO,
--      no por pesada — si un pedido tiene 10 pesadas, las 10 comparten el
--      mismo N° de remito, y como Báscula permite imprimir el remito desde
--      CUALQUIER pesada (no solo la última), el número tiene que quedar
--      asignado desde la PRIMERA carga/pesada del pedido, no recién al
--      cerrar el despacho — si no, imprimir el remito a mitad del día
--      (antes de la pesada 10) mostraría "—" en vez del número real.
--      Por eso el auto-asignado va en registrar_carga_asfalto() (primera
--      carga), no en finalizar_despacho(). Arranca una secuencia NUEVA
--      ("arrancalo de cero a partir de ahora") — no se renumeran los
--      despachos ya cerrados (quedan con el valor que tengan, incluido null
--      si nunca se completó a mano).
--   2. Nueva funcionalidad "Remito en Blanco / Manual": para envíos de
--      materiales a obra u otros movimientos internos que no pasan por un
--      pedido — consume Y CONTINÚA la misma secuencia correlativa de arriba
--      (pedido explícito: "debe consumir y continuar la misma secuencia...
--      utilizada para los remitos de asfalto").
--
-- Fuera de alcance a propósito (no lo pidió en estos 2 mensajes): el N° de
-- remito POR CARGA de hormigón (plantas_cargas_hormigon.numero_remito) sigue
-- siendo manual — ahí "el remito ya es por carga" (cada mixer = su propio
-- remito físico que trae el chofer), no un concepto de secuencia única del
-- sistema como el de asfalto. Si Federico pide lo mismo para hormigón, es
-- una migración aparte sobre esa tabla.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Secuencia única de remitos — arranca en 1 ("arrancar de cero" se
--    interpreta como "numeración nueva, sin continuar ningún número viejo",
--    no como que el primer remito real diga literalmente "0" — un remito
--    fiscal numerado "0" no es estándar. Si Federico quería el 0 literal,
--    es un `alter sequence plantas_remitos_numero_seq restart with 0;` de
--    un renglón, avisar y lo ajusto).
-- ----------------------------------------------------------------------------
create sequence if not exists plantas_remitos_numero_seq start 1;

-- ----------------------------------------------------------------------------
-- 2) registrar_carga_asfalto — deja de aceptar un remito tipeado a mano
--    (p_numero_remito_global sale de la firma). Sigue siendo acá (no en
--    finalizar_despacho()) donde se asigna el N° de remito, automáticamente,
--    la PRIMERA vez que se registra una carga del pedido — coalesce evita
--    reasignar en la 2ª/3ª/... carga. Ver nota de alcance arriba (por qué
--    tiene que ser en la primera carga y no al cerrar).
-- ----------------------------------------------------------------------------

drop function if exists registrar_carga_asfalto(uuid, text, numeric, text, timestamptz, text, text);

create function registrar_carga_asfalto(
  p_pedido_id     uuid,
  p_numero_vale   text,
  p_cantidad_tn   numeric,
  p_patente       text default null,
  p_fecha_carga   timestamptz default now(),
  p_observaciones text default null
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

  -- Ya no cierra el pedido acá (finalizar_despacho() lo hace). nro_remito_global
  -- se asigna automáticamente, UNA sola vez por pedido (coalesce: no pisa si
  -- ya lo trae una carga anterior del mismo despacho) — así cualquier pesada,
  -- sea la 1ª o la 10ª, ve/imprime siempre el mismo número real.
  update plantas_pedidos
    set cantidad_despachada = coalesce(v_pedido.cantidad_despachada, 0) + p_cantidad_tn,
        nro_remito_global   = coalesce(v_pedido.nro_remito_global, nextval('plantas_remitos_numero_seq')::text)
    where id = p_pedido_id;

  return v_carga;
end;
$$;

comment on function registrar_carga_asfalto is
  'Registra una carga de asfalto (vale por camión) y acumula cantidad_despachada de forma atómica. No cierra el pedido (finalizar_despacho() lo hace). Asigna nro_remito_global automáticamente en la primera carga del pedido (plantas_remitos_numero_seq, migración 36) — ya no se tipea a mano, y es el mismo número para todas las cargas/pesadas del pedido.';

revoke execute on function registrar_carga_asfalto(uuid, text, numeric, text, timestamptz, text) from public;
grant execute on function registrar_carga_asfalto(uuid, text, numeric, text, timestamptz, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 3) finalizar_despacho — SIN CAMBIOS de comportamiento respecto de la
--    migración 26 (se re-crea igual, solo para dejar el comentario
--    actualizado): nro_remito_global YA quedó asignado desde la primera
--    carga (registrar_carga_asfalto(), punto 2) — cerrar el despacho no
--    tiene que tocarlo.
-- ----------------------------------------------------------------------------

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
  'Cierra un pedido confirmado -> despachado con lo cargado hasta el momento (parcial o completo), genera el residual si corresponde. nro_remito_global (asfalto) NO se toca acá — ya quedó asignado automáticamente desde la primera carga (registrar_carga_asfalto(), migración 36).';

revoke execute on function finalizar_despacho(uuid, boolean, date) from public;
grant execute on function finalizar_despacho(uuid, boolean, date) to authenticated;

-- ----------------------------------------------------------------------------
-- 4) plantas_remitos_manuales — "Remito en Blanco / Manual": envíos de
--    materiales a obra u otros movimientos internos que no pasan por un
--    pedido. Nunca se edita ni se borra (mismo criterio de auditoría que el
--    resto del sistema — un remito manual mal cargado se anula creando uno
--    nuevo con una nota, no se corrige el original).
-- ----------------------------------------------------------------------------
create table if not exists plantas_remitos_manuales (
  id            uuid primary key default gen_random_uuid(),
  numero_remito bigint not null unique default nextval('plantas_remitos_numero_seq'),
  fecha         date not null default current_date,
  descripcion   text not null,
  destino       text,
  patente       text,
  transportista text,
  creado_por    text,
  created_at    timestamptz not null default now()
);

comment on table plantas_remitos_manuales is
  'Remitos "en blanco"/manuales (envío de materiales a obra u otro movimiento interno sin pedido asociado) — numero_remito sale de la misma secuencia que plantas_pedidos.nro_remito_global (asfalto), continuidad correlativa real entre ambos usos. Solo se crea vía generar_remito_manual() (RPC), nunca INSERT directo — la tabla no tiene policy de insert/update/delete para authenticated a propósito.';

create index if not exists idx_plantas_remitos_manuales_fecha on plantas_remitos_manuales (fecha);

alter table plantas_remitos_manuales enable row level security;

create policy "plantas_remitos_manuales: leer" on plantas_remitos_manuales
  for select to authenticated using (true);

-- Sin policy de insert/update/delete para `authenticated`: la única vía de
-- escritura es la RPC de abajo (SECURITY DEFINER, corre como owner y
-- bypassea RLS) — mismo patrón de "funnel único" que el resto de las
-- acciones auditables del sistema (crear_pedido, registrar_pesada_bascula,
-- etc.), evita que alguien inserte un remito manual salteando el chequeo de
-- rol o pisando la numeración.

create function generar_remito_manual(
  p_descripcion   text,
  p_destino       text default null,
  p_patente       text default null,
  p_transportista text default null,
  p_fecha         date default current_date
)
returns plantas_remitos_manuales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_remito plantas_remitos_manuales;
begin
  if not plantas_tiene_permiso('despachos', 'aprobar') then
    raise exception 'Tu rol (%) no puede generar un remito manual.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  if p_descripcion is null or btrim(p_descripcion) = '' then
    raise exception 'La descripción es obligatoria.';
  end if;

  insert into plantas_remitos_manuales (descripcion, destino, patente, transportista, fecha, creado_por)
  values (btrim(p_descripcion), nullif(btrim(coalesce(p_destino, '')), ''), nullif(btrim(coalesce(p_patente, '')), ''),
          nullif(btrim(coalesce(p_transportista, '')), ''), coalesce(p_fecha, current_date), auth.email())
  returning * into v_remito;

  return v_remito;
end;
$$;

comment on function generar_remito_manual is
  'Genera un remito "en blanco"/manual (sin pedido asociado) con numero_remito automático, misma secuencia que los remitos de asfalto (plantas_remitos_numero_seq). Solo admin/plantista (mismo permiso que finalizar_despacho).';

revoke execute on function generar_remito_manual(text, text, text, text, date) from public;
grant execute on function generar_remito_manual(text, text, text, text, date) to authenticated;
