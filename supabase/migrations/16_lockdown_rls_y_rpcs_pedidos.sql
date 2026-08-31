-- ============================================================================
-- Migración 16: Fase 1 — Lock down de seguridad (RLS) + RPCs de Pedidos
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Origen: diagnóstico de Usuarios/Roles/Permisos (sesión 2026-08-31).
-- Hallazgo crítico: 12/15 tablas de negocio tenían `for all to authenticated
-- using(true) with check(true)` — no solo lectura amplia (ya aceptada en la
-- migración 08), sino ESCRITURA sin ninguna condición. Dos consecuencias
-- reales verificadas: (1) pedidos.service.js#actualizarPedido/confirmarPedido/
-- cancelarPedido/archivarPedido usaban `.update()` directo, sin RPC — cero
-- check de rol server-side, solo la UI ocultaba el botón; (2) se podía
-- `supabase.from('plantas_stock').update(...)` directo, saltando
-- plantas_aplicar_movimiento_stock y corrompiendo la auditoría.
--
-- Fix: las tablas listadas pasan a SELECT-only para `authenticated` — la
-- escritura queda EXCLUSIVAMENTE para funciones SECURITY DEFINER (dueño
-- `postgres`, verificado que bypassea RLS por ser el owner de la tabla —
-- relforcerowsecurity=false, no se activó FORCE). Ninguna RPC existente se
-- ve afectada por este cambio.
--
-- Fuera de alcance de esta Fase 1 (a propósito, ver diagnóstico): los
-- catálogos (plantas_formulas/materiales/proveedores/encargados/patentes/
-- choferes) siguen con su política amplia — hoy se escriben por CRUD directo
-- desde Maestros/Fórmulas (crudEntidad(), sin capa de RPC), bloquearlos acá
-- rompería esas pantallas sin haber construido su RPC todavía. Igual la
-- visibilidad fina por obra (ver_todas_obras/obra_ids) en el SELECT de
-- plantas_pedidos — sigue "lectura amplia" por decisión explícita de
-- Federico para esta fase, queda para una Fase 2.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Lock down: reemplazar ALL/with_check(true) por SELECT-only.
-- ----------------------------------------------------------------------------

drop policy if exists "plantas_pedidos: acceso autenticado" on plantas_pedidos;
create policy "plantas_pedidos: leer" on plantas_pedidos
  for select to authenticated using (true);

drop policy if exists "plantas_vales: acceso autenticado" on plantas_vales;
create policy "plantas_vales: leer" on plantas_vales
  for select to authenticated using (true);

drop policy if exists "plantas_ingresos: acceso autenticado" on plantas_ingresos;
create policy "plantas_ingresos: leer" on plantas_ingresos
  for select to authenticated using (true);

drop policy if exists "plantas_cargas_asfalto: acceso autenticado" on plantas_cargas_asfalto;
create policy "plantas_cargas_asfalto: leer" on plantas_cargas_asfalto
  for select to authenticated using (true);

drop policy if exists "plantas_cargas_hormigon: acceso autenticado" on plantas_cargas_hormigon;
create policy "plantas_cargas_hormigon: leer" on plantas_cargas_hormigon
  for select to authenticated using (true);

drop policy if exists "plantas_stock: acceso autenticado" on plantas_stock;
create policy "plantas_stock: leer" on plantas_stock
  for select to authenticated using (true);

-- plantas_pedidos_historial y plantas_stock_movimientos ya eran select+insert
-- (append-only) desde que se crearon — acá se saca el INSERT: ya no hace
-- falta (todo el historial se escribe atómico dentro de las RPC) y cerraba
-- la puerta a insertar un evento de auditoría falso directo desde el cliente.
drop policy if exists "plantas_pedidos_historial: crear" on plantas_pedidos_historial;
drop policy if exists "plantas_stock_movimientos: insertar" on plantas_stock_movimientos;

-- ----------------------------------------------------------------------------
-- 2) RPCs de Pedidos — reemplazan los 4 métodos que usaban `.update()`/
--    `.insert()` directo en pedidos.service.js. Diseño a propósito NO
--    genérico (nada de "actualizar cualquier columna que mande el cliente"):
--    cada RPC tiene su propia firma explícita y su propia validación de
--    transición de estado — un "update genérico vía RPC" sería
--    funcionalmente idéntico al bypass que se está cerrando.
--
--    Reglas de rol: crear_pedido/actualizar_pedido/cancelar_pedido usan el
--    mismo set (admin/plantista/encargado/supervisor) — quien puede crear un
--    pedido puede editarlo o cancelarlo antes de que se despache; ninguno de
--    los dos .rtf tiene un flag "cancelar" distinto de "crear", así que se
--    infiere de ahí. confirmar_pedido/archivar_pedido quedan solo para
--    admin/plantista (memory/business-rules.md: "Confirmado: solo
--    plantista/admin"; archivar es una acción administrativa de limpieza,
--    mismo criterio). Si Federico quiere afinar esto, es un ajuste puntual
--    del `not in (...)` de cada función, no un rediseño.
-- ----------------------------------------------------------------------------

