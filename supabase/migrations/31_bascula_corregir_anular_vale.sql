-- ============================================================================
-- Migración 31: Báscula — corregir/anular un vale (Editar/Eliminar del
-- historial, pedido explícito de Federico 2026-09-08).
--
-- APLICADA en producción 2026-09-08, autorizada explícitamente por Federico.
--
-- Decisión de diseño (contradice el pedido literal, documentado acá a
-- propósito): "Eliminar" NO hace un DELETE real. memory/business-rules.md
-- ya fija "los pedidos nunca se eliminan, solo se archivan", y
-- memory/modules-status.md (Fase 2 de Pedidos/Báscula, 2026-08-28) ya había
-- dejado anotado como decisión pendiente "botón Eliminar en vales/despachos
-- — se mantiene la regla de business-rules.md (nunca se eliminan), no se
-- agregó". El pedido de esta sesión ya contempla la alternativa ("o baja
-- lógica según corresponda") — se implementa como ANULACIÓN: el vale queda
-- en la tabla para siempre (mismo criterio que un vale de papel anulado,
-- memory/business-rules.md ya usa esa metáfora para la numeración), marcado
-- `anulado=true` con motivo obligatorio (mismo patrón que cancelar_pedido),
-- visualmente distinguido en el historial, excluido de acciones (imprimir/
-- volver a editar) y con su efecto de stock revertido si correspondía.
--
-- "Editar" (corregir_vale_bascula) NO permite cambiar el material de un
-- ingreso_arido/egreso_arido — simplificación deliberada: si el material
-- cargado estaba mal, la corrección real es anular ese vale (con motivo) y
-- cargar uno nuevo, no reasignar retroactivamente a qué stock le pegó un
-- pesaje ya hecho. Mismo criterio que ya aplica corregir_despacho(): el
-- delta de stock se recalcula siempre contra el historial REAL de
-- plantas_stock_movimientos atado a este vale (columna vale_id, migración
-- 13), no contra un recálculo ciego — así corregir/anular son idempotentes
-- sin importar cuántas veces se llamen ni si hubo un piso de 0 de por medio
-- (mismo fix que la migración 22 le dio a plantas_descontar_stock_despacho).
--
-- Permisos: admin/plantista únicamente (pedido explícito de Federico — más
-- angosto que quién puede REGISTRAR una pesada, que además incluye
-- balancero). Restringido tanto server-side (estas 2 RPC) como en la UI
-- (BasculaView.vue solo muestra los botones a esos 2 roles).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Columnas de anulación en plantas_vales — nunca se borra la fila.
-- ----------------------------------------------------------------------------
alter table plantas_vales
  add column if not exists anulado          boolean not null default false,
  add column if not exists anulado_en       timestamptz,
  add column if not exists anulado_por      text,
  add column if not exists motivo_anulacion text;

comment on column plantas_vales.anulado is
  'Baja lógica (Federico pidió "Eliminar" en la UI, memory/business-rules.md prohíbe el DELETE real — ver header de la migración 31). Un vale anulado no se puede volver a editar ni anular de nuevo, y queda excluido de impresión/acumulado.';
comment on column plantas_vales.motivo_anulacion is
  'Obligatorio al anular (mismo patrón que plantas_pedidos: cancelar_pedido exige motivo).';

-- ----------------------------------------------------------------------------
-- 2) Nuevo tipo de movimiento de stock para las correcciones/anulaciones de
--    Báscula — mismo criterio que 'recalculo_despacho' (migración 13) para
--    Pedidos, separado de ese tipo porque el origen es distinto (Báscula,
--    no Pedidos) y así el historial de plantas_stock_movimientos deja
--    trazable de dónde vino cada ajuste.
-- ----------------------------------------------------------------------------
alter table plantas_stock_movimientos
  drop constraint if exists plantas_stock_movimientos_tipo_check;

