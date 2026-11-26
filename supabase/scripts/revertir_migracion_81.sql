-- ============================================================================
-- Vuelta atrás de la migración 81 (cierre automático de pedidos Plantas).
-- Deja vincular / restar / desvincular como en la 79, el helper de "completo" y
-- registrar_ingreso_pedido_flota como en la 80, borra los permisos de "vincular después" y el aviso de pesada sin pedido
-- (el trigger de anulación vuelve a la 79), y borra la tabla plantas_cierres_flota y las funciones nuevas.
-- NO deshace datos de Flota: los ítems que la balanza dejó "recibido" y los
-- pedidos que cerró quedan así (Alejandro los maneja a mano, como antes).
-- Antes de correrla, guardar el listado:  select * from plantas_cierres_flota;
-- ============================================================================
begin;
set local lock_timeout = '5s';
create or replace function public.vincular_pesada_pedido_flota(p_ingreso_id uuid, p_flota_item_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $f$
declare
  v_ing    plantas_ingresos;
  v_vale   plantas_vales;
  v_item   flota_pedido_items;
  v_pedido flota_pedidos;
  v_mat    text;
  v_neto   numeric;
begin
  if not plantas_puede_vincular_flota() then
    raise exception 'No tenés permiso para vincular pesadas a pedidos de Flota.';
  end if;

  select * into v_item from flota_pedido_items where id = p_flota_item_id for update;
  if not found then raise exception 'El ítem del pedido de Flota no existe.'; end if;
  select * into v_pedido from flota_pedidos where id = v_item.pedido_id;
  if v_pedido.modulo is distinct from 'plantas' then
    raise exception 'El pedido % no es un pedido de Plantas.', v_pedido.numero;
  end if;
  if v_pedido.estado not in ('en_compras', 'parcialmente_abierto') then
    raise exception 'El pedido % está % — no recibe pesadas.', v_pedido.numero, v_pedido.estado;
  end if;
  if v_item.estado_item is distinct from 'pendiente' then
    raise exception 'El ítem del pedido % ya está % — no recibe pesadas.', v_pedido.numero, v_item.estado_item;
  end if;
  if upper(coalesce(v_item.unidad, '')) not in ('TN', 'KG') then
    raise exception 'El ítem del pedido % está en %: solo se suman pesadas a ítems en TN o KG.', v_pedido.numero, coalesce(v_item.unidad, 'sin unidad');
  end if;

  select * into v_ing from plantas_ingresos where id = p_ingreso_id for update;
  if not found or v_ing.vale_id is null then raise exception 'La pesada no existe o no es de balanza.'; end if;
  select * into v_vale from plantas_vales where id = v_ing.vale_id;
  if coalesce(v_ing.anulado, false) or coalesce(v_vale.anulado, false) then
    raise exception 'La pesada (vale I-%) está anulada.', v_vale.numero_vale_arido;
  end if;
  if exists (select 1 from flota_pedido_item_ingresos_planta where ingreso_id = p_ingreso_id) then
    raise exception 'La pesada (vale I-%) ya está vinculada a un pedido.', v_vale.numero_vale_arido;
  end if;

  select nombre into v_mat from plantas_materiales where id = v_item.material_planta_id;
  if v_mat is null or plantas_buscar_material_id(v_ing.material) is distinct from v_item.material_planta_id then
    raise exception 'El pedido % es de %, la pesada es de %.', v_pedido.numero, coalesce(v_mat, 'otro material'), v_ing.material;
  end if;

  v_neto := case when coalesce(v_vale.unidad, 'tn') = 'kg' then v_vale.peso_neto / 1000 else v_vale.peso_neto end;  -- tn
  v_neto := round(case when upper(v_item.unidad) = 'KG' then v_neto * 1000 else v_neto end, 3);                  -- unidad del ítem

  insert into flota_pedido_item_ingresos_planta (item_id, ingreso_id, creado_por, cantidad_sumada)
  values (v_item.id, p_ingreso_id, auth.email(), v_neto);

  update flota_pedido_items
     set camiones_recibidos = coalesce(camiones_recibidos, 0) + 1,
         cantidad_real      = coalesce(cantidad_real, 0) + v_neto
   where id = v_item.id
   returning * into v_item;

  perform plantas_auditar('CREAR', 'bascula', 'vinculo_flota', p_ingreso_id::text,
    'Vale I-' || v_vale.numero_vale_arido || ' → ' || v_pedido.numero, null, null,
    jsonb_build_object('pedido', v_pedido.numero, 'material', v_mat, 'sumado', v_neto, 'unidad', upper(v_item.unidad),
                       'camiones_recibidos', v_item.camiones_recibidos, 'cantidad_real', v_item.cantidad_real));

  return jsonb_build_object('item_id', v_item.id, 'pedido', v_pedido.numero, 'sumado', v_neto,
                            'camiones_recibidos', v_item.camiones_recibidos, 'cantidad_real', v_item.cantidad_real);
end;
$f$;

create or replace function public.plantas_restar_pesada_de_item(p_ingreso_id uuid, p_motivo text, p_por_anulacion boolean)
returns void language plpgsql security definer set search_path to 'public'
as $f$
declare
  v_link    flota_pedido_item_ingresos_planta;
  v_item    flota_pedido_items;
  v_numero  text;
  v_vale_n  bigint;
  v_quedan  int;
  v_cam     int;
  v_cant    numeric;
begin
  select * into v_link from flota_pedido_item_ingresos_planta where ingreso_id = p_ingreso_id;
  if not found then return; end if;
  select * into v_item from flota_pedido_items where id = v_link.item_id for update;
  select numero into v_numero from flota_pedidos where id = v_item.pedido_id;
  select v.numero_vale_arido into v_vale_n from plantas_ingresos g join plantas_vales v on v.id = g.vale_id where g.id = p_ingreso_id;

  delete from flota_pedido_item_ingresos_planta where ingreso_id = p_ingreso_id;
  select count(*) into v_quedan from flota_pedido_item_ingresos_planta where item_id = v_item.id;

  v_cam  := greatest(coalesce(v_item.camiones_recibidos, 0) - 1, 0);
  v_cant := greatest(coalesce(v_item.cantidad_real, 0) - coalesce(v_link.cantidad_sumada, 0), 0);
  -- Un ítem por camión ya recibido no puede quedar con 0 camiones (regla de Flota).
  if v_item.pedido_por = 'camion' and v_item.estado_item = 'recibido' then v_cam := greatest(v_cam, 1); end if;
  -- Sin vínculos y en 0: vuelve a vacío, como antes de la primera pesada.
  if v_quedan = 0 and v_cant = 0 then v_cant := null; end if;
  if v_quedan = 0 and v_cam = 0 then v_cam := null; end if;

  update flota_pedido_items set camiones_recibidos = v_cam, cantidad_real = v_cant where id = v_item.id;

  perform plantas_auditar('ELIMINAR', 'bascula', 'vinculo_flota', p_ingreso_id::text,
    'Vale I-' || v_vale_n || ' → ' || v_numero,
    coalesce(p_motivo, case when p_por_anulacion then 'Pesada anulada' end),
    jsonb_build_object('pedido', v_numero, 'sumado', v_link.cantidad_sumada,
                       'camiones_recibidos', v_item.camiones_recibidos, 'cantidad_real', v_item.cantidad_real),
    jsonb_build_object('camiones_recibidos', v_cam, 'cantidad_real', v_cant, 'por_anulacion', p_por_anulacion));
end;
$f$;

create or replace function public.desvincular_pesada_pedido_flota(p_ingreso_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path to 'public'
as $f$
declare
  v_estado text;
  v_numero text;
begin
  if not plantas_puede_vincular_flota() then
    raise exception 'No tenés permiso para desvincular pesadas de pedidos de Flota.';
  end if;
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'El motivo es obligatorio para desvincular una pesada.';
  end if;
  select p.estado, p.numero into v_estado, v_numero
    from flota_pedido_item_ingresos_planta l
    join flota_pedido_items i on i.id = l.item_id
    join flota_pedidos p on p.id = i.pedido_id
   where l.ingreso_id = p_ingreso_id;
  if not found then raise exception 'La pesada no está vinculada a ningún pedido.'; end if;
  if v_estado not in ('en_compras', 'parcialmente_abierto') then
    raise exception 'El pedido % está % — ya no se puede desvincular.', v_numero, v_estado;
  end if;
  perform plantas_restar_pesada_de_item(p_ingreso_id, btrim(p_motivo), false);
end;
$f$;

create or replace function public.plantas_item_flota_completo(i flota_pedido_items)
returns boolean language sql immutable set search_path to 'public'
as $f$
  select case
    when i.pedido_por = 'camion'   then i.camiones is not null and coalesce(i.camiones_recibidos, 0) >= i.camiones
    when i.pedido_por = 'cantidad' then i.cantidad is not null and coalesce(i.cantidad_real, 0) >= i.cantidad
    else false
  end
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
  v_motivo     text;
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
     and v_item.estado_item = 'pendiente' and upper(coalesce(v_item.unidad, '')) in ('TN', 'KG')
     and not plantas_item_flota_completo(v_item) then
    perform vincular_pesada_pedido_flota(v_ingreso_id, v_item.id);
    return jsonb_build_object('vale_id', v_vale.id, 'vinculado', true, 'aviso', null);
  end if;

  v_motivo := case
    when v_item.estado_item <> 'pendiente' then 'ítem ' || v_item.estado_item
    when v_pedido.estado not in ('en_compras', 'parcialmente_abierto') then 'pedido ' || v_pedido.estado
    when plantas_item_flota_completo(v_item) and v_item.pedido_por = 'camion' then
      case when v_item.camiones = 1 then 'ya tiene su camión' else format('ya tiene sus %s camiones', v_item.camiones) end
    when plantas_item_flota_completo(v_item) then
      format('ya tiene sus %s %s', replace(trim_scale(v_item.cantidad)::text, '.', ','), upper(v_item.unidad))
    else 'pedido ' || v_pedido.estado
  end;
  v_aviso := format('Pesada I-%s guardada SIN pedido: el pedido %s ya no la recibe (%s). Compras puede vincularla desde Flota.',
                    v_vale.numero_vale_arido, v_pedido.numero, v_motivo);
  return jsonb_build_object('vale_id', v_vale.id, 'vinculado', false, 'aviso', v_aviso);
end;
$f$;

create or replace function public.plantas_trg_ingreso_anulado_flota()
returns trigger language plpgsql security definer set search_path to 'public'
as $f$
begin
  if new.anulado and not coalesce(old.anulado, false) then
    perform plantas_restar_pesada_de_item(new.id, null, true);
  end if;
  return new;
end;
$f$;

drop trigger if exists plantas_ingresos_sin_pedido_flota on public.plantas_ingresos;
drop function if exists public.plantas_trg_ingreso_sin_pedido_flota();
drop function if exists public.pesadas_de_pedido_flota(uuid);
drop function if exists public.plantas_vincular_pesada_interna(uuid, uuid);
drop function if exists public.plantas_puede_vincular_despues();
drop table if exists public.plantas_vinculo_flota_autorizados;
drop function if exists public.plantas_cerrar_item_flota_si_completo(uuid);
drop function if exists public.plantas_recalcular_pedido_flota(uuid);
drop table if exists public.plantas_cierres_flota;
delete from public.plantas_auditoria_entidades e
 where e.modulo = 'bascula' and e.entidad = 'cierre_flota'
   and not exists (select 1 from public.plantas_auditoria a where a.modulo = 'bascula' and a.entidad = 'cierre_flota');
commit;
