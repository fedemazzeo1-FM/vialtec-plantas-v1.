-- ============================================================================
-- Migración 44: "Cant. s/Remito" deja de duplicar el peso pesado en ingresos
-- de áridos (Báscula)
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Bug reportado por Federico (2026-09-22): al registrar un ingreso de
-- proveedores, "Cant. s/Remito" terminaba siendo igual al peso neto/bruto
-- pesado por la báscula en vez de ser un valor independiente cargado por el
-- operador.
--
-- Causa raíz (investigada en esta sesión, código + producción): el
-- frontend nunca exigía cargar `cantidad_remito` en el alta (a diferencia
-- de material/proveedor/N° de remito, que sí son obligatorios) — ver fix
-- en paralelo en `useBascula.js#guardarPesada()`/`guardarEdicion()` y las
-- etiquetas "(obligatorio)" en `BasculaView.vue`. Cuando el operador lo
-- dejaba vacío, `registrar_pesada_bascula()` (RPC, ver migración 42) tapaba
-- el hueco con `coalesce(p_cantidad_remito, v_neto_tn)` — v_neto_tn es el
-- peso neto MEDIDO por la báscula — tanto al guardar
-- `plantas_ingresos.cantidad` como al mover stock (`ingreso_proveedor`).
-- Ese `coalesce` viene arrastrado sin cambios desde la migración 13
-- original (13_stock_e_inventarios.sql).
--
-- Qué hace esta migración:
--   1) `registrar_pesada_bascula()`: agrega una validación explícita —
--      ingreso_arido exige `p_cantidad_remito > 0`, mismo patrón que ya usa
--      para material/proveedor — y saca el `coalesce(..., v_neto_tn)` de
--      las 2 líneas que lo usaban (INSERT a plantas_ingresos y el
--      movimiento de stock): ahora usan `p_cantidad_remito` directo, sin
--      fallback silencioso al peso pesado. Resto de la función sin cambios
--      (misma firma — no rompe ningún caller).
--
-- Fuera de alcance a propósito (decisión pendiente de Federico, no una
-- tarea de código): los ingresos YA CARGADOS antes de este fix cuyo
-- `plantas_ingresos.cantidad` haya quedado igual al peso neto pesado por el
-- bug — no se tocan datos históricos acá, es una decisión de negocio (no
-- todo caso "cantidad == peso neto" es necesariamente el bug, podría
-- coincidir de casualidad).
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
    -- Fix migración 44: "Cant. s/Remito" es un valor independiente del peso
    -- pesado (declarado por el proveedor) — antes, si llegaba null acá, el
    -- INSERT de más abajo lo tapaba con el peso neto medido.
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
    -- Fix migración 44: `p_cantidad_remito` directo, sin `coalesce(...,
    -- v_neto_tn)` — ya está garantizado no-null y > 0 por la validación de
    -- arriba, así que el fallback al peso pesado ya no puede dispararse.
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

  return v_vale;
end;
$$;

comment on function registrar_pesada_bascula is
  'Numeración (migración 42): asfalto/hormigón toman numero_vale de plantas_vales_numero_vale_seq; ingreso/egreso de áridos comparten numero_vale_arido de plantas_vales_numero_arido_seq (se muestra I-00001) — nunca se mezclan. Registra un vale de báscula (asfalto/hormigón/ingreso o egreso de árido), mueve stock en ingreso_arido/egreso_arido (migración 13) y captura responsable_email vía auth.email() (migración 20). Para asfalto con pedido_id, asigna nro_remito_global en la PRIMERA pesada del pedido (migración 39, coalesce — no se reasigna en pesadas siguientes del mismo pedido). Ingreso de áridos exige cantidad_remito > 0 (migración 44) — ya no se sustituye silenciosamente por el peso neto pesado. Fuera de eso, sigue sin tocar plantas_pedidos: cantidad_despachada/estado siguen siendo exclusivos de Pedidos (registrar_carga_asfalto + finalizar_despacho) — Báscula es el origen del remito y la auditoría del pesaje, no la fuente de verdad del total despachado (memory/business-rules.md).';
