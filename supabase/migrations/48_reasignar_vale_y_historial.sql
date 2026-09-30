-- ============================================================================
-- Migración 48: reasignar un vale de asfalto a otro pedido + historial de vales
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Pedido de Federico (2026-09-30, opción A aprobada): cuando el balancero pesa
-- un camión contra el pedido equivocado, hoy la única salida es anular el
-- vale y volver a pesarlo (caso real: vale 10170 anulado "mal obra" y
-- repesado como 10171 el 30/09) — deja un hueco en la numeración y obliga a
-- retipear bruto/tara. Ahora se puede reasignar el vale al pedido correcto,
-- con motivo obligatorio y registro en un historial.
--
-- Qué hace:
--   1) Tabla plantas_vales_historial: una fila por reasignación, edición o
--      anulación de un vale (quién, cuándo, motivo, pedido anterior/nuevo,
--      valores antes/después). Solo se escribe desde las RPC (SECURITY
--      DEFINER); lectura con bascula:ver.
--   2) RPC reasignar_vale_bascula(vale, pedido, motivo). Reglas:
--      - permiso bascula:editar (admin, plantista, balancero hoy);
--      - motivo obligatorio;
--      - solo vales de ASFALTO no anulados;
--      - pedido de origen (si tiene) y de destino en estado 'confirmado':
--        si alguno ya está despachado, la cantidad oficial ya está cerrada
--        en Pedidos y el remito ya salió -> anular + corregir despacho;
--      - destino distinto al actual y de asfalto;
--      - si en Pedidos ya se registró una carga con ese N° de vale en el
--        pedido de origen, se rechaza: esa carga suma cantidad_despachada
--        (dominio de Pedidos, memory/business-rules.md) y la tiene que
--        corregir el plantista primero.
--      Efectos: pedido_id y obra_id del vale pasan al destino; el destino
--      toma N° de remito si todavía no tenía (mismo coalesce que
--      registrar_pesada_bascula). N° de vale intacto. Sin impacto en stock
--      (el asfalto descuenta stock al finalizar el despacho, desde
--      cantidad_despachada de Pedidos, nunca desde los vales). El remito que
--      el origen haya recibido por esta pesada NO se le quita (pudo haberse
--      impreso; un N° de remito no se reutiliza).
--   3) corregir_vale_bascula() y anular_vale_bascula() también registran en
--      el historial (antes las ediciones no dejaban rastro). Cuerpos
--      tomados de la migración 47 (aplicada 2026-09-30), solo se agrega el
--      insert al historial.
--
-- Reversión: drop function reasignar_vale_bascula; volver a correr las
-- funciones de la migración 47; drop table plantas_vales_historial.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Historial de vales
-- ----------------------------------------------------------------------------
create table if not exists plantas_vales_historial (
  id                 uuid primary key default gen_random_uuid(),
  vale_id            uuid not null references plantas_vales(id),
  accion             text not null check (accion in ('reasignacion', 'edicion', 'anulacion')),
  pedido_anterior_id uuid references plantas_pedidos(id),
  pedido_nuevo_id    uuid references plantas_pedidos(id),
  antes              jsonb,
  despues            jsonb,
  motivo             text,
  usuario_email      text,
  created_at         timestamptz not null default now()
);

create index if not exists plantas_vales_historial_vale_idx on plantas_vales_historial (vale_id, created_at);

alter table plantas_vales_historial enable row level security;

drop policy if exists plantas_vales_historial_select on plantas_vales_historial;
create policy plantas_vales_historial_select on plantas_vales_historial
  for select to authenticated
  using ((select plantas_tiene_permiso('bascula', 'ver')));

revoke all on plantas_vales_historial from anon;
revoke insert, update, delete on plantas_vales_historial from authenticated;
grant select on plantas_vales_historial to authenticated;

-- ----------------------------------------------------------------------------
-- 2) Reasignar vale de asfalto a otro pedido
-- ----------------------------------------------------------------------------
create or replace function public.reasignar_vale_bascula(p_vale_id uuid, p_pedido_id uuid, p_motivo text)
 returns plantas_vales
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_vale    plantas_vales;
  v_origen  plantas_pedidos;
  v_destino plantas_pedidos;
