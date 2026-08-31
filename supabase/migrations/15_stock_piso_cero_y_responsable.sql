-- ============================================================================
-- Migración 15: Stock nunca negativo (piso en 0) + Responsable en el
-- historial de movimientos
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Origen: relevamiento en vivo de Simulador/Stock contra produccion.vialtec.app
-- (sesión 2026-08-31). Dos hallazgos de esa pasada, aprobados por Federico:
--   1. Logica sis. plantas v1.rtf §5.3: "el stock nunca queda negativo, va a
--      0 como mínimo" (regla `max(0, ...)` del legado) — plantas_stock podía
--      quedar negativo, no estaba implementado.
--   2. El historial real de producción tiene columna RESPONSABLE (nombre de
--      persona) — plantas_stock_movimientos solo guardaba usuario_id (uuid),
--      sin forma de resolver un nombre desde el cliente (auth.users no se
--      expone vía API). Se agrega responsable_email, resuelto server-side
--      con auth.email() (mismo mecanismo que auth.uid(), sin parámetro
--      nuevo) — el cliente después lo cruza contra flota_usuarios_email
--      (memory/architecture.md: solo lectura sobre flota_*) para mostrar el
--      nombre, igual que ya hace auth.store.js con el usuario logueado.
-- ============================================================================

alter table plantas_stock_movimientos
  add column if not exists responsable_email text;

comment on column plantas_stock_movimientos.responsable_email is
  'Email de quien generó el movimiento (auth.email(), capturado server-side en plantas_aplicar_movimiento_stock). El cliente lo cruza contra flota_usuarios_email para mostrar el nombre — ver src/services/flota.service.js#fetchNombresPorEmail.';

create or replace function plantas_aplicar_movimiento_stock(
  p_material_id    uuid,
  p_tipo           text,
  p_cantidad_kg    numeric,
  p_origen         text default null,
  p_numero_remito  text default null,
  p_pedido_id      uuid default null,
  p_vale_id        uuid default null,
  p_ingreso_id     uuid default null,
  p_observaciones  text default null
)
returns plantas_stock_movimientos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mov            plantas_stock_movimientos;
  v_actual         numeric;
  v_nuevo          numeric;
  v_delta_aplicado numeric;
  v_observaciones  text := p_observaciones;
begin
  if p_cantidad_kg = 0 or p_material_id is null then
    return null;
  end if;

  insert into plantas_stock (material_id, cantidad_kg)
  values (p_material_id, 0)
  on conflict (material_id) do nothing;

  select cantidad_kg into v_actual from plantas_stock where material_id = p_material_id for update;

  -- Piso en 0 (Logica sis. plantas v1.rtf §5.3) — el delta REALMENTE
  -- aplicado puede ser menor al solicitado si el egreso excede el stock
  -- disponible. Se audita el delta aplicado (no el solicitado) para que
  -- sum(plantas_stock_movimientos.cantidad_kg) siempre reconcilie exacto
  -- contra plantas_stock.cantidad_kg — y se deja una nota en observaciones
  -- cuando hay recorte, para no perder esa información.
  v_nuevo := greatest(0, v_actual + p_cantidad_kg);
  v_delta_aplicado := v_nuevo - v_actual;

  if v_delta_aplicado = 0 then
    return null;
  end if;

  if v_delta_aplicado <> p_cantidad_kg then
    v_observaciones := coalesce(v_observaciones || ' — ', '')
      || format('consumo solicitado %s kg, aplicado %s kg (stock insuficiente, piso en 0)', p_cantidad_kg, v_delta_aplicado);
  end if;

  update plantas_stock
    set cantidad_kg = v_nuevo,
        actualizado_en = now()
    where material_id = p_material_id;

  insert into plantas_stock_movimientos (
    material_id, tipo, cantidad_kg, origen, numero_remito,
    pedido_id, vale_id, ingreso_id, observaciones, usuario_id, responsable_email
  ) values (
    p_material_id, p_tipo, v_delta_aplicado, p_origen, p_numero_remito,
    p_pedido_id, p_vale_id, p_ingreso_id, v_observaciones, auth.uid(), auth.email()
  )
  returning * into v_mov;

  return v_mov;
end;
$$;

comment on function plantas_aplicar_movimiento_stock is
  'Aplica un delta (con signo) a plantas_stock con piso en 0 (nunca negativo) e inserta el movimiento correspondiente con el delta REALMENTE aplicado (puede ser menor al solicitado si el stock no alcanza). Registra responsable_email vía auth.email(). Único punto de escritura de plantas_stock — llamado solo desde otras funciones SECURITY DEFINER que ya validaron rol.';
