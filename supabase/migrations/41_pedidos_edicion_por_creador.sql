-- ============================================================================
-- Migración 41: Editar/Postergar un pedido queda restringido a admin/
-- plantista (alcance global) o al usuario que CREÓ ese pedido puntual
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Pedido explícito de Federico (2026-09-17): hoy encargado/supervisor
-- pueden editar CUALQUIER pedido (plantas_permisos: pedidos.editar=true
-- para esos 2 roles) y nadie más que plantista/admin puede postergar
-- (pedidos.aprobar). El pedido nuevo: admin/plantista mantienen alcance
-- global sobre ambas acciones; cualquier otro rol (encargado, supervisor —
-- los únicos que además pueden CREAR pedidos, pedidos.crear) solo puede
-- editar/postergar los pedidos que ÉL MISMO creó.
--
-- 1) Columna nueva plantas_pedidos.creado_por (texto, email — mismo patrón
--    que plantas_vales.responsable_email/plantas_remitos_manuales.creado_por):
--    se completa en crear_pedido() vía auth.email(). Backfill de los 198
--    pedidos existentes desde plantas_pedidos_historial (evento
--    'solicitado', que ya guarda usuario_legado = auth.email() del creador
--    real para todo pedido creado desde la app — verificado: los 198
--    pedidos actuales tienen ese dato reconstruible, 0 huérfanos).
-- 2) actualizar_pedido(): sigue exigiendo el piso de plantas_tiene_permiso
--    ('pedidos','editar') — eso no cambia (balancero sigue sin poder editar
--    nada, por ejemplo) — pero además, si el rol no es admin/plantista,
--    exige creado_por = auth.email().
-- 3) postergar_pedido(): antes exigía plantas_tiene_permiso('pedidos',
--    'aprobar') — SOLO plantista/admin podían postergar, ningún encargado/
--    supervisor podía hacerlo nunca, ni siquiera lo propio. Ahora: admin/
--    plantista mantienen el alcance global de siempre; además, cualquier
--    rol con permiso de CREAR pedidos (pedidos.crear — hoy encargado/
--    supervisor/plantista) puede postergar el pedido puntual que él mismo
--    creó. Balancero/gerencia/plantista_hormigon no tienen pedidos.crear
--    hoy, así que esta rama no les abre nada nuevo (nunca van a ser
--    "creado_por" de ningún pedido).
-- ============================================================================

alter table plantas_pedidos add column if not exists creado_por text;

comment on column plantas_pedidos.creado_por is
  'Email (auth.email()) de quien creó el pedido — se completa en crear_pedido(). Permite que encargado/supervisor editen/posterguen SOLO los pedidos que ellos mismos crearon (migración 41); admin/plantista mantienen alcance global sin depender de este campo.';

-- Backfill (2026-09-17, autorizado por Federico): reconstruye el creador
-- real de los 198 pedidos existentes desde el primer evento 'solicitado'
-- de su historial — no es un dato inventado, es el mismo usuario_legado
-- que crear_pedido() ya graba ahí desde siempre.
with primer_evento as (
  select distinct on (pedido_id) pedido_id, usuario_legado
  from plantas_pedidos_historial
  where estado = 'solicitado' and usuario_legado is not null
  order by pedido_id, fecha_evento asc
)
update plantas_pedidos p
set creado_por = e.usuario_legado
from primer_evento e
where e.pedido_id = p.id and p.creado_por is null;

-- ----------------------------------------------------------------------------
-- crear_pedido() — agrega creado_por = auth.email() al insert. Firma sin
-- cambios.
-- ----------------------------------------------------------------------------
create or replace function crear_pedido(
  p_formula_id uuid,
  p_cantidad_solicitada numeric,
  p_fecha_programada date,
  p_obra_id bigint default null,
  p_tipo_pedido text default 'obra',
  p_cliente_externo text default null,
  p_encargado text default null,
  p_ubicacion text default null,
  p_observaciones text default null,
  p_usuario_legado text default null
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
    tipo_pedido, cliente_externo, encargado, ubicacion, observaciones, estado, creado_por
  ) values (
    p_obra_id, p_formula_id, v_tipo, p_cantidad_solicitada, p_fecha_programada,
    p_tipo_pedido, p_cliente_externo, p_encargado, p_ubicacion, p_observaciones, 'solicitado', auth.email()
  )
  returning * into v_pedido;

  insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id, usuario_legado)
  values (v_pedido.id, 'solicitado', now(), auth.uid(), coalesce(p_usuario_legado, auth.email()));

  return v_pedido;
end;
$$;

-- ----------------------------------------------------------------------------
-- actualizar_pedido() — agrega el chequeo de "dueño" para roles que no son
-- admin/plantista. Firma sin cambios.
-- ----------------------------------------------------------------------------
create or replace function actualizar_pedido(
  p_pedido_id uuid,
  p_formula_id uuid,
  p_cantidad_solicitada numeric,
  p_fecha_programada date,
  p_obra_id bigint default null,
  p_tipo_pedido text default 'obra',
  p_cliente_externo text default null,
  p_encargado text default null,
  p_ubicacion text default null,
  p_observaciones text default null
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

  if plantas_rol_actual() not in ('admin', 'plantista')
     and coalesce(v_pedido.creado_por, '') <> coalesce(auth.email(), '') then
    raise exception 'Solo podés editar los pedidos que vos mismo creaste.';
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

-- ----------------------------------------------------------------------------
-- postergar_pedido() — antes solo plantista/admin (pedidos.aprobar) podían
-- postergar. Ahora también puede el creador del pedido, si su rol tiene
-- permiso de CREAR pedidos (pedidos.crear — hoy encargado/supervisor).
-- Firma sin cambios.
-- ----------------------------------------------------------------------------
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
  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;

  if not (
    plantas_tiene_permiso('pedidos', 'aprobar')
    or (plantas_tiene_permiso('pedidos', 'crear') and coalesce(v_pedido.creado_por, '') = coalesce(auth.email(), ''))
  ) then
    raise exception 'Tu rol (%) no puede postergar este pedido.', coalesce(plantas_rol_actual(), 'sin rol asignado');
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

comment on function actualizar_pedido is
  'Edita un pedido solicitado/confirmado. Admin/plantista: alcance global. Cualquier otro rol con permiso de editar (encargado/supervisor): solo si creado_por = auth.email() (migración 41).';
comment on function postergar_pedido is
  'Posterga un pedido solicitado/confirmado/postergado. Admin/plantista: alcance global (pedidos.aprobar). Cualquier rol con permiso de crear pedidos (encargado/supervisor): solo el pedido que él mismo creó (migración 41) — antes solo plantista/admin podían postergar, nadie más.';
