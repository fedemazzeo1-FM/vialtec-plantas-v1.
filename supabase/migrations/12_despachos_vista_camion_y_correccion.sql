-- ============================================================================
-- Migración 12: Módulo Despachos — corrección de plantas_v_despachos_camion
-- (gap #12 del diagnóstico) + corregir_despacho (edición post-despacho)
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Origen: memory/relevamiento-sistema-viejo.md §3 + auditoría de Despachos
-- contra Logica sis. plantas v1.rtf/v2.rtf. Aprobado por Federico (sesión
-- 2026-08-31).
--
-- Aclaración de flujo operativo real (Federico, misma sesión, corrigiendo un
-- diseño previo de este archivo que forzaba deduplicación): Báscula
-- (plantas_vales) es el detalle auditable camión por camión del pesaje real.
-- Pedidos (plantas_cargas_asfalto/hormigon + plantas_pedidos.cantidad_despachada)
-- es donde se cierra el despacho con la cantidadReal tomada del remito final
-- consolidado. Son dos registros con propósito distinto, no el mismo dato
-- contado dos veces — por eso el fix de acá NO deduplica nada: solo agrega
-- la fuente que faltaba a la vista de detalle, y la cantidad oficial de un
-- despacho para el módulo Despachos sigue siendo SIEMPRE
-- plantas_pedidos.cantidad_despachada (nunca una suma sobre esta vista).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) plantas_v_despachos_camion (gap #12) — la vista (migración 05) nunca se
--    actualizó cuando se agregó plantas_cargas_asfalto (migración 09): un
--    despacho de asfalto declarado desde Pedidos que todavía no fue pesado en
--    Báscula no aparecía acá. Se agrega como tercer UNION, sin excluir ni
--    reconciliar contra plantas_vales a propósito (ver aclaración arriba) —
--    esta vista es SOLO el detalle auditable por camión (Dashboard, modal
--    "Detalle de cargas"), no la fuente de ningún total oficial.
-- ----------------------------------------------------------------------------
create or replace view plantas_v_despachos_camion as
  select
    'asfalto'::text as material,
    v.fecha_pesada  as fecha,
    v.obra_id,
    v.pedido_id,
    v.patente,
    v.chofer,
    v.numero_vale::text as numero_remito,
    v.peso_neto     as volumen,
    v.unidad        as unidad_volumen
  from plantas_vales v
  where v.tipo_vale = 'asfalto'

  union all

  select
    'asfalto'::text as material,
    ca.fecha_carga  as fecha,
    ca.obra_id,
    ca.pedido_id,
    ca.patente,
    null::text      as chofer,
    ca.numero_vale  as numero_remito,
    ca.cantidad_tn  as volumen,
    'tn'::text      as unidad_volumen
  from plantas_cargas_asfalto ca

  union all

  select
    'hormigon'::text as material,
    c.fecha_carga    as fecha,
    c.obra_id,
    c.pedido_id,
    c.patente_mixer  as patente,
    c.chofer,
    c.numero_remito,
    c.volumen_m3     as volumen,
    'm3'::text       as unidad_volumen
  from plantas_cargas_hormigon c;

comment on view plantas_v_despachos_camion is
  'Detalle auditable por camión: asfalto pesado en Báscula (plantas_vales) + asfalto declarado en Pedidos (plantas_cargas_asfalto) + hormigón (plantas_cargas_hormigon). A propósito SIN deduplicar entre las dos fuentes de asfalto (Federico, 2026-08-31): son registros de propósito distinto, no el mismo camión contado dos veces. NO es la fuente de la cantidad oficial despachada de un pedido — esa es siempre plantas_pedidos.cantidad_despachada. Ver src/modules/analytics/services/analytics.service.js y src/services/despachos.service.js.';

-- ----------------------------------------------------------------------------
-- 2) plantas_pedidos_historial: se agrega 'corregido' como valor de estado
--    válido SOLO en esta tabla (auditoría), distinto de los 5 estados reales
--    de plantas_pedidos — una corrección post-despacho no cambia el estado
--    del pedido (sigue despachado), así que reusar 'despachado' para el
--    evento lo haría indistinguible del cierre original.
-- ----------------------------------------------------------------------------
alter table plantas_pedidos_historial
  drop constraint plantas_pedidos_historial_estado_check;

alter table plantas_pedidos_historial
  add constraint plantas_pedidos_historial_estado_check
  check (estado in ('solicitado', 'confirmado', 'despachado', 'postergado', 'cancelado', 'corregido'));

-- ----------------------------------------------------------------------------
-- 3) corregir_despacho — Logica sis. plantas v1.rtf §5 ("Solo plantista y
--    admin pueden editar cantidadReal después del despacho. Sirve para
--    correcciones post-hecho") + v1.rtf §4.5 / v2.rtf §3.5 ("Permite editar
--    cantidadReal, remito, vale, notas de un despacho ya registrado"). Solo
--    sobre pedidos ya 'despachado'; no reabre el pedido ni recalcula
--    cargas/vales — pisa directamente los 3 campos consolidados del pedido
--    (cantidadReal tomada del remito final, remito global, vale global) y
--    dos deja auditado en el historial con el valor anterior y el nuevo.
-- ----------------------------------------------------------------------------
create or replace function corregir_despacho(
  p_pedido_id           uuid,
  p_cantidad_despachada numeric default null,
  p_nro_remito_global   text default null,
  p_nro_vale_global     text default null,
  p_notas               text default null
)
returns plantas_pedidos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol    text;
  v_pedido plantas_pedidos;
  v_diff   jsonb;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista', 'plantista_hormigon') then
    raise exception 'Tu rol (%) no puede corregir un despacho.', coalesce(v_rol, 'sin rol asignado');
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

  v_diff := jsonb_build_object(
    'cantidad_despachada', jsonb_build_object(
      'anterior', v_pedido.cantidad_despachada,
      'nueva', coalesce(p_cantidad_despachada, v_pedido.cantidad_despachada)
    ),
    'nro_remito_global', jsonb_build_object(
      'anterior', v_pedido.nro_remito_global,
      'nuevo', coalesce(p_nro_remito_global, v_pedido.nro_remito_global)
    ),
    'nro_vale_global', jsonb_build_object(
      'anterior', v_pedido.nro_vale_global,
      'nuevo', coalesce(p_nro_vale_global, v_pedido.nro_vale_global)
    )
  );

  update plantas_pedidos
    set cantidad_despachada = coalesce(p_cantidad_despachada, cantidad_despachada),
        nro_remito_global   = coalesce(p_nro_remito_global, nro_remito_global),
        nro_vale_global     = coalesce(p_nro_vale_global, nro_vale_global)
    where id = p_pedido_id;

  insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id, motivo, datos_legados)
  values (p_pedido_id, 'corregido', now(), auth.uid(), p_notas, v_diff);

  select * into v_pedido from plantas_pedidos where id = p_pedido_id;
  return v_pedido;
end;
$$;

comment on function corregir_despacho is
  'Edita cantidadReal/remito/vale/notas de un despacho ya cerrado (solo plantista/admin) y deja el valor anterior/nuevo auditado en plantas_pedidos_historial como evento ''corregido''. Logica sis. plantas v1.rtf §5.';

revoke execute on function corregir_despacho(uuid, numeric, text, text, text) from public;
grant execute on function corregir_despacho(uuid, numeric, text, text, text) to authenticated;
