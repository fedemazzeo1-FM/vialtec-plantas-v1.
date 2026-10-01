-- ============================================================================
-- Migración 49: tercer tipo de producto, 'mezcla_cemento'
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Pedido de Federico (2026-10-01): la mezcla cemento no es asfalto ni
-- hormigón. Es un tipo propio, siempre independiente en totales y reportes:
--   asfalto        -> se pesa en báscula, en tn
--   hormigon       -> sale en mixer con remito por carga, en m³
--   mezcla_cemento -> sale igual que el hormigón (remito por carga, sin
--                     báscula), pero se mide en tn
--
-- Qué cambia:
--   1) plantas_formulas.tipo y plantas_pedidos.tipo aceptan 'mezcla_cemento'.
--   2) registrar_carga_hormigon() acepta pedidos de mezcla cemento (mismo
--      circuito de despacho). plantas_cargas_hormigon.volumen_m3 guarda la
--      cantidad en la unidad del pedido: m³ para hormigón, tn para mezcla
--      cemento (el nombre de la columna no cambia).
--      Roles: los mismos que hormigón (admin, plantista, plantista_hormigon).
--   3) registrar_carga_hormigon() deja de ser ejecutable por `anon` (mismo
--      criterio que las migraciones 46 y 47; ya validaba el rol adentro).
--
-- Qué NO cambia:
--   - finalizar_despacho(): el texto del residual ya escribe ' m³' solo para
--     hormigón y ' tn' para todo lo demás, así que mezcla cemento sale en tn
--     sin tocarla. El descuento de stock (insumo × cantidad despachada) no
--     depende del tipo.
--   - registrar_pesada_bascula() / registrar_carga_asfalto(): siguen
--     aceptando solo pedidos de asfalto. La mezcla cemento no pasa por báscula.
--   - plantas_vales.tipo_vale: es el tipo de VALE, otro concepto.
--   - Ninguna fila existente.
--
-- La regla "qué circuito y qué unidad tiene cada tipo" vive en el frontend en
-- src/config/tipos-producto.js. Estas funciones son su gemela SQL: si se
-- agrega un tipo, se cambia en los dos lados.
--
-- registrar_carga_hormigon parte de la definición REAL de producción
-- (pg_get_functiondef, 2026-10-01). Misma firma; solo cambia la validación
-- del tipo y su mensaje.
--
-- Reversión: volver los 2 CHECK a ('asfalto', 'hormigon') (falla si ya hay
-- filas 'mezcla_cemento': hay que reclasificarlas antes) y restaurar la línea
-- `if v_pedido.tipo <> 'hormigon'` en registrar_carga_hormigon.
-- ============================================================================

alter table plantas_formulas
  drop constraint plantas_formulas_tipo_check,
  add constraint plantas_formulas_tipo_check check (tipo in ('asfalto', 'hormigon', 'mezcla_cemento'));

alter table plantas_pedidos
  drop constraint plantas_pedidos_tipo_check,
  add constraint plantas_pedidos_tipo_check check (tipo in ('asfalto', 'hormigon', 'mezcla_cemento'));

create or replace function registrar_carga_hormigon(
  p_pedido_id uuid,
  p_numero_remito text,
  p_volumen_m3 numeric,
  p_patente_mixer text default null,
  p_chofer text default null,
  p_fecha_carga timestamptz default now(),
  p_observaciones text default null
)
returns plantas_cargas_hormigon
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_rol    text;
  v_pedido plantas_pedidos;
  v_carga  plantas_cargas_hormigon;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista', 'plantista_hormigon') then
    raise exception 'Tu rol (%) no puede registrar cargas de hormigón.', coalesce(v_rol, 'sin rol asignado');
  end if;

  if not (p_volumen_m3 > 0) then
    raise exception 'volumen_m3 debe ser mayor a 0';
  end if;
  if p_numero_remito is null or btrim(p_numero_remito) = '' then
    raise exception 'numero_remito es obligatorio';
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  -- Circuito "mixer" (remito por carga, sin báscula): hormigón y mezcla
  -- cemento. Gemela de src/config/tipos-producto.js.
  if v_pedido.tipo not in ('hormigon', 'mezcla_cemento') then
    raise exception 'El pedido no es de hormigón ni de mezcla cemento.';
  end if;
  if v_pedido.estado <> 'confirmado' then
    raise exception 'El pedido tiene que estar confirmado.';
  end if;

  insert into plantas_cargas_hormigon (
    pedido_id, obra_id, numero_remito, volumen_m3, patente_mixer, chofer, fecha_carga, observaciones
  ) values (
    v_pedido.id, v_pedido.obra_id, btrim(p_numero_remito), p_volumen_m3, p_patente_mixer, p_chofer, p_fecha_carga, p_observaciones
  )
  returning * into v_carga;

  update plantas_pedidos
    set cantidad_despachada = coalesce(v_pedido.cantidad_despachada, 0) + p_volumen_m3
    where id = p_pedido_id;

  return v_carga;
end;
$function$;

revoke execute on function registrar_carga_hormigon(uuid, text, numeric, text, text, timestamptz, text) from anon;
