-- 26_matriz_permisos_roles.sql
-- Módulo "Administración" (2026-09-06, pedido de Federico — imagen de
-- referencia: modal "Editar Rol" del sistema de Flota, matriz Ver/Crear/
-- Editar/Eliminar/Aprobar/Exportar por módulo, con switches). Pedido
-- explícito: "hacé lo que haya que hacer para que funcione" — a diferencia
-- de la matriz informativa que ya existía en UsuariosPermisosView.vue
-- (MATRIZ_REAL_PERMISOS, hardcodeada en el frontend), ESTO es real:
--
--   1. `plantas_roles`: reemplaza el CHECK hardcodeado de 7 roles fijos por
--      una tabla real — permite crear roles nuevos desde la UI (Federico
--      podrá dar de alta, por ejemplo, un rol "Administrativo Taller" si
--      alguna vez lo necesita, igual que en el ejemplo de Flota).
--   2. `plantas_permisos`: la matriz en sí (rol × módulo × acción →
--      habilitado). Sembrada 1:1 con el comportamiento de HOY (ver abajo)
--      para que aplicar esta migración no cambie nada hasta que Federico
--      toque un switch.
--   3. `plantas_tiene_permiso(modulo, accion)`: helper SECURITY DEFINER que
--      reemplaza los chequeos de rol hardcodeados adentro de las RPC y RLS.
--      `admin` tiene bypass total y no pasa por la tabla — no se puede
--      revocar admin desde la matriz (piso de seguridad no negociable: sin
--      esto, un admin distraído podría auto-bloquearse o un rol con acceso
--      de edición a Administración podría escalar sus propios permisos).
--
-- Alcance deliberadamente NO cubierto acá (documentado en memory/pending.md
-- para no perderlo, no es un olvido):
--   - `registrar_carga_asfalto`/`registrar_carga_hormigon`: quedan con su
--     chequeo de rol hardcodeado tal cual estaba. Son acciones muy
--     específicas (con un carve-out puntual para `plantista_hormigon` que
--     no encaja en el patrón genérico Ver/Crear/Editar/Eliminar/Aprobar/
--     Exportar de un módulo) — forzarlas a la matriz genérica perdía
--     precisión sin ganar nada real a dos días del corte.
--   - `archivar_pedido`: sigue admin/plantista fijo, no editable desde la
--     matriz — es una acción de housekeeping post-cierre, no una acción de
--     uso diario del "módulo Pedidos" en el sentido de la matriz.
--   - El módulo "Administración" en sí: SIEMPRE admin-only, no editable
--     desde su propia matriz (ver punto 3 arriba) — evita que se pueda usar
--     la herramienta para quitarle el control a sí misma.

begin;

-- ---------------------------------------------------------------------------
-- 1. plantas_roles
-- ---------------------------------------------------------------------------

create table if not exists plantas_roles (
  id          text primary key,
  nombre      text not null,
  descripcion text,
  es_sistema  boolean not null default false, -- true = uno de los 7 roles originales del v1.rtf; su `id` no se puede borrar ni renombrar (está hardcodeado en decenas de checks de rol legados: auth.uid()/plantas_rol_actual() = 'admin', etc.)
  activo      boolean not null default true,
  creado_en   timestamptz not null default now()
);

insert into plantas_roles (id, nombre, descripcion, es_sistema) values
  ('admin',              'Administrador',        'Acceso total al sistema. No se puede restringir desde la matriz de permisos.', true),
  ('plantista',          'Plantista',             'Operación diaria de planta: pedidos, despachos, báscula, stock, maestros.', true),
  ('encargado',          'Encargado de obra',     'Solicita y edita pedidos de su obra, ve sus despachos.', true),
  ('supervisor',         'Supervisor',            'Solicita pedidos, ve plan semanal y despachos.', true),
  ('balancero',          'Balancero',             'Registra pesadas en Báscula, ve Stock y Maestros.', true),
  ('gerencia',           'Gerencia',              'Vista gerencial de pedidos, plan semanal, despachos, stock y fórmulas.', true),
  ('plantista_hormigon', 'Plantista de hormigón', 'Gestiona pedidos y despachos de hormigón.', true)
on conflict (id) do nothing;

