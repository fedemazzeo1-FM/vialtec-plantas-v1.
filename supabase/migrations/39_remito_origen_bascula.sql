-- ============================================================================
-- Migración 39: el N° de remito de asfalto (plantas_pedidos.nro_remito_global)
-- se origina en BÁSCULA (primera pesada), no en Pedidos (primera carga)
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Pedido explícito de Federico ("Atención Code", 2026-09-16): la migración 36
-- (2026-09-09) había puesto la asignación automática del remito en
-- registrar_carga_asfalto() — el paso que hace el PLANTISTA en Pedidos al
-- "Registrar despacho". Federico aclara que eso no refleja la operativa real:
-- el remito se origina en BÁSCULA, cuando el BALANCERO procesa la pesada
-- (y lo imprime ahí mismo) — recién después el plantista usa ese remito ya
-- impreso para concretar el despacho en Pedidos. Con el esquema viejo, si el
-- balancero pesaba e imprimía el remito ANTES de que el plantista cargara
-- algo en Pedidos (el orden real, casi siempre), el remito salía sin número
-- ("—") porque todavía no existía ninguna carga registrada del lado de
-- Pedidos.
--
-- Fix: se mueve el coalesce+nextval de registrar_carga_asfalto() (Pedidos) a
-- registrar_pesada_bascula() (Báscula), tipo_vale='asfalto' con pedido_id.
-- Se mantiene exactamente el mismo criterio de "una sola vez por pedido"
-- (coalesce sobre nro_remito_global, no lo pisa si una pesada anterior del
-- mismo pedido ya lo asignó) — mismo comportamiento de fondo (business-rules:
-- 1 remito por pedido, compartido por todas sus pesadas/cargas), solo cambia
-- EN QUÉ MÓDULO se dispara la primera vez.
--
-- registrar_carga_asfalto() (Pedidos) deja de tocar nro_remito_global —
-- pasa a ser puramente de LECTURA desde ese lado (lo completa Báscula, el
-- plantista ya lo recibe impreso en papel). Si un pedido llegara a
-- despacharse en Pedidos sin ninguna pesada previa en Báscula (caso límite,
-- no el flujo esperado), nro_remito_global queda null — mismo criterio
-- "informativo, no bloqueante" que ya usa el resto del sistema (alertas de
-- stock, business-rules.md), no se agrega ninguna validación dura nueva acá.
--
-- Se agrega `for update` al lock del pedido en registrar_pesada_bascula()
-- (no lo tenía, porque hasta ahora esa función solo LEÍA el pedido para
-- obra_id/acumulado) — necesario ahora que puede ESCRIBIR nro_remito_global,
-- para evitar que dos puertas de báscula pesando en simultáneo el mismo
-- pedido (memory/business-rules.md, "Despachos simultáneos") le asignen dos
-- números de la secuencia en una carrera — mismo patrón que ya usa
-- registrar_carga_asfalto()/registrar_carga_hormigon() desde la Fase 1
-- (memory/modules-status.md).
--
-- finalizar_despacho() (migración 38, residual hereda nro_remito_global del
-- padre) y generar_remito_manual()/plantas_remitos_manuales (migración 36-37,
-- misma secuencia) NO cambian — son consumidores/continuadores de la misma
-- secuencia, no su origen.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) registrar_pesada_bascula — ahora asigna nro_remito_global (asfalto, con
--    pedido_id) en la primera pesada del pedido. Firma sin cambios respecto
--    de la migración 20 (solo se agrega `for update` al select del pedido y
--    el UPDATE de remito dentro del bloque ya existente de tipo asfalto).
-- ----------------------------------------------------------------------------
create or replace function registrar_pesada_bascula(
  p_tipo_vale        text,
  p_peso_bruto       numeric,
  p_tara             numeric,
  p_pedido_id        uuid default null,
  p_obra_id          bigint default null,
  p_patente          text default null,
  p_chofer           text default null,
  p_unidad           text default 'tn',
  p_observaciones    text default null,
  p_fecha_pesada     timestamptz default now(),
  p_material         text default null,
  p_proveedor        text default null,
  p_numero_remito    text default null,
  p_cantidad_remito  numeric default null,
  p_temperatura      numeric default null
)
returns plantas_vales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol           text;
  v_pedido        plantas_pedidos;
  v_peso_neto     numeric;
  v_obra_id       bigint;
  v_neto_tn       numeric;
  v_acumulado_tn  numeric;
  v_vale          plantas_vales;
  v_ingreso_id    uuid;
  v_material_id   uuid;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista', 'balancero') then
    raise exception 'Tu rol (%) no puede registrar pesadas de báscula.', coalesce(v_rol, 'sin rol asignado');
  end if;

  if not (p_peso_bruto > 0) then
    raise exception 'peso_bruto debe ser mayor a 0';
  end if;
  if not (p_tara >= 0) then
    raise exception 'tara no puede ser negativa';
  end if;
  if not (p_peso_bruto > p_tara) then
    raise exception 'el peso bruto debe ser mayor que la tara';
  end if;

  v_peso_neto := p_peso_bruto - p_tara;

  if p_pedido_id is not null then
    -- `for update`: nuevo desde esta migración — antes esta función solo
    -- LEÍA el pedido (obra_id/acumulado), ahora también puede escribir
    -- nro_remito_global (ver bloque asfalto más abajo), así que necesita el
    -- mismo lock de fila que ya usa registrar_carga_asfalto() para evitar
    -- que dos pesadas simultáneas del mismo pedido se pisen la asignación.
    select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
    if not found then
      raise exception 'El pedido % no existe.', p_pedido_id;
    end if;
  end if;

  v_obra_id := coalesce(p_obra_id, v_pedido.obra_id);
  v_neto_tn := case when p_unidad = 'kg' then v_peso_neto / 1000 else v_peso_neto end;

  if p_tipo_vale = 'ingreso_arido' then
    if p_material is null or p_proveedor is null then
      raise exception 'Un ingreso de áridos necesita material y proveedor.';
    end if;
    if p_numero_remito is not null and btrim(p_numero_remito) <> ''
       and exists (select 1 from plantas_ingresos where numero_remito = btrim(p_numero_remito)) then
      raise exception 'Ya existe un ingreso registrado con el remito %.', p_numero_remito;
    end if;
  end if;

  if p_tipo_vale = 'egreso_arido' then
    if p_material is null or btrim(p_material) = '' then
      raise exception 'Un egreso de áridos necesita material.';
    end if;
    if v_obra_id is null then
      raise exception 'Un egreso de áridos necesita la obra de destino.';
    end if;
  end if;

  if p_tipo_vale = 'asfalto' then
    if p_pedido_id is not null then
      select coalesce(sum(case when unidad = 'kg' then peso_neto / 1000 else peso_neto end), 0)
        into v_acumulado_tn
        from plantas_vales
        where pedido_id = p_pedido_id
          and tipo_vale = 'asfalto'
          and fecha_pesada >= date_trunc('day', p_fecha_pesada)
          and fecha_pesada <= p_fecha_pesada;

      -- Origen del remito (migración 39): se asigna acá, en la PRIMERA
      -- pesada del pedido en Báscula — no en Pedidos. Coalesce: si una
      -- pesada anterior del mismo pedido ya lo asignó, no lo pisa (mismo
      -- número para todas las pesadas/cargas del pedido, business-rules.md).
      update plantas_pedidos
        set nro_remito_global = coalesce(nro_remito_global, nextval('plantas_remitos_numero_seq')::text)
        where id = p_pedido_id;
    elsif v_obra_id is not null then
      select coalesce(sum(case when unidad = 'kg' then peso_neto / 1000 else peso_neto end), 0)
        into v_acumulado_tn
        from plantas_vales
        where obra_id = v_obra_id
          and tipo_vale = 'asfalto'
          and fecha_pesada >= date_trunc('day', p_fecha_pesada)
          and fecha_pesada <= p_fecha_pesada;
    else
      v_acumulado_tn := 0;
    end if;
    v_acumulado_tn := coalesce(v_acumulado_tn, 0) + v_neto_tn;
  end if;

  insert into plantas_vales (
    tipo_vale, pedido_id, obra_id, patente, chofer,
    peso_bruto, tara, peso_neto, unidad, acumulado_obra_tn, fecha_pesada, observaciones,
    temperatura, material, responsable_email
  ) values (
    p_tipo_vale, p_pedido_id, v_obra_id, p_patente, p_chofer,
    p_peso_bruto, p_tara, v_peso_neto, p_unidad, v_acumulado_tn, p_fecha_pesada, p_observaciones,
    p_temperatura,
    case when p_tipo_vale = 'egreso_arido' then p_material else null end,
    auth.email()
  )
  returning * into v_vale;

  if p_tipo_vale = 'ingreso_arido' then
    insert into plantas_ingresos (
      material, proveedor, numero_remito, cantidad, unidad, origen, vale_id, fecha_ingreso, observaciones
    ) values (
      p_material, p_proveedor, p_numero_remito, coalesce(p_cantidad_remito, v_neto_tn), 'tn',
      'bascula', v_vale.id, p_fecha_pesada, p_observaciones
    )
    returning id into v_ingreso_id;

    v_material_id := plantas_buscar_material_id(p_material);
    if v_material_id is not null then
      perform plantas_aplicar_movimiento_stock(
        v_material_id, 'ingreso_proveedor', coalesce(p_cantidad_remito, v_neto_tn) * 1000,
        p_proveedor, p_numero_remito, null, v_vale.id, v_ingreso_id, null
      );
    end if;
  end if;

  if p_tipo_vale = 'egreso_arido' then
    v_material_id := plantas_buscar_material_id(p_material);
    if v_material_id is not null then
      perform plantas_aplicar_movimiento_stock(
        v_material_id, 'egreso_arido', -(v_neto_tn * 1000),
        null, null, null, v_vale.id, null, p_observaciones
      );
    end if;
  end if;

  return v_vale;
