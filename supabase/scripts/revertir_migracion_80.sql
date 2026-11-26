-- ============================================================================
-- Vuelta atrás de la migración 80: deja plantas_pedidos_flota_pendientes y
-- registrar_ingreso_pedido_flota exactamente como en la 79 y borra el helper.
-- No toca datos (vales, ingresos, vínculos y lo sumado en Flota quedan).
-- ============================================================================
begin;
set local lock_timeout = '5s';
create or replace function public.plantas_pedidos_flota_pendientes()
returns table (
  item_id uuid, pedido_numero text, pedido_fecha date, material text, unidad text, pedido_por text,
  cantidad numeric, camiones integer, camiones_recibidos integer, cantidad_real numeric, proveedor text,
  ingresos_balanza integer
)
language plpgsql stable security definer set search_path to 'public'
as $f$
begin
  if coalesce(plantas_rol_actual(), '') not in ('admin', 'plantista', 'balancero') then
    raise exception 'Tu rol (%) no puede ver los pedidos de Flota para ingresar.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;
  return query
  select i.id, p.numero, p.fecha, m.nombre, upper(i.unidad), i.pedido_por, i.cantidad, i.camiones,
         i.camiones_recibidos, i.cantidad_real, i.proveedor,
         (select count(*)::int from flota_pedido_item_ingresos_planta l where l.item_id = i.id)
    from flota_pedido_items i
    join flota_pedidos p on p.id = i.pedido_id
    join plantas_materiales m on m.id = i.material_planta_id
   where p.modulo = 'plantas' and p.estado in ('en_compras', 'parcialmente_abierto')
     and i.estado_item = 'pendiente' and upper(i.unidad) in ('TN', 'KG')
   order by p.fecha, p.numero, m.nombre;
end;
$f$;

create or replace function public.registrar_ingreso_pedido_flota(
  p_flota_item_id uuid, p_peso_bruto numeric, p_tara numeric, p_material text, p_proveedor text,
  p_numero_remito text, p_cantidad_remito numeric, p_patente text default null, p_unidad text default 'tn',
  p_observaciones text default null, p_fecha_pesada timestamptz default now()
)
returns jsonb language plpgsql security definer set search_path to 'public'
as $f$
declare
  v_item       flota_pedido_items;
  v_pedido     flota_pedidos;
  v_vale       plantas_vales;
  v_ingreso_id uuid;
  v_aviso      text;
begin
  if coalesce(plantas_rol_actual(), '') not in ('admin', 'plantista', 'balancero') then
    raise exception 'Tu rol (%) no puede registrar pesadas de báscula.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  select * into v_item from flota_pedido_items where id = p_flota_item_id for update;
  if not found then raise exception 'El ítem del pedido de Flota no existe.'; end if;
  select * into v_pedido from flota_pedidos where id = v_item.pedido_id;
  if plantas_buscar_material_id(p_material) is distinct from v_item.material_planta_id then
    raise exception 'El pedido % es de %, no de %.', v_pedido.numero,
      coalesce((select nombre from plantas_materiales where id = v_item.material_planta_id), 'otro material'), p_material;
  end if;

  v_vale := registrar_pesada_bascula(
    p_tipo_vale => 'ingreso_arido', p_peso_bruto => p_peso_bruto, p_tara => p_tara, p_patente => p_patente,
    p_unidad => coalesce(p_unidad, 'tn'), p_observaciones => p_observaciones, p_fecha_pesada => coalesce(p_fecha_pesada, now()),
    p_material => p_material, p_proveedor => p_proveedor, p_numero_remito => p_numero_remito, p_cantidad_remito => p_cantidad_remito);
  select id into v_ingreso_id from plantas_ingresos where vale_id = v_vale.id;

  if v_pedido.modulo = 'plantas' and v_pedido.estado in ('en_compras', 'parcialmente_abierto')
     and v_item.estado_item = 'pendiente' and upper(coalesce(v_item.unidad, '')) in ('TN', 'KG') then
    perform vincular_pesada_pedido_flota(v_ingreso_id, v_item.id);
    return jsonb_build_object('vale_id', v_vale.id, 'vinculado', true, 'aviso', null);
  end if;

  v_aviso := format('Pesada I-%s guardada SIN pedido: el pedido %s ya no la recibe (%s). Compras puede vincularla desde Flota.',
                    v_vale.numero_vale_arido, v_pedido.numero,
                    case when v_item.estado_item <> 'pendiente' then 'ítem ' || v_item.estado_item else 'pedido ' || v_pedido.estado end);
  return jsonb_build_object('vale_id', v_vale.id, 'vinculado', false, 'aviso', v_aviso);
end;
$f$;

drop function if exists public.plantas_item_flota_completo(flota_pedido_items);
commit;