-- Reemplaza el CHECK fijo de 7 valores por un FK real a plantas_roles — es
-- lo que habilita crear roles nuevos (antes era imposible sin migración).
alter table plantas_usuarios_roles drop constraint if exists plantas_usuarios_roles_rol_check;
alter table plantas_usuarios_roles
  add constraint plantas_usuarios_roles_rol_fkey foreign key (rol) references plantas_roles(id);

-- ---------------------------------------------------------------------------
-- 2. plantas_permisos — la matriz. Sin fila para un (rol, modulo, accion) =
--    false (default seguro). admin no tiene filas: bypass total en la
--    función de abajo, no pasa por acá.
-- ---------------------------------------------------------------------------

create table if not exists plantas_permisos (
  rol_id     text not null references plantas_roles(id) on delete cascade,
  modulo     text not null check (modulo in ('pedidos', 'bascula', 'stock', 'despachos', 'formulas', 'maestros', 'plan_semanal', 'simulador', 'administracion')),
  accion     text not null check (accion in ('ver', 'crear', 'editar', 'eliminar', 'aprobar', 'exportar')),
  habilitado boolean not null default false,
  primary key (rol_id, modulo, accion)
);

-- Semilla 1:1 con el comportamiento de HOY (auth.store.js#PERMISOS_POR_ROL
-- para "ver" + los roles hardcodeados de cada RPC/RLS para el resto,
-- relevados en vivo contra pg_proc/pg_policies al escribir esta migración).
-- Solo se insertan las combinaciones en `true` — todo lo demás queda en
-- `false` por default, sin necesidad de listar 300+ filas en falso.
insert into plantas_permisos (rol_id, modulo, accion, habilitado) values
  -- plantista
  ('plantista', 'pedidos', 'ver', true), ('plantista', 'pedidos', 'crear', true), ('plantista', 'pedidos', 'editar', true), ('plantista', 'pedidos', 'eliminar', true), ('plantista', 'pedidos', 'aprobar', true), ('plantista', 'pedidos', 'exportar', true),
  ('plantista', 'bascula', 'ver', true), ('plantista', 'bascula', 'crear', true), ('plantista', 'bascula', 'exportar', true),
  ('plantista', 'stock', 'ver', true), ('plantista', 'stock', 'crear', true), ('plantista', 'stock', 'editar', true), ('plantista', 'stock', 'exportar', true),
  ('plantista', 'despachos', 'ver', true), ('plantista', 'despachos', 'editar', true), ('plantista', 'despachos', 'aprobar', true), ('plantista', 'despachos', 'exportar', true),
  ('plantista', 'formulas', 'ver', true), ('plantista', 'formulas', 'crear', true), ('plantista', 'formulas', 'editar', true), ('plantista', 'formulas', 'eliminar', true),
  ('plantista', 'maestros', 'ver', true), ('plantista', 'maestros', 'crear', true), ('plantista', 'maestros', 'editar', true), ('plantista', 'maestros', 'eliminar', true),
  ('plantista', 'plan_semanal', 'ver', true),
  ('plantista', 'simulador', 'ver', true),
  -- encargado
  ('encargado', 'pedidos', 'ver', true), ('encargado', 'pedidos', 'crear', true), ('encargado', 'pedidos', 'editar', true), ('encargado', 'pedidos', 'eliminar', true), ('encargado', 'pedidos', 'exportar', true),
  ('encargado', 'despachos', 'ver', true), ('encargado', 'despachos', 'exportar', true),
  -- supervisor
  ('supervisor', 'pedidos', 'ver', true), ('supervisor', 'pedidos', 'crear', true), ('supervisor', 'pedidos', 'editar', true), ('supervisor', 'pedidos', 'eliminar', true), ('supervisor', 'pedidos', 'exportar', true),
  ('supervisor', 'plan_semanal', 'ver', true),
  ('supervisor', 'despachos', 'ver', true), ('supervisor', 'despachos', 'exportar', true),
  -- balancero
  ('balancero', 'bascula', 'ver', true), ('balancero', 'bascula', 'crear', true), ('balancero', 'bascula', 'exportar', true),
  ('balancero', 'stock', 'ver', true), ('balancero', 'stock', 'exportar', true),
  ('balancero', 'maestros', 'ver', true),
  -- gerencia
  ('gerencia', 'pedidos', 'ver', true), ('gerencia', 'pedidos', 'exportar', true),
  ('gerencia', 'plan_semanal', 'ver', true),
  ('gerencia', 'despachos', 'ver', true), ('gerencia', 'despachos', 'exportar', true),
  ('gerencia', 'stock', 'ver', true), ('gerencia', 'stock', 'exportar', true),
  ('gerencia', 'formulas', 'ver', true),
  -- plantista_hormigon
  ('plantista_hormigon', 'pedidos', 'ver', true), ('plantista_hormigon', 'pedidos', 'exportar', true),
  ('plantista_hormigon', 'despachos', 'editar', true), ('plantista_hormigon', 'despachos', 'aprobar', true)
