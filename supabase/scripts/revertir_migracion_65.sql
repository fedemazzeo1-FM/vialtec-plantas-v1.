-- ============================================================================
-- Reversión de la migración 65 (solo si hiciera falta volver atrás).
-- Vuelve registrar_pesada_bascula, reasignar_vale_bascula y la vista de
-- Báscula a la versión del 2026-10-20 y borra lo nuevo.
-- OJO: si ya hay filas IMPRIMIR en plantas_auditoria, el CHECK viejo y el
-- borrado de la entidad 'impresion' fallan (la auditoría no se borra). En ese
-- caso dejar el CHECK y la entidad como están y revertir solo el resto.
-- Antes: bajar el frontend a la versión previa (usa las funciones nuevas).
-- ============================================================================

-- 1) Vista: vuelve el corte por día de Argentina
do $vista$
declare
  v_src   text := pg_get_viewdef('public.plantas_v_bascula_viva'::regclass);
  v_nueva text := $a$OVER (PARTITION BY COALESCE((pedido_id)::text, (obra_id)::text, 'sin-obra'::text), (date_trunc('day'::text, (fecha_pesada AT TIME ZONE 'America/Argentina/Buenos_Aires'::text))) ORDER BY fecha_pesada)$a$;
  v_ancla text := $b$OVER (PARTITION BY COALESCE(('p:'::text || (pedido_id)::text), ((('o:'::text || COALESCE((obra_id)::text, 'sin-obra'::text)) || ':'::text) || to_char((fecha_pesada AT TIME ZONE 'America/Argentina/Buenos_Aires'::text), 'YYYY-MM-DD'::text))) ORDER BY fecha_pesada)$b$;
begin
  if position(v_ancla in v_src) = 0 then
    raise exception 'REV65: la vista no tiene el acumulado de la migración 65';
  end if;
  execute 'create or replace view public.plantas_v_bascula_viva with (security_invoker = true) as '
    || replace(v_src, v_ancla, v_nueva);
end;
$vista$;

-- 2) reasignar_vale_bascula: saca el chequeo de pesaje cerrado
do $reasignar$
declare
  v_src   text := pg_get_functiondef('public.reasignar_vale_bascula(uuid,uuid,text)'::regprocedure);
  v_extra text := $a$  if v_destino.pesaje_cerrado_en is not null then
    raise exception 'El pedido elegido tiene el pesaje cerrado — un plantista o admin tiene que reabrirlo desde Pedidos.';
  end if;
$a$;
begin
  if position(v_extra in v_src) = 0 then
    raise exception 'REV65: reasignar_vale_bascula no tiene el chequeo de la migración 65';
  end if;
  execute replace(v_src, v_extra, '');
end;
$reasignar$;

-- 3) registrar_pesada_bascula: cuerpo previo (acumulado por día UTC, sin chequeo de estado)
create or replace function public.registrar_pesada_bascula(p_tipo_vale text, p_peso_bruto numeric, p_tara numeric, p_pedido_id uuid DEFAULT NULL::uuid, p_obra_id bigint DEFAULT NULL::bigint, p_patente text DEFAULT NULL::text, p_chofer text DEFAULT NULL::text, p_unidad text DEFAULT 'tn'::text, p_observaciones text DEFAULT NULL::text, p_fecha_pesada timestamp with time zone DEFAULT now(), p_material text DEFAULT NULL::text, p_proveedor text DEFAULT NULL::text, p_numero_remito text DEFAULT NULL::text, p_cantidad_remito numeric DEFAULT NULL::numeric, p_temperatura numeric DEFAULT NULL::numeric)
 RETURNS plantas_vales
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    if p_cantidad_remito is null or not (p_cantidad_remito > 0) then
      raise exception 'Un ingreso de áridos necesita la cantidad según remito (declarada por el proveedor), independiente del peso pesado.';
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
    tipo_vale, numero_vale, numero_vale_arido, pedido_id, obra_id, patente, chofer,
    peso_bruto, tara, peso_neto, unidad, acumulado_obra_tn, fecha_pesada, observaciones,
    temperatura, material, responsable_email
  ) values (
    p_tipo_vale,
    case when p_tipo_vale in ('asfalto', 'hormigon') then nextval('plantas_vales_numero_vale_seq') end,
    case when p_tipo_vale in ('ingreso_arido', 'egreso_arido') then nextval('plantas_vales_numero_arido_seq') end,
    p_pedido_id, v_obra_id, p_patente, p_chofer,
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
      p_material, p_proveedor, p_numero_remito, p_cantidad_remito, 'tn',
      'bascula', v_vale.id, p_fecha_pesada, p_observaciones
    )
    returning id into v_ingreso_id;

    v_material_id := plantas_buscar_material_id(p_material);
    if v_material_id is not null then
      perform plantas_aplicar_movimiento_stock(
        v_material_id, 'ingreso_proveedor', p_cantidad_remito * 1000,
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

  perform plantas_auditar_vale('CREAR', v_vale.id);

  return v_vale;
end;
$function$;

-- 4) Lo nuevo
drop function public.registrar_impresion(uuid, text, text, text);
drop function public.impresiones_del_vale(uuid);
drop function public.cerrar_pesaje_pedido(uuid);
drop function public.reabrir_pesaje_pedido(uuid, text);
drop function public.plantas_acumulado_asfalto(uuid, bigint, timestamptz);
alter table public.plantas_pedidos
  drop constraint plantas_pedidos_pesaje_cerrado_chk,
  drop column pesaje_cerrado_en,
  drop column pesaje_cerrado_por;

-- 5) Solo si no hay filas IMPRIMIR (ver nota arriba)
-- alter table public.plantas_auditoria drop constraint plantas_auditoria_tipo_accion_check;
-- alter table public.plantas_auditoria add constraint plantas_auditoria_tipo_accion_check
--   check (tipo_accion = any (array['CREAR', 'EDITAR', 'CAMBIAR_ESTADO', 'ANULAR', 'CORREGIR', 'REASIGNAR', 'ELIMINAR']));
-- delete from public.plantas_auditoria_entidades where modulo = 'bascula' and entidad = 'impresion';