begin
  if not plantas_tiene_permiso('bascula', 'editar') then
    raise exception 'Tu rol (%) no puede reasignar vales de báscula.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'El motivo de la reasignación es obligatorio.';
  end if;
  if p_pedido_id is null then
    raise exception 'Elegí el pedido correcto.';
  end if;

  select * into v_vale from plantas_vales where id = p_vale_id for update;
  if not found then
    raise exception 'El vale % no existe.', p_vale_id;
  end if;
  if v_vale.tipo_vale <> 'asfalto' then
    raise exception 'Solo los vales de asfalto se pueden reasignar a otro pedido.';
  end if;
  if v_vale.anulado then
    raise exception 'Este vale está anulado — no se puede reasignar.';
  end if;
  if v_vale.pedido_id is not distinct from p_pedido_id then
    raise exception 'El vale ya está asignado a ese pedido.';
  end if;

  -- Lock de los dos pedidos en orden de id (evita deadlock entre dos
  -- reasignaciones cruzadas simultáneas).
  perform 1 from plantas_pedidos
    where id in (p_pedido_id, v_vale.pedido_id)
    order by id
    for update;

  select * into v_destino from plantas_pedidos where id = p_pedido_id;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_destino.tipo <> 'asfalto' then
    raise exception 'El pedido elegido no es de asfalto.';
  end if;
  if v_destino.estado <> 'confirmado' then
    raise exception 'El pedido elegido tiene que estar confirmado (estado actual: %).', v_destino.estado;
  end if;

  if v_vale.pedido_id is not null then
    select * into v_origen from plantas_pedidos where id = v_vale.pedido_id;
    if v_origen.estado <> 'confirmado' then
      raise exception 'El pedido actual del vale ya está % — no se puede reasignar. Anulá el vale y corregí el despacho desde Pedidos.', v_origen.estado;
    end if;
    if exists (
      select 1 from plantas_cargas_asfalto
      where pedido_id = v_origen.id and btrim(numero_vale) = v_vale.numero_vale::text
    ) then
      raise exception 'El vale N° % ya figura como carga en el despacho del pedido actual (Pedidos). Corregí esa carga primero.', v_vale.numero_vale;
    end if;
  end if;

  update plantas_vales set
    pedido_id = v_destino.id,
    obra_id   = v_destino.obra_id
  where id = p_vale_id
  returning * into v_vale;

  update plantas_pedidos
    set nro_remito_global = coalesce(nro_remito_global, nextval('plantas_remitos_numero_seq')::text)
    where id = v_destino.id;

  insert into plantas_vales_historial (vale_id, accion, pedido_anterior_id, pedido_nuevo_id, antes, despues, motivo, usuario_email)
  values (
    p_vale_id, 'reasignacion', v_origen.id, v_destino.id,
    jsonb_build_object('pedido_id', v_origen.id, 'obra_id', v_origen.obra_id, 'cliente_externo', v_origen.cliente_externo),
    jsonb_build_object('pedido_id', v_destino.id, 'obra_id', v_destino.obra_id, 'cliente_externo', v_destino.cliente_externo),
    btrim(p_motivo), auth.email()
  );

  return v_vale;
end;
$function$;

comment on function reasignar_vale_bascula is
  'Reasigna un vale de asfalto (no anulado) a otro pedido de asfalto confirmado, con motivo obligatorio y registro en plantas_vales_historial (migración 48). Origen también tiene que estar confirmado y sin carga en Pedidos con ese N° de vale. Conserva el N° de vale; el destino toma N° de remito si no tenía; sin impacto en stock.';

revoke execute on function reasignar_vale_bascula(uuid, uuid, text) from public, anon;
grant execute on function reasignar_vale_bascula(uuid, uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 3) Edición y anulación también dejan rastro en el historial
-- ----------------------------------------------------------------------------
create or replace function public.corregir_vale_bascula(p_vale_id uuid, p_peso_bruto numeric, p_tara numeric, p_patente text default null::text, p_chofer text default null::text, p_observaciones text default null::text, p_temperatura numeric default null::numeric, p_proveedor text default null::text, p_numero_remito text default null::text, p_cantidad_remito numeric default null::numeric, p_obra_id bigint default null::bigint)
 returns plantas_vales
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_vale        plantas_vales;
  v_antes       jsonb;
  v_peso_neto   numeric;
  v_neto_tn     numeric;
  v_material_id uuid;