on conflict (rol_id, modulo, accion) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Helper de enforcement — reemplaza los `if v_rol not in (...)` sueltos.
-- ---------------------------------------------------------------------------

create or replace function plantas_tiene_permiso(p_modulo text, p_accion text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select case
    when plantas_rol_actual() = 'admin' then true
    else coalesce(
      (select habilitado from plantas_permisos where rol_id = plantas_rol_actual() and modulo = p_modulo and accion = p_accion),
      false
    )
  end;
$$;

-- RLS: solo admin lee/escribe la config de roles y permisos desde el
-- cliente (mismo patrón que "admin lee todos los usuarios" de la
-- migración 21) — plantas_tiene_permiso() sigue funcionando para todos
-- porque es SECURITY DEFINER, no depende de esta policy.
alter table plantas_roles enable row level security;
alter table plantas_permisos enable row level security;

drop policy if exists "plantas_roles: admin todo" on plantas_roles;
create policy "plantas_roles: admin todo" on plantas_roles
  for all using (plantas_rol_actual() = 'admin') with check (plantas_rol_actual() = 'admin');

drop policy if exists "plantas_permisos: admin todo" on plantas_permisos;
create policy "plantas_permisos: admin todo" on plantas_permisos
  for all using (plantas_rol_actual() = 'admin') with check (plantas_rol_actual() = 'admin');

-- ---------------------------------------------------------------------------
-- 4. Rewire — Pedidos
-- ---------------------------------------------------------------------------

create or replace function crear_pedido(
  p_formula_id uuid, p_cantidad_solicitada numeric, p_fecha_programada date,
  p_obra_id bigint default null, p_tipo_pedido text default 'obra',
  p_cliente_externo text default null, p_encargado text default null,
  p_ubicacion text default null, p_observaciones text default null, p_usuario_legado text default null
)
returns plantas_pedidos
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_tipo   text;
  v_pedido plantas_pedidos;
begin
  if not plantas_tiene_permiso('pedidos', 'crear') then
    raise exception 'Tu rol (%) no puede crear pedidos.', coalesce(plantas_rol_actual(), 'sin rol asignado');
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

create or replace function actualizar_pedido(
  p_pedido_id uuid, p_formula_id uuid, p_cantidad_solicitada numeric, p_fecha_programada date,
  p_obra_id bigint default null, p_tipo_pedido text default 'obra',
  p_cliente_externo text default null, p_encargado text default null,
  p_ubicacion text default null, p_observaciones text default null
)
returns plantas_pedidos
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_tipo   text;
  v_pedido plantas_pedidos;
begin
  if not plantas_tiene_permiso('pedidos', 'editar') then
    raise exception 'Tu rol (%) no puede editar pedidos.', coalesce(plantas_rol_actual(), 'sin rol asignado');
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

create or replace function cancelar_pedido(p_pedido_id uuid, p_motivo text, p_usuario_legado text default null)
returns plantas_pedidos
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_pedido plantas_pedidos;
begin
  if not plantas_tiene_permiso('pedidos', 'eliminar') then
    raise exception 'Tu rol (%) no puede cancelar pedidos.', coalesce(plantas_rol_actual(), 'sin rol asignado');
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
    set estado = 'cancelado',
        observaciones = 'MOTIVO CANCELACIÓN: ' || p_motivo ||
          case when v_pedido.observaciones is not null and btrim(v_pedido.observaciones) <> ''
               then ' | OBS: ' || v_pedido.observaciones
               else '' end
    where id = p_pedido_id
    returning * into v_pedido;

  insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id, motivo, usuario_legado)
  values (p_pedido_id, 'cancelado', now(), auth.uid(), p_motivo, coalesce(p_usuario_legado, auth.email()));

  return v_pedido;