alter table plantas_stock_movimientos
  add constraint plantas_stock_movimientos_tipo_check
  check (tipo in (
    'ingreso_proveedor', 'egreso_despacho', 'egreso_arido',
    'ingreso_manual', 'egreso_manual', 'ajuste', 'recalculo_despacho',
    'recalculo_bascula'
  ));

-- ----------------------------------------------------------------------------
-- 3) plantas_recalcular_stock_vale — helper interno (no se otorga a
--    authenticated). Idéntico patrón idempotente que
--    plantas_descontar_stock_despacho() (migración 22): en vez de recalcular
--    a ciegas, lee lo que YA está aplicado en plantas_stock_movimientos para
--    este vale_id (todos los tipos que este helper puede generar:
--    'ingreso_proveedor'/'egreso_arido' del pesaje original +
--    'recalculo_bascula' de correcciones/anulaciones previas) y aplica solo
--    la diferencia contra el objetivo pedido. p_cantidad_kg_objetivo=0 es lo
--    que usa anular_vale_bascula() para revertir el efecto por completo,
--    sea cual sea el material.
-- ----------------------------------------------------------------------------
create or replace function plantas_recalcular_stock_vale(
  p_vale_id             uuid,
  p_material_id         uuid,
  p_cantidad_kg_objetivo numeric,
  p_origen              text default null,
  p_numero_remito       text default null,
  p_observaciones       text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ya_aplicado numeric;
  v_delta       numeric;
begin
  if p_material_id is null then
    return;
  end if;

  select coalesce(sum(cantidad_kg), 0) into v_ya_aplicado
    from plantas_stock_movimientos
    where vale_id = p_vale_id
      and material_id = p_material_id
      and tipo in ('ingreso_proveedor', 'egreso_arido', 'recalculo_bascula');

  v_delta := coalesce(p_cantidad_kg_objetivo, 0) - v_ya_aplicado;
  if v_delta = 0 then
    return;
  end if;

  perform plantas_aplicar_movimiento_stock(
    p_material_id, 'recalculo_bascula', v_delta, p_origen, p_numero_remito, null, p_vale_id, null, p_observaciones
  );
end;
$$;

revoke execute on function plantas_recalcular_stock_vale(uuid, uuid, numeric, text, text, text) from public;

-- ----------------------------------------------------------------------------
-- 4) corregir_vale_bascula — "Editar" del historial. No permite cambiar
--    tipo_vale ni material (ver header). Sí permite corregir peso/tara
--    (recalcula peso_neto), patente, chofer, observaciones, temperatura
--    (asfalto), proveedor/N° remito/cantidad de remito (ingreso_arido) y
--    obra de destino (egreso_arido).
-- ----------------------------------------------------------------------------
create or replace function corregir_vale_bascula(
  p_vale_id         uuid,
  p_peso_bruto      numeric,
  p_tara            numeric,
  p_patente         text default null,
  p_chofer          text default null,
  p_observaciones   text default null,
  p_temperatura     numeric default null,
  p_proveedor       text default null,
  p_numero_remito   text default null,
  p_cantidad_remito numeric default null,
  p_obra_id         bigint default null
)
returns plantas_vales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol         text;
  v_vale        plantas_vales;
  v_peso_neto   numeric;
  v_neto_tn     numeric;
  v_material_id uuid;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista') then
    raise exception 'Tu rol (%) no puede editar vales de báscula.', coalesce(v_rol, 'sin rol asignado');
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
      p_proveedor, p_numero_remito, 'Corrección de vale #' || coalesce(v_vale.numero_vale::text, '?')
    );
  end if;

  if v_vale.tipo_vale = 'egreso_arido' then
    v_material_id := plantas_buscar_material_id(v_vale.material);
    perform plantas_recalcular_stock_vale(
      p_vale_id, v_material_id, -(v_neto_tn * 1000),
      null, null, 'Corrección de vale #' || coalesce(v_vale.numero_vale::text, '?')
    );
  end if;

  return v_vale;