begin
  if not plantas_tiene_permiso('bascula', 'editar') then
    raise exception 'Tu rol (%) no puede editar vales de báscula.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  select * into v_vale from plantas_vales where id = p_vale_id;
  if not found then
    raise exception 'El vale % no existe.', p_vale_id;
  end if;
  if v_vale.anulado then
    raise exception 'Este vale está anulado — no se puede editar. Cargá un vale nuevo si corresponde.';
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
  v_neto_tn := case when v_vale.unidad = 'kg' then v_peso_neto / 1000 else v_peso_neto end;

  if v_vale.tipo_vale = 'ingreso_arido' and p_numero_remito is not null and btrim(p_numero_remito) <> '' then
    if exists (
      select 1 from plantas_ingresos
      where numero_remito = btrim(p_numero_remito) and vale_id <> p_vale_id
    ) then
      raise exception 'Ya existe otro ingreso registrado con el remito %.', p_numero_remito;
    end if;
  end if;

  v_antes := jsonb_build_object(
    'peso_bruto', v_vale.peso_bruto, 'tara', v_vale.tara, 'peso_neto', v_vale.peso_neto,
    'patente', v_vale.patente, 'chofer', v_vale.chofer, 'temperatura', v_vale.temperatura,
    'obra_id', v_vale.obra_id, 'observaciones', v_vale.observaciones
  );
  if v_vale.tipo_vale = 'ingreso_arido' then
    v_antes := v_antes || coalesce((
      select jsonb_build_object('proveedor', proveedor, 'numero_remito', numero_remito, 'cantidad_remito', cantidad)
      from plantas_ingresos where vale_id = p_vale_id limit 1
    ), '{}'::jsonb);
  end if;

  update plantas_vales set
    peso_bruto    = p_peso_bruto,
    tara          = p_tara,
    peso_neto     = v_peso_neto,
    patente       = coalesce(p_patente, patente),
    chofer        = case when tipo_vale = 'asfalto' then coalesce(p_chofer, chofer) else chofer end,
    temperatura   = case when tipo_vale = 'asfalto' then p_temperatura else temperatura end,
    obra_id       = case when tipo_vale = 'egreso_arido' then coalesce(p_obra_id, obra_id) else obra_id end,
    observaciones = coalesce(p_observaciones, observaciones)
  where id = p_vale_id
  returning * into v_vale;

  if v_vale.tipo_vale = 'ingreso_arido' then
    update plantas_ingresos set
      proveedor     = coalesce(p_proveedor, proveedor),
      numero_remito = coalesce(nullif(btrim(p_numero_remito), ''), numero_remito),
      cantidad      = coalesce(p_cantidad_remito, cantidad)
    where vale_id = p_vale_id;

    v_material_id := plantas_buscar_material_id(v_vale.material);
    perform plantas_recalcular_stock_vale(
      p_vale_id, v_material_id, coalesce(p_cantidad_remito, v_neto_tn) * 1000,
      p_proveedor, p_numero_remito, 'Corrección de vale #' || plantas_etiqueta_vale(v_vale)
    );
  end if;

  if v_vale.tipo_vale = 'egreso_arido' then
    v_material_id := plantas_buscar_material_id(v_vale.material);
    perform plantas_recalcular_stock_vale(
      p_vale_id, v_material_id, -(v_neto_tn * 1000),
      null, null, 'Corrección de vale #' || plantas_etiqueta_vale(v_vale)
    );
  end if;

  insert into plantas_vales_historial (vale_id, accion, pedido_anterior_id, pedido_nuevo_id, antes, despues, usuario_email)
  values (
    p_vale_id, 'edicion', v_vale.pedido_id, v_vale.pedido_id, v_antes,
    jsonb_build_object(
      'peso_bruto', v_vale.peso_bruto, 'tara', v_vale.tara, 'peso_neto', v_vale.peso_neto,
      'patente', v_vale.patente, 'chofer', v_vale.chofer, 'temperatura', v_vale.temperatura,
      'obra_id', v_vale.obra_id, 'observaciones', v_vale.observaciones
    ) || case when v_vale.tipo_vale = 'ingreso_arido' then coalesce((
      select jsonb_build_object('proveedor', proveedor, 'numero_remito', numero_remito, 'cantidad_remito', cantidad)
      from plantas_ingresos where vale_id = p_vale_id limit 1
    ), '{}'::jsonb) else '{}'::jsonb end,
    auth.email()
  );

  return v_vale;
end;
$function$;

create or replace function public.anular_vale_bascula(p_vale_id uuid, p_motivo text)
 returns plantas_vales
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_vale        plantas_vales;
  v_material_id uuid;
begin
  if not plantas_tiene_permiso('bascula', 'eliminar') then
    raise exception 'Tu rol (%) no puede anular vales de báscula.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'El motivo de anulación es obligatorio.';
  end if;

  select * into v_vale from plantas_vales where id = p_vale_id;
  if not found then
    raise exception 'El vale % no existe.', p_vale_id;
  end if;
  if v_vale.anulado then
    raise exception 'Este vale ya está anulado.';
  end if;

  update plantas_vales set
    anulado          = true,
    anulado_en       = now(),
    anulado_por      = auth.email(),
    motivo_anulacion = btrim(p_motivo)
  where id = p_vale_id
  returning * into v_vale;

  if v_vale.tipo_vale in ('ingreso_arido', 'egreso_arido') then
    v_material_id := plantas_buscar_material_id(v_vale.material);
    perform plantas_recalcular_stock_vale(
      p_vale_id, v_material_id, 0, null, null, 'Anulación de vale #' || plantas_etiqueta_vale(v_vale) || ': ' || btrim(p_motivo)
    );
  end if;

  insert into plantas_vales_historial (vale_id, accion, pedido_anterior_id, pedido_nuevo_id, motivo, usuario_email)
  values (p_vale_id, 'anulacion', v_vale.pedido_id, v_vale.pedido_id, btrim(p_motivo), auth.email());

  return v_vale;
end;
$function$;

revoke execute on function corregir_vale_bascula(uuid, numeric, numeric, text, text, text, numeric, text, text, numeric, bigint) from public, anon;
grant execute on function corregir_vale_bascula(uuid, numeric, numeric, text, text, text, numeric, text, text, numeric, bigint) to authenticated;
revoke execute on function anular_vale_bascula(uuid, text) from public, anon;
grant execute on function anular_vale_bascula(uuid, text) to authenticated;