end;
$$;

create or replace function confirmar_pedido(p_pedido_id uuid, p_observaciones text default null, p_usuario_legado text default null)
returns plantas_pedidos
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_pedido plantas_pedidos;
begin
  if not plantas_tiene_permiso('pedidos', 'aprobar') then
    raise exception 'Tu rol (%) no puede confirmar pedidos.', coalesce(plantas_rol_actual(), 'sin rol asignado');
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

-- postergar_pedido comparte el flag pedidos.aprobar con confirmar_pedido
-- (mismo set de roles hoy: admin/plantista únicamente, ver migración 24) —
-- no "pedidos.editar", que en la matriz queda para actualizar_pedido
-- (admin/plantista/encargado/supervisor).
create or replace function postergar_pedido(p_pedido_id uuid, p_fecha_nueva date default null, p_motivo text default null)
returns plantas_pedidos
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_pedido         plantas_pedidos;
  v_fecha_anterior date;
begin
  if not plantas_tiene_permiso('pedidos', 'aprobar') then
    raise exception 'Tu rol (%) no puede postergar pedidos.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.estado not in ('solicitado', 'confirmado', 'postergado') then
    raise exception 'Solo se puede postergar un pedido solicitado, confirmado o ya postergado (estado actual: %).', v_pedido.estado;
  end if;

  v_fecha_anterior := v_pedido.fecha_programada;

  update plantas_pedidos
    set estado = 'postergado',
        fecha_programada = coalesce(p_fecha_nueva, fecha_programada),
        motivo = p_motivo,
        motivo_en = case when p_motivo is not null then now() else motivo_en end
    where id = p_pedido_id
    returning * into v_pedido;

  insert into plantas_pedidos_historial (
    pedido_id, estado, fecha_evento, fecha_programada_anterior, fecha_programada_nueva, usuario_id, motivo
  ) values (
    p_pedido_id, 'postergado', now(), v_fecha_anterior, p_fecha_nueva, auth.uid(), p_motivo
  );

  return v_pedido;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Rewire — Despachos
-- ---------------------------------------------------------------------------

create or replace function corregir_despacho(
  p_pedido_id uuid, p_cantidad_despachada numeric default null,
  p_nro_remito_global text default null, p_nro_vale_global text default null, p_notas text default null
)
returns plantas_pedidos
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_pedido         plantas_pedidos;
  v_diff           jsonb;
  v_cantidad_nueva numeric;
begin
  if not plantas_tiene_permiso('despachos', 'editar') then
    raise exception 'Tu rol (%) no puede corregir un despacho.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.estado <> 'despachado' then
    raise exception 'Solo se puede corregir un despacho ya cerrado (estado actual: %).', v_pedido.estado;
  end if;
  if p_cantidad_despachada is not null and not (p_cantidad_despachada > 0) then
    raise exception 'La cantidad corregida debe ser mayor a 0.';
  end if;

  v_cantidad_nueva := coalesce(p_cantidad_despachada, v_pedido.cantidad_despachada);

  v_diff := jsonb_build_object(
    'cantidad_despachada', jsonb_build_object('anterior', v_pedido.cantidad_despachada, 'nueva', v_cantidad_nueva),
    'nro_remito_global', jsonb_build_object('anterior', v_pedido.nro_remito_global, 'nuevo', coalesce(p_nro_remito_global, v_pedido.nro_remito_global)),
    'nro_vale_global', jsonb_build_object('anterior', v_pedido.nro_vale_global, 'nuevo', coalesce(p_nro_vale_global, v_pedido.nro_vale_global))
  );

  update plantas_pedidos
    set cantidad_despachada = v_cantidad_nueva,
        nro_remito_global   = coalesce(p_nro_remito_global, nro_remito_global),
        nro_vale_global     = coalesce(p_nro_vale_global, nro_vale_global)
    where id = p_pedido_id;

  perform plantas_descontar_stock_despacho(p_pedido_id, v_pedido.cantidad_despachada, v_cantidad_nueva);

  insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id, motivo, datos_legados)
  values (p_pedido_id, 'corregido', now(), auth.uid(), p_notas, v_diff);

  select * into v_pedido from plantas_pedidos where id = p_pedido_id;
  return v_pedido;