end;
$$;

comment on function corregir_vale_bascula is
  'Editar un vale de Báscula ya guardado (admin/plantista). No cambia tipo_vale ni material — ver header de la migración 31. Recalcula stock de forma idempotente vía plantas_recalcular_stock_vale().';

revoke execute on function corregir_vale_bascula(uuid, numeric, numeric, text, text, text, numeric, text, text, numeric, bigint) from public;
grant execute on function corregir_vale_bascula(uuid, numeric, numeric, text, text, text, numeric, text, text, numeric, bigint) to authenticated;

-- ----------------------------------------------------------------------------
-- 5) anular_vale_bascula — "Eliminar" del historial (baja lógica, ver
--    header). Motivo obligatorio, mismo patrón que cancelar_pedido().
-- ----------------------------------------------------------------------------
create or replace function anular_vale_bascula(p_vale_id uuid, p_motivo text)
returns plantas_vales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol         text;
  v_vale        plantas_vales;
  v_neto_tn     numeric;
  v_material_id uuid;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista') then
    raise exception 'Tu rol (%) no puede anular vales de báscula.', coalesce(v_rol, 'sin rol asignado');
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
      p_vale_id, v_material_id, 0, null, null, 'Anulación de vale #' || coalesce(v_vale.numero_vale::text, '?') || ': ' || btrim(p_motivo)
    );
  end if;

  return v_vale;
end;
$$;

comment on function anular_vale_bascula is
  'Baja lógica de un vale de Báscula (admin/plantista, motivo obligatorio) — nunca DELETE real, ver header de la migración 31. Revierte el efecto de stock a 0 si el vale era ingreso_arido/egreso_arido.';