create or replace function crear_pedido(
  p_formula_id          uuid,
  p_cantidad_solicitada numeric,
  p_fecha_programada    date,
  p_obra_id             bigint default null,
  p_tipo_pedido         text default 'obra',
  p_cliente_externo     text default null,
  p_encargado           text default null,
  p_ubicacion           text default null,
  p_observaciones       text default null,
  p_usuario_legado      text default null
)
returns plantas_pedidos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol    text;
  v_tipo   text;
  v_pedido plantas_pedidos;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista', 'encargado', 'supervisor') then
    raise exception 'Tu rol (%) no puede crear pedidos.', coalesce(v_rol, 'sin rol asignado');
  end if;

  select tipo into v_tipo from plantas_formulas where id = p_formula_id;
  if v_tipo is null then
    raise exception 'La fórmula % no existe.', p_formula_id;
  end if;

  if p_tipo_pedido not in ('obra', 'venta') then
    raise exception 'tipo_pedido inválido: %', p_tipo_pedido;
  end if;
  if p_tipo_pedido = 'venta' and (p_cliente_externo is null or btrim(p_cliente_externo) = '') then
    raise exception 'Las ventas externas necesitan cliente_externo.';
  end if;
  if p_tipo_pedido = 'obra' and p_obra_id is null then
    raise exception 'Completá la obra.';
  end if;
  if not (p_cantidad_solicitada > 0) then
    raise exception 'cantidad_solicitada debe ser mayor a 0.';
  end if;

  insert into plantas_pedidos (
    obra_id, formula_id, tipo, cantidad_solicitada, fecha_programada,
    tipo_pedido, cliente_externo, encargado, ubicacion, observaciones, estado
  ) values (
    p_obra_id, p_formula_id, v_tipo, p_cantidad_solicitada, p_fecha_programada,
    p_tipo_pedido, p_cliente_externo, p_encargado, p_ubicacion, p_observaciones, 'solicitado'
  )
  returning * into v_pedido;

  insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id, usuario_legado)
  values (v_pedido.id, 'solicitado', now(), auth.uid(), coalesce(p_usuario_legado, auth.email()));

  return v_pedido;
end;
$$;

comment on function crear_pedido is
  'Crea un pedido en estado solicitado y su primer evento de historial, de forma atómica. Reemplaza el insert directo de pedidos.service.js#crearPedido (migración 16, lock down RLS).';

revoke execute on function crear_pedido(uuid, numeric, date, bigint, text, text, text, text, text, text) from public;
grant execute on function crear_pedido(uuid, numeric, date, bigint, text, text, text, text, text, text) to authenticated;

create or replace function actualizar_pedido(
  p_pedido_id           uuid,
  p_formula_id          uuid,
  p_cantidad_solicitada numeric,
  p_fecha_programada    date,
  p_obra_id             bigint default null,
  p_tipo_pedido         text default 'obra',
  p_cliente_externo     text default null,
  p_encargado           text default null,
  p_ubicacion           text default null,
  p_observaciones       text default null
)
returns plantas_pedidos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol    text;
  v_tipo   text;
  v_pedido plantas_pedidos;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista', 'encargado', 'supervisor') then
    raise exception 'Tu rol (%) no puede editar pedidos.', coalesce(v_rol, 'sin rol asignado');
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.estado not in ('solicitado', 'confirmado') then
    raise exception 'Solo se puede editar un pedido solicitado o confirmado (estado actual: %).', v_pedido.estado;
  end if;

  select tipo into v_tipo from plantas_formulas where id = p_formula_id;
  if v_tipo is null then
    raise exception 'La fórmula % no existe.', p_formula_id;
  end if;
  if p_tipo_pedido not in ('obra', 'venta') then
    raise exception 'tipo_pedido inválido: %', p_tipo_pedido;
  end if;
  if p_tipo_pedido = 'venta' and (p_cliente_externo is null or btrim(p_cliente_externo) = '') then
    raise exception 'Las ventas externas necesitan cliente_externo.';
  end if;
  if p_tipo_pedido = 'obra' and p_obra_id is null then
    raise exception 'Completá la obra.';
  end if;
  if not (p_cantidad_solicitada > 0) then
    raise exception 'cantidad_solicitada debe ser mayor a 0.';
  end if;

  update plantas_pedidos
    set obra_id             = p_obra_id,
        formula_id          = p_formula_id,
        tipo                = v_tipo,
        cantidad_solicitada = p_cantidad_solicitada,
        fecha_programada    = p_fecha_programada,
        tipo_pedido         = p_tipo_pedido,
        cliente_externo     = p_cliente_externo,
        encargado           = p_encargado,
        ubicacion           = p_ubicacion,
        observaciones       = p_observaciones
    where id = p_pedido_id
    returning * into v_pedido;

  return v_pedido;