end;
$$;

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

-- ---------------------------------------------------------------------------
-- 6. Rewire — Stock
-- ---------------------------------------------------------------------------

create or replace function registrar_movimiento_manual(
  p_material_id uuid, p_tipo text, p_cantidad_kg numeric,
  p_origen text default null, p_numero_remito text default null, p_observaciones text default null
)
returns plantas_stock_movimientos
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_mov plantas_stock_movimientos;
begin
  if not plantas_tiene_permiso('stock', 'crear') then
    raise exception 'Tu rol (%) no puede registrar movimientos manuales de stock.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;
  if p_tipo not in ('ingreso_manual', 'egreso_manual') then
    raise exception 'tipo inválido: % (esperado ingreso_manual o egreso_manual)', p_tipo;
  end if;
  if not (p_cantidad_kg > 0) then
    raise exception 'cantidad_kg debe ser mayor a 0';
  end if;
  if not exists (select 1 from plantas_materiales where id = p_material_id and controla_stock) then
    raise exception 'El material no existe o no controla stock.';
  end if;

  v_mov := plantas_aplicar_movimiento_stock(
    p_material_id,
    p_tipo,
    case when p_tipo = 'ingreso_manual' then p_cantidad_kg else -p_cantidad_kg end,
    p_origen, p_numero_remito, null, null, null, p_observaciones
  );
  return v_mov;
end;
$$;

create or replace function registrar_relevamiento_stock(p_conteos jsonb, p_motivo text default 'Relevamiento mensual')
returns setof plantas_stock_movimientos
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_item              jsonb;
  v_material_id       uuid;
  v_nueva             numeric;
  v_actual            numeric;
  v_total_antes       numeric := 0;
  v_total_despues     numeric := 0;
  v_con_valor_antes   int := 0;
  v_con_valor_despues int := 0;
  v_mov               plantas_stock_movimientos;
begin
  if not plantas_tiene_permiso('stock', 'editar') then
    raise exception 'Tu rol (%) no puede cargar un relevamiento de stock.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  select coalesce(sum(cantidad_kg), 0), count(*) filter (where cantidad_kg > 0)
    into v_total_antes, v_con_valor_antes
    from plantas_stock;

  v_total_despues := v_total_antes;
  v_con_valor_despues := v_con_valor_antes;

  for v_item in select * from jsonb_array_elements(p_conteos)
  loop
    v_material_id := (v_item->>'material_id')::uuid;
    v_nueva := (v_item->>'cantidad_kg')::numeric;
    if v_nueva is null or v_nueva < 0 then
      raise exception 'cantidad_kg inválida para el material % (no puede ser negativa).', v_material_id;
    end if;

    select cantidad_kg into v_actual from plantas_stock where material_id = v_material_id;
    v_actual := coalesce(v_actual, 0);

    v_total_despues := v_total_despues - v_actual + v_nueva;
    if v_actual > 0 and v_nueva = 0 then v_con_valor_despues := v_con_valor_despues - 1; end if;
    if v_actual = 0 and v_nueva > 0 then v_con_valor_despues := v_con_valor_despues + 1; end if;
  end loop;

  if v_con_valor_antes > 0 and v_con_valor_despues < (v_con_valor_antes * 0.5) then
    raise exception 'saveStockGuard: el relevamiento deja sin stock a más de la mitad de los materiales que hoy tienen valor (% -> %). Guardado cancelado — revisá los conteos.',
      v_con_valor_antes, v_con_valor_despues;
  end if;
  if v_total_antes > 0 and v_total_despues < (v_total_antes * 0.1) then
    raise exception 'saveStockGuard: el relevamiento hace caer el stock total más de un 90%% (% kg -> % kg). Guardado cancelado — revisá los conteos.',
      v_total_antes, v_total_despues;
  end if;

  for v_item in select * from jsonb_array_elements(p_conteos)
  loop
    v_material_id := (v_item->>'material_id')::uuid;
    v_nueva := (v_item->>'cantidad_kg')::numeric;
    select cantidad_kg into v_actual from plantas_stock where material_id = v_material_id;
    v_actual := coalesce(v_actual, 0);

    if v_nueva <> v_actual then
      v_mov := plantas_aplicar_movimiento_stock(v_material_id, 'ajuste', v_nueva - v_actual, p_motivo, null, null, null, null, null);
      return next v_mov;
    end if;
  end loop;

  return;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Rewire — Báscula/Stock RLS de lectura (migración 23)