end;
$$;

comment on function registrar_pesada_bascula is
  'Registra un vale de báscula (asfalto/hormigón/ingreso o egreso de árido), mueve stock en ingreso_arido/egreso_arido (migración 13) y captura responsable_email vía auth.email() (migración 20). Para asfalto con pedido_id, asigna nro_remito_global en la PRIMERA pesada del pedido (migración 39, coalesce — no se reasigna en pesadas siguientes del mismo pedido). Fuera de eso, sigue sin tocar plantas_pedidos: cantidad_despachada/estado siguen siendo exclusivos de Pedidos (registrar_carga_asfalto + finalizar_despacho) — Báscula es el origen del remito y la auditoría del pesaje, no la fuente de verdad del total despachado (memory/business-rules.md).';

-- ----------------------------------------------------------------------------
-- 2) registrar_carga_asfalto — deja de asignar nro_remito_global (eso ahora
--    lo hace registrar_pesada_bascula, punto 1). Firma sin cambios respecto
--    de la migración 36. Si el pedido llega acá sin remito asignado todavía
--    (caso límite: se despachó sin pasar antes por Báscula), queda null —
--    mismo criterio "informativo, no bloqueante" del resto del sistema, sin
--    validación dura nueva.
-- ----------------------------------------------------------------------------
create or replace function registrar_carga_asfalto(
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

  -- Ya no cierra el pedido acá (finalizar_despacho() lo hace) NI asigna
  -- nro_remito_global (migración 39: eso lo hace registrar_pesada_bascula,
  -- en Báscula, en la primera pesada del pedido) — acá solo se acumula
  -- cantidad_despachada.
  update plantas_pedidos
    set cantidad_despachada = coalesce(v_pedido.cantidad_despachada, 0) + p_cantidad_tn
    where id = p_pedido_id;

  return v_carga;
end;
$$;

comment on function registrar_carga_asfalto is
  'Registra una carga de asfalto (vale por camión) y acumula cantidad_despachada de forma atómica. No cierra el pedido (finalizar_despacho() lo hace) ni asigna nro_remito_global (migración 39: se origina en Báscula, registrar_pesada_bascula, en la primera pesada del pedido — acá solo se lee/hereda, nunca se genera).';

revoke execute on function registrar_carga_asfalto(uuid, text, numeric, text, timestamptz, text) from public;
grant execute on function registrar_carga_asfalto(uuid, text, numeric, text, timestamptz, text) to authenticated;