revoke execute on function anular_vale_bascula(uuid, text) from public;
grant execute on function anular_vale_bascula(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 6) plantas_v_bascula_viva — agrega anulado/motivo_anulacion (false/null
--    para filas que todavía solo viven en el legado, que nunca pueden
--    anularse desde acá).
--
--    OJO: el intento original de este archivo copiaba el cuerpo de
--    supabase/scripts/vistas_puente_legado_bascula_stock.sql (2026-09-04),
--    que estaba DESACTUALIZADO — la vista real en producción ya tenía un
--    CTE "combinado" + la columna `acumulado_dia_tn` (calculada con una
--    window function) agregados en algún momento posterior, sin que ese
--    script quedara reflejado. `create or replace view` con un `select *`
--    que no matcheaba la posición real de columnas tiró
--    "cannot change name of view column ... to ...". Reconstruido acá
--    contra la definición REAL leída en vivo con
--    `pg_get_viewdef('plantas_v_bascula_viva'::regclass, true)` antes de
--    reintentar — anulado/motivo_anulacion quedan al final del SELECT
--    externo (única posición válida para columnas nuevas sin tocar el
--    orden de las existentes).
-- ----------------------------------------------------------------------------
create or replace view plantas_v_bascula_viva
with (security_invoker = true) as
with obras_legado as (
  select
    o ->> 'id' as obra_id_legado,
    trim(o ->> 'nombre') as nombre_legado,
    coalesce(
      fo_cod.id,
      fo_nom.id,
      case o ->> 'id'
        when 'o1' then 10
        when 'yjscoq2' then 26
        when 'f4stkay' then 2
      end
    ) as flota_obra_id
  from kv_store, jsonb_array_elements(value -> 'obras') as o
  left join flota_obras fo_cod
    on fo_cod.codigo is not null and upper(trim(fo_cod.codigo)) = upper(nullif(trim(o ->> 'codigo'), ''))
  left join flota_obras fo_nom
    on upper(trim(fo_nom.nombre)) = upper(trim(o ->> 'nombre'))
  where kv_store.key = 'vt_maestros9'
),
pp_visible as materialized (
  select id, obra_id, cliente_externo, formula_id, datos_legados ->> 'id' as legado_id
  from plantas_pedidos
),
pv_base as materialized (
  select pv.*, pi.material as ing_material, pi.numero_remito as ing_numero_remito, pi.cantidad as ing_cantidad,
         ppv.cliente_externo as pp_cliente_externo
  from plantas_vales pv
  left join plantas_ingresos pi on pi.vale_id = pv.id
  left join pp_visible ppv on ppv.id = pv.pedido_id
),
legado_asfalto as (
  select
    md5('bascula:asfalto:' || (v ->> 'id'))::uuid as id,
    (v ->> 'numero')::bigint as numero_vale,
    'asfalto'::text as tipo_vale,
    pp.id as pedido_id,
    coalesce(pp.obra_id, ol.flota_obra_id) as obra_id,
    nullif(v ->> 'patente', '') as patente,
    nullif(v ->> 'chofer', '') as chofer,
    (v ->> 'pesoBruto')::numeric as peso_bruto,
    (v ->> 'tara')::numeric as tara,
    (v ->> 'pesoNeto')::numeric as peso_neto,
    'tn'::text as unidad,
    ((v ->> 'fecha') || ' ' || coalesce(nullif(v ->> 'hora', ''), '00:00'))::timestamp
      at time zone 'America/Argentina/Buenos_Aires' as fecha_pesada,
    null::text as material,
    nullif(v ->> 'temperatura', '')::numeric as temperatura,
    null::text as responsable_email,
    nullif(v ->> 'operador', '') as responsable_texto_legado,
    null::text as numero_remito_ingreso,
    null::numeric as cantidad_remito_ingreso,
    pp.cliente_externo as cliente_externo,
    null::numeric as acumulado_obra_tn,
    true as pendiente_migracion,
    false as anulado,
    null::text as motivo_anulacion
  from kv_store, jsonb_array_elements(value) as v
  left join pp_visible pp on pp.legado_id = v ->> 'pedidoId'
  left join obras_legado ol on ol.nombre_legado = trim(v ->> 'obra')
  where kv_store.key = 'vt_vales9'
    and (v ->> 'fecha')::date >= '2026-09-01'
    and not exists (select 1 from pv_base pv where pv.datos_legados ->> 'id' = v ->> 'id')
),
legado_ingreso as (
  select
    md5('bascula:ingreso:' || (v ->> 'id'))::uuid as id,
    null::bigint as numero_vale,
    'ingreso_arido'::text as tipo_vale,
    null::uuid as pedido_id,
    null::bigint as obra_id,
    nullif(v ->> 'patente', '') as patente,
    null::text as chofer,
    (v ->> 'pesoBruto')::numeric as peso_bruto,
    (v ->> 'tara')::numeric as tara,
    (v ->> 'pesoNeto')::numeric as peso_neto,
    'tn'::text as unidad,
    ((v ->> 'fecha') || ' ' || coalesce(nullif(v ->> 'hora', ''), '00:00'))::timestamp
      at time zone 'America/Argentina/Buenos_Aires' as fecha_pesada,
    trim(v ->> 'material') as material,
    null::numeric as temperatura,
    null::text as responsable_email,
    nullif(v ->> 'responsable', '') as responsable_texto_legado,
    nullif(v ->> 'remito', '') as numero_remito_ingreso,
    (v ->> 'cantidadRemito')::numeric as cantidad_remito_ingreso,
    null::text as cliente_externo,
    null::numeric as acumulado_obra_tn,
    true as pendiente_migracion,
    false as anulado,
    null::text as motivo_anulacion
  from kv_store, jsonb_array_elements(value) as v
  where kv_store.key = 'vt_ingaridos9'
    and (v ->> 'fecha')::date >= '2026-09-01'
    and not exists (
      select 1 from plantas_ingresos pi
      where pi.numero_remito = nullif(v ->> 'remito', '') and pi.material = trim(v ->> 'material')
    )
),
legado_egreso as (
  select
    md5('bascula:egreso:' || (v ->> 'id'))::uuid as id,
    (v ->> 'numero')::bigint as numero_vale,
    'egreso_arido'::text as tipo_vale,
    null::uuid as pedido_id,
    ol.flota_obra_id as obra_id,
    nullif(v ->> 'patente', '') as patente,
    nullif(v ->> 'chofer', '') as chofer,
    (v ->> 'pesoBruto')::numeric as peso_bruto,
    (v ->> 'tara')::numeric as tara,
    (v ->> 'pesoNeto')::numeric as peso_neto,
    'tn'::text as unidad,
    ((v ->> 'fecha') || ' ' || coalesce(nullif(v ->> 'hora', ''), '00:00'))::timestamp
      at time zone 'America/Argentina/Buenos_Aires' as fecha_pesada,
    nullif(v ->> 'material', '') as material,
    null::numeric as temperatura,
    null::text as responsable_email,
    nullif(v ->> 'responsable', '') as responsable_texto_legado,
    null::text as numero_remito_ingreso,
    null::numeric as cantidad_remito_ingreso,
    null::text as cliente_externo,
    null::numeric as acumulado_obra_tn,
    true as pendiente_migracion,
    false as anulado,
    null::text as motivo_anulacion
  from kv_store, jsonb_array_elements(value) as v
  left join obras_legado ol on ol.nombre_legado = trim(v ->> 'destino')
  where kv_store.key = 'vt_egaridos9'
    and (v ->> 'fecha')::date >= '2026-09-01'
    and not exists (select 1 from pv_base pv where pv.datos_legados ->> 'id' = v ->> 'id')
),
migrados as (
  select
    pv.id,
    pv.numero_vale,
    pv.tipo_vale,
    pv.pedido_id,
    pv.obra_id,
    pv.patente,
    pv.chofer,
    pv.peso_bruto,
    pv.tara,
    pv.peso_neto,
    pv.unidad,
    pv.fecha_pesada,
    coalesce(pv.material, pv.ing_material) as material,
    pv.temperatura,
    pv.responsable_email,
    null::text as responsable_texto_legado,
    pv.ing_numero_remito as numero_remito_ingreso,
    pv.ing_cantidad as cantidad_remito_ingreso,
    pv.pp_cliente_externo as cliente_externo,
    pv.acumulado_obra_tn,
    false as pendiente_migracion,
    pv.anulado,
    pv.motivo_anulacion
  from pv_base pv
),
combinado as (
  select * from migrados
  union all
  select * from legado_asfalto
  union all
  select * from legado_ingreso
  union all
  select * from legado_egreso
)
select
  id, numero_vale, tipo_vale, pedido_id, obra_id, patente, chofer,
  peso_bruto, tara, peso_neto, unidad, fecha_pesada, material, temperatura,
  responsable_email, responsable_texto_legado, numero_remito_ingreso,
  cantidad_remito_ingreso, cliente_externo, acumulado_obra_tn, pendiente_migracion,
  -- Acumulado del día por pedido/obra, recalculado en vivo con una suma
  -- corrida (no depende de acumulado_obra_tn, que es solo una foto al
  -- pesar) — excluye vales anulados con `and not anulado` (2026-09-08).
  case
    when tipo_vale = 'asfalto' then
      sum(peso_neto) filter (where tipo_vale = 'asfalto' and not anulado) over (
        partition by coalesce(pedido_id::text, obra_id::text, 'sin-obra'), date_trunc('day', fecha_pesada at time zone 'America/Argentina/Buenos_Aires')
        order by fecha_pesada
      )
    else null::numeric
  end as acumulado_dia_tn,
  anulado,
  motivo_anulacion
from combinado c;

grant select on plantas_v_bascula_viva to authenticated;