-- ---------------------------------------------------------------------------

create or replace function plantas_puede_ver_bascula()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select plantas_tiene_permiso('bascula', 'ver');
$$;

create or replace function plantas_puede_ver_stock()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select plantas_tiene_permiso('stock', 'ver');
$$;

-- ---------------------------------------------------------------------------
-- 8. Rewire — Maestros (5 catálogos) + Fórmulas (su propio módulo en la
--    matriz, aunque comparte el mismo patrón de policies que Maestros).
-- ---------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array['plantas_choferes', 'plantas_encargados', 'plantas_materiales', 'plantas_patentes', 'plantas_proveedores']
  loop
    execute format('drop policy if exists %I on %I', t || ': crear admin/plantista', t);
    execute format('drop policy if exists %I on %I', t || ': editar admin/plantista', t);
    execute format('drop policy if exists %I on %I', t || ': borrar admin/plantista', t);

    execute format(
      'create policy %I on %I for insert with check (plantas_tiene_permiso(''maestros'', ''crear''))',
      t || ': crear (matriz)', t
    );
    execute format(
      'create policy %I on %I for update using (plantas_tiene_permiso(''maestros'', ''editar'')) with check (plantas_tiene_permiso(''maestros'', ''editar''))',
      t || ': editar (matriz)', t
    );
    execute format(
      'create policy %I on %I for delete using (plantas_tiene_permiso(''maestros'', ''eliminar''))',
      t || ': borrar (matriz)', t
    );
  end loop;
end $$;

drop policy if exists "plantas_formulas: crear admin/plantista" on plantas_formulas;
drop policy if exists "plantas_formulas: editar admin/plantista" on plantas_formulas;
drop policy if exists "plantas_formulas: borrar admin/plantista" on plantas_formulas;

create policy "plantas_formulas: crear (matriz)" on plantas_formulas
  for insert with check (plantas_tiene_permiso('formulas', 'crear'));
create policy "plantas_formulas: editar (matriz)" on plantas_formulas
  for update using (plantas_tiene_permiso('formulas', 'editar')) with check (plantas_tiene_permiso('formulas', 'editar'));
create policy "plantas_formulas: borrar (matriz)" on plantas_formulas
  for delete using (plantas_tiene_permiso('formulas', 'eliminar'));

-- ---------------------------------------------------------------------------
-- 9. admin_upsert_usuario_rol: validar p_rol contra plantas_roles (activo)
--    en vez de la lista hardcodeada de 7 valores — permite asignar roles
--    nuevos a un usuario. El chequeo "solo admin puede llamar esto" queda
--    igual (no pasa por la matriz — Administración es admin-only fijo).
-- ---------------------------------------------------------------------------

create or replace function admin_upsert_usuario_rol(
  p_email text, p_rol text, p_ver_todas_obras boolean default false,
  p_ver_ventas boolean default false, p_obra_ids integer[] default '{}', p_activo boolean default true
)
returns plantas_usuarios_roles
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_resultado plantas_usuarios_roles;
begin
  if plantas_rol_actual() is distinct from 'admin' then
    raise exception 'Solo un usuario con rol admin puede administrar usuarios y roles.';
  end if;

  if not exists (select 1 from plantas_roles where id = p_rol and activo = true) then
    raise exception 'Rol "%" inválido o inactivo.', p_rol;
  end if;

  insert into plantas_usuarios_roles (email, rol, ver_todas_obras, ver_ventas, obra_ids, activo)
  values (lower(trim(p_email)), p_rol, p_ver_todas_obras, p_ver_ventas, coalesce(p_obra_ids, '{}'), p_activo)
  on conflict (email) do update set
    rol = excluded.rol,
    ver_todas_obras = excluded.ver_todas_obras,
    ver_ventas = excluded.ver_ventas,
    obra_ids = excluded.obra_ids,
    activo = excluded.activo
  returning * into v_resultado;

  return v_resultado;
end;
$$;

commit;
