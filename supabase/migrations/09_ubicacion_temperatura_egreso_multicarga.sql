-- ============================================================================
-- Migración 09: ubicación, temperatura, egreso de áridos y despacho
-- multi-carga de asfalto (vale por carga)
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Origen: memory/relevamiento-sistema-viejo.md, gaps #4, #5, #6, #7.
-- Aprobado por Federico en sesión 2026-08-28 (ver memory/pending.md) — los
-- 4 puntos de este archivo fueron descriptos uno por uno antes de la
-- aprobación (protocolo memory/procedimientos.md).
--
-- Depende de: 01-08 (ya aplicadas — verificado contra information_schema
-- antes de escribir este archivo, no contra los comentarios de los .sql
-- anteriores que quedaron desactualizados).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) plantas_pedidos.ubicacion (gap #4) — texto libre opcional, ej. "Acceso
--    norte, km 12". Campo del modal "Nuevo pedido" del sistema legado.
-- ----------------------------------------------------------------------------
alter table plantas_pedidos
  add column if not exists ubicacion text;

comment on column plantas_pedidos.ubicacion is
  'Ubicación/acceso dentro de la obra (texto libre, opcional) — memory/relevamiento-sistema-viejo.md §1.';

-- ----------------------------------------------------------------------------
-- 2) plantas_vales.temperatura (gap #5) — °C, opcional. Solo se muestra en
--    el form de Báscula para tipo_vale='asfalto', no se valida a nivel DB.
-- ----------------------------------------------------------------------------
alter table plantas_vales
  add column if not exists temperatura numeric;

comment on column plantas_vales.temperatura is
  'Temperatura de la mezcla en °C al pesar (solo asfalto), opcional — memory/relevamiento-sistema-viejo.md §2.';

-- ----------------------------------------------------------------------------
-- 3) plantas_vales: tipo_vale='egreso_arido' (gap #6) + columnas material/destino
--    "Vale Salida Áridos" del legado: egreso pesado de material crudo. A
--    diferencia de ingreso_arido (que vive en plantas_ingresos vía vale_id,
--    porque SÍ suma stock), el egreso no alimenta esa tabla — no hay todavía
--    una tabla de movimientos de stock (plantas_stock, PENDIENTE) a la que
--    escribirle una salida, así que material/destino se guardan acá mismo.
-- ----------------------------------------------------------------------------
alter table plantas_vales
  drop constraint if exists plantas_vales_tipo_vale_check;

alter table plantas_vales
  add constraint plantas_vales_tipo_vale_check
  check (tipo_vale in ('asfalto', 'hormigon', 'ingreso_arido', 'egreso_arido'));

alter table plantas_vales
  add column if not exists material text,
  add column if not exists destino  text;

comment on column plantas_vales.material is
  'Material pesado — solo tipo_vale=''egreso_arido''. (ingreso_arido guarda el material en plantas_ingresos.material vía vale_id, no acá).';
comment on column plantas_vales.destino is
  'Destino declarado del egreso (texto libre) — solo tipo_vale=''egreso_arido''.';

-- ----------------------------------------------------------------------------
-- 4) plantas_cargas_asfalto (gap #7) — despacho multi-camión con vale por
--    carga, disponible desde el modal "Registrar despacho" de Pedidos (no
--    solo desde Báscula: es un registro administrativo del despacho, no un
--    pesaje). Análoga a plantas_cargas_hormigon (migración 05): remito por
--    carga allá, vale por carga acá. El N° de remito único del despacho
--    completo (opcional) sigue viviendo en plantas_pedidos.nro_remito_global
--    (ya existe, migración 06) — no se duplica acá.
-- ----------------------------------------------------------------------------
create table if not exists plantas_cargas_asfalto (
  id             uuid primary key default gen_random_uuid(),
  pedido_id      uuid not null references plantas_pedidos (id),
  obra_id        bigint references flota_obras (id),
  numero_vale    text not null,
  cantidad_tn    numeric not null check (cantidad_tn > 0),
  patente        text,
  fecha_carga    timestamptz not null default now(),
  observaciones  text,
  created_at     timestamptz not null default now()
);

create index if not exists idx_plantas_cargas_asfalto_pedido_id on plantas_cargas_asfalto (pedido_id);
create index if not exists idx_plantas_cargas_asfalto_obra_id on plantas_cargas_asfalto (obra_id);
create index if not exists idx_plantas_cargas_asfalto_fecha_carga on plantas_cargas_asfalto (fecha_carga);

comment on table plantas_cargas_asfalto is
  'Despacho por camión de asfalto declarado desde Pedidos (vale por carga, remito único opcional a nivel pedido). No reemplaza el pesaje real de Báscula (plantas_vales) — mismo patrón que plantas_cargas_hormigon. Ver memory/relevamiento-sistema-viejo.md §1.';

alter table plantas_cargas_asfalto enable row level security;
create policy "plantas_cargas_asfalto: acceso autenticado" on plantas_cargas_asfalto
  for all to authenticated using (true) with check (true);

-- ----------------------------------------------------------------------------
-- 5) registrar_carga_asfalto — atómica, mismo patrón que
--    registrar_carga_hormigon (migración 07): lock de fila del pedido,
--    inserta la carga, acumula cantidad_despachada, pasa a 'despachado' si
--    se cubre lo solicitado. Completa nro_remito_global si se pasa, sin
--    pisar un valor ya cargado por una carga anterior del mismo despacho.
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

  update plantas_pedidos
    set cantidad_despachada = coalesce(v_pedido.cantidad_despachada, 0) + p_cantidad_tn,
        nro_remito_global = coalesce(v_pedido.nro_remito_global, p_numero_remito_global),
        estado = case
          when coalesce(v_pedido.cantidad_despachada, 0) + p_cantidad_tn >= v_pedido.cantidad_solicitada
          then 'despachado' else estado end
    where id = p_pedido_id;

  return v_carga;
