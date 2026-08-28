-- ============================================================================
-- Migración 10: Báscula Fase 1/2 — acumulado por pedido, remito duplicado,
-- egreso de áridos con obra_id (reemplaza destino texto libre)
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Origen: memory/relevamiento-sistema-viejo.md Etapa 3 + auditoría de código
-- de Báscula contra Logica sis. plantas v1.rtf/v2.rtf. Aprobado por Federico
-- (sesión 2026-08-28, "dale para adelante... Fase 1" y "Fase 2 ... Punto 8").
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) plantas_vales.destino: se elimina. El relevamiento en vivo confirmó que
--    "Vale Salida Áridos" en el legado usa un SELECT de obra (requerido), no
--    texto libre — se reemplaza por reusar plantas_vales.obra_id (ya existe,
--    misma columna que usa asfalto).
-- ----------------------------------------------------------------------------
alter table plantas_vales
  drop column if exists destino;

-- ----------------------------------------------------------------------------
-- 2) registrar_pesada_bascula — reemplazo completo:
--    a) Acumulado: agrupa por pedido_id si la pesada tiene pedido asociado,
--       y solo cae a agrupar por obra_id cuando NO hay pedido (Logica v1 §2.4
--       / v2 §6: "pedidoId === this vale's pedidoId (si existe) O bien
--       obra === ... (si no hay pedidoId)"). Antes agrupaba siempre por
--       obra_id, mezclando el acumulado de dos pedidos distintos de la misma
--       obra despachándose en paralelo.
--    b) Ingreso de áridos: valida que el N° de remito no esté ya usado en
--       plantas_ingresos antes de guardar (Logica v1 §2.5).
--    c) Egreso de áridos: usa obra_id (p_obra_id, ya existía como parámetro)
--       en vez de un p_destino de texto libre — se elimina ese parámetro.
--       Ahora exige obra_id no nulo para egreso_arido (antes solo exigía
--       material).
-- ----------------------------------------------------------------------------
drop function if exists registrar_pesada_bascula(
  text, numeric, numeric, uuid, bigint, text, text, text, text, timestamptz, text, text, text, numeric, numeric, text
);

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
    select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
    if not found then
      raise exception 'El pedido % no existe.', p_pedido_id;
    end if;
  end if;

  v_obra_id := coalesce(p_obra_id, v_pedido.obra_id);
  v_neto_tn := case when p_unidad = 'kg' then v_peso_neto / 1000 else v_peso_neto end;

  -- Validaciones específicas por tipo, ANTES de insertar nada.
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

  -- Acumulado dinámico (foto informativa al momento de pesar — el imprimible
  -- y el historial lo recalculan de nuevo al consultar, nunca leen esta
  -- columna como fuente de verdad, ver bascula.service.js#obtenerAcumuladoHastaFecha).
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

  if p_pedido_id is not null and p_tipo_vale = 'asfalto' then
    update plantas_pedidos
      set cantidad_despachada = coalesce(v_pedido.cantidad_despachada, 0) + v_neto_tn,
          estado = case
            when coalesce(v_pedido.cantidad_despachada, 0) + v_neto_tn >= v_pedido.cantidad_solicitada
            then 'despachado' else estado end
      where id = p_pedido_id;
  end if;

  if p_tipo_vale = 'ingreso_arido' then
    insert into plantas_ingresos (
      material, proveedor, numero_remito, cantidad, unidad, origen, vale_id, fecha_ingreso, observaciones
    ) values (
      p_material, p_proveedor, p_numero_remito, coalesce(p_cantidad_remito, v_neto_tn), 'tn',
      'bascula', v_vale.id, p_fecha_pesada, p_observaciones
    );
  end if;

  -- TODO(stock): acá van los movimientos de stock (ingreso Y egreso de
  -- áridos) cuando exista plantas_stock.

  return v_vale;
end;
$$;

comment on function registrar_pesada_bascula is
  'Registra un vale de báscula (asfalto/hormigón/ingreso o egreso de árido) y actualiza el pedido asociado de forma atómica. Migración 10: acumulado agrupado por pedido_id cuando existe (antes solo por obra_id), valida remito duplicado en ingreso, egreso usa obra_id (no destino texto libre).';

revoke execute on function registrar_pesada_bascula(text, numeric, numeric, uuid, bigint, text, text, text, text, timestamptz, text, text, text, numeric, numeric) from public;
grant execute on function registrar_pesada_bascula(text, numeric, numeric, uuid, bigint, text, text, text, text, timestamptz, text, text, text, numeric, numeric) to authenticated;
