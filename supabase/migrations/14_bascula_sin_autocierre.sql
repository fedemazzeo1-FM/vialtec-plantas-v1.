-- ============================================================================
-- Migración 14: Báscula ya no cierra pedidos (hallazgo de la migración 13,
-- corregido por decisión de Federico, sesión 2026-08-31)
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Hallazgo: registrar_pesada_bascula() (migración 09, nunca tocada por la
-- migración 11 que estableció que SOLO finalizar_despacho() cierra un
-- pedido) seguía incrementando plantas_pedidos.cantidad_despachada y
-- pasando estado a 'despachado' cuando el acumulado pesado alcanzaba
-- cantidad_solicitada. Esto contradecía el principio ya fijado
-- ("Pedidos cierra, Báscula audita" — memory/business-rules.md) y, peor:
-- con el descuento de stock ya enganchado a finalizar_despacho()/
-- corregir_despacho() (migración 13), un pedido cerrado por esta vía NUNCA
-- descontaba stock.
--
-- Fix: se saca por completo el bloque que tocaba plantas_pedidos desde acá
-- (ni cantidad_despachada ni estado). Báscula (plantas_vales) queda 100%
-- como lo que siempre debió ser — detalle auditable de pesadas, sin efecto
-- sobre el pedido. El acumulado impreso en el vale (acumulado_obra_tn) no
-- cambia: se calcula sumando plantas_vales, no lee cantidad_despachada.
--
-- Cierre real: exclusivamente vía Pedidos — registrar_carga_asfalto()
-- (acumula cantidad_despachada) + finalizar_despacho() (cierra el pedido y
-- descuenta stock). Un pedido que solo se pesó en Báscula y nunca se
-- "Registró despacho" en Pedidos queda 'confirmado' indefinidamente hasta
-- que alguien lo cierre desde ahí — es el comportamiento correcto según el
-- principio fijado, no un bug.
-- ============================================================================

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

  -- Ya no se pide "for update": esta función no escribe plantas_pedidos
  -- (migración 14) — solo lee obra_id como default. Sin lock innecesario.
  if p_pedido_id is not null then
    select * into v_pedido from plantas_pedidos where id = p_pedido_id;
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
    temperatura, material
  ) values (
    p_tipo_vale, p_pedido_id, v_obra_id, p_patente, p_chofer,
    p_peso_bruto, p_tara, v_peso_neto, p_unidad, v_acumulado_tn, p_fecha_pesada, p_observaciones,
    p_temperatura,
    case when p_tipo_vale = 'egreso_arido' then p_material else null end
  )
  returning * into v_vale;

  -- (migración 14) Se elimina el bloque que acá tocaba plantas_pedidos
  -- (cantidad_despachada + estado='despachado'). El cierre del pedido y el
  -- descuento de stock son EXCLUSIVAMENTE de Pedidos —
  -- registrar_carga_asfalto() + finalizar_despacho() (migraciones 09/11/13).
  -- Báscula queda solo como detalle auditable, sin efecto sobre el pedido.

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
  'Registra un vale de báscula (asfalto/hormigón/ingreso o egreso de árido) y mueve stock en ingreso_arido/egreso_arido (migración 13). Desde la migración 14 NO toca plantas_pedidos para asfalto — ni cantidad_despachada ni estado: Báscula es auditoría, Pedidos (registrar_carga_asfalto + finalizar_despacho) es quien acumula y cierra.';

revoke execute on function registrar_pesada_bascula(text, numeric, numeric, uuid, bigint, text, text, text, text, timestamptz, text, text, text, numeric, numeric) from public;
grant execute on function registrar_pesada_bascula(text, numeric, numeric, uuid, bigint, text, text, text, text, timestamptz, text, text, text, numeric, numeric) to authenticated;