end;
$$;

comment on function actualizar_pedido is
  'Edita los campos generales de un pedido solicitado/confirmado (no cambia estado, no genera historial — edición no es un cambio de estado). Reemplaza el update directo de pedidos.service.js#actualizarPedido (migración 16, lock down RLS).';

revoke execute on function actualizar_pedido(uuid, uuid, numeric, date, bigint, text, text, text, text, text) from public;
grant execute on function actualizar_pedido(uuid, uuid, numeric, date, bigint, text, text, text, text, text) to authenticated;

create or replace function confirmar_pedido(
  p_pedido_id      uuid,
  p_observaciones  text default null,
  p_usuario_legado text default null
)
returns plantas_pedidos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol    text;
  v_pedido plantas_pedidos;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista') then
    raise exception 'Tu rol (%) no puede confirmar pedidos.', coalesce(v_rol, 'sin rol asignado');
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.estado not in ('solicitado', 'postergado') then
    raise exception 'Solo se puede confirmar un pedido solicitado o postergado (estado actual: %).', v_pedido.estado;
  end if;

  update plantas_pedidos
    set estado        = 'confirmado',
        observaciones = coalesce(p_observaciones, observaciones)
    where id = p_pedido_id
    returning * into v_pedido;

  insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id, usuario_legado)
  values (p_pedido_id, 'confirmado', now(), auth.uid(), coalesce(p_usuario_legado, auth.email()));

  return v_pedido;
end;
$$;

comment on function confirmar_pedido is
  'solicitado|postergado -> confirmado, solo admin/plantista, con historial atómico. Reemplaza pedidos.service.js#confirmarPedido (migración 16, lock down RLS).';

revoke execute on function confirmar_pedido(uuid, text, text) from public;
grant execute on function confirmar_pedido(uuid, text, text) to authenticated;

create or replace function cancelar_pedido(
  p_pedido_id      uuid,
  p_motivo         text,
  p_usuario_legado text default null
)
returns plantas_pedidos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol    text;
  v_pedido plantas_pedidos;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista', 'encargado', 'supervisor') then
    raise exception 'Tu rol (%) no puede cancelar pedidos.', coalesce(v_rol, 'sin rol asignado');
  end if;
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'El motivo es obligatorio para cancelar un pedido.';
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.estado not in ('solicitado', 'confirmado', 'postergado') then
    raise exception 'No se puede cancelar un pedido en estado %.', v_pedido.estado;
  end if;

  update plantas_pedidos
    set estado = 'cancelado', observaciones = p_motivo
    where id = p_pedido_id
    returning * into v_pedido;

  insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id, motivo, usuario_legado)
  values (p_pedido_id, 'cancelado', now(), auth.uid(), p_motivo, coalesce(p_usuario_legado, auth.email()));

  return v_pedido;
end;
$$;

comment on function cancelar_pedido is
  'Cancela un pedido (motivo obligatorio, memory/business-rules.md), no se reactiva, con historial atómico. Reemplaza pedidos.service.js#cancelarPedido (migración 16, lock down RLS).';

revoke execute on function cancelar_pedido(uuid, text, text) from public;
grant execute on function cancelar_pedido(uuid, text, text) to authenticated;

create or replace function archivar_pedido(p_pedido_id uuid)
returns plantas_pedidos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol    text;
  v_pedido plantas_pedidos;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista') then
    raise exception 'Tu rol (%) no puede archivar pedidos.', coalesce(v_rol, 'sin rol asignado');
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.estado not in ('despachado', 'cancelado') then
    raise exception 'Solo se pueden archivar pedidos despachados o cancelados (estado actual: %).', v_pedido.estado;
  end if;

  update plantas_pedidos set archivado = true where id = p_pedido_id returning * into v_pedido;
  return v_pedido;
end;
$$;

comment on function archivar_pedido is
  'Archiva un pedido despachado/cancelado (memory/business-rules.md: nunca se eliminan). Reemplaza pedidos.service.js#archivarPedido (migración 16, lock down RLS).';

revoke execute on function archivar_pedido(uuid) from public;
grant execute on function archivar_pedido(uuid) to authenticated;