end;
$$;

comment on function registrar_carga_asfalto is
  'Registra una carga de asfalto (vale por camión) desde el despacho manual de Pedidos y actualiza el pedido de forma atómica. Análoga a registrar_carga_hormigon — memory/relevamiento-sistema-viejo.md §1.';

revoke execute on function registrar_carga_asfalto(uuid, text, numeric, text, timestamptz, text, text) from public;
grant execute on function registrar_carga_asfalto(uuid, text, numeric, text, timestamptz, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 6) registrar_pesada_bascula — extender con temperatura + egreso_arido.
--    Se DROPEA la firma vieja antes de recrear: agregar parámetros al final
--    cambia la firma (tipos), y dejar las dos versiones coexistiendo vuelve
--    ambigua cualquier llamada con parámetros nombrados que no incluya los
--    2 nuevos — el service ya llama 100% por nombre.
-- ----------------------------------------------------------------------------
drop function if exists registrar_pesada_bascula(
  text, numeric, numeric, uuid, bigint, text, text, text, text, timestamptz, text, text, text, numeric
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
  p_temperatura      numeric default null,
  p_destino          text default null
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

  if v_obra_id is not null and p_tipo_vale = 'asfalto' then
    select coalesce(sum(case when unidad = 'kg' then peso_neto / 1000 else peso_neto end), 0)
      into v_acumulado_tn
      from plantas_vales
      where obra_id = v_obra_id
        and tipo_vale = 'asfalto'
        and fecha_pesada >= date_trunc('day', p_fecha_pesada)
        and fecha_pesada <= p_fecha_pesada;
    v_acumulado_tn := v_acumulado_tn + v_neto_tn;
  end if;

  if p_tipo_vale = 'egreso_arido' and (p_material is null or btrim(p_material) = '') then
    raise exception 'Un egreso de áridos necesita material.';
  end if;

  insert into plantas_vales (
    tipo_vale, pedido_id, obra_id, patente, chofer,
    peso_bruto, tara, peso_neto, unidad, acumulado_obra_tn, fecha_pesada, observaciones,
    temperatura, material, destino
  ) values (
    p_tipo_vale, p_pedido_id, v_obra_id, p_patente, p_chofer,
    p_peso_bruto, p_tara, v_peso_neto, p_unidad, v_acumulado_tn, p_fecha_pesada, p_observaciones,
    p_temperatura,
    case when p_tipo_vale = 'egreso_arido' then p_material else null end,
    case when p_tipo_vale = 'egreso_arido' then p_destino else null end
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
    if p_material is null or p_proveedor is null then
      raise exception 'Un ingreso de áridos necesita material y proveedor.';
    end if;
    insert into plantas_ingresos (
      material, proveedor, numero_remito, cantidad, unidad, origen, vale_id, fecha_ingreso, observaciones
    ) values (
      p_material, p_proveedor, p_numero_remito, coalesce(p_cantidad_remito, v_neto_tn), 'tn',
      'bascula', v_vale.id, p_fecha_pesada, p_observaciones
    );
  end if;

  -- TODO(stock): acá van los movimientos de stock (ingreso Y egreso de
  -- áridos) cuando exista plantas_stock — mismo TODO que ya estaba.

  return v_vale;
end;
$$;

comment on function registrar_pesada_bascula is
  'Registra un vale de báscula (asfalto/hormigón/ingreso o egreso de árido) y actualiza el pedido asociado de forma atómica. Extendida en la migración 09 con temperatura (asfalto) y egreso_arido (material/destino) — memory/relevamiento-sistema-viejo.md §2.';

revoke execute on function registrar_pesada_bascula(text, numeric, numeric, uuid, bigint, text, text, text, text, timestamptz, text, text, text, numeric, numeric, text) from public;
grant execute on function registrar_pesada_bascula(text, numeric, numeric, uuid, bigint, text, text, text, text, timestamptz, text, text, text, numeric, numeric, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 7) fetchPedidosAsfaltoConSaldo (código, no DB) queda renombrada/ampliada
--    en bascula.service.js para dejar de filtrar por saldo pendiente —
--    decisión explícita de Federico (calzar con el comportamiento del
--    legado: permitir pesar contra pedidos ya despachado). No requiere
--    cambio de schema, se deja documentado acá para que quede junto al
--    resto de los cambios de esta sesión.
-- ----------------------------------------------------------------------------
