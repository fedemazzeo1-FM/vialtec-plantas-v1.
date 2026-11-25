-- ============================================================================
-- Migración 79: Ingreso de insumos contra un pedido de Flota — 25/11/2026,
-- pedido de Federico + propuesta de la sesión de Flota ("vincular después").
-- Proyecto Supabase compartido con Flota (ejitztewkpnmrckwmvny).
--
-- Reglas (Federico, 25/11):
--   - Puerta "Ingreso Áridos" de Báscula: campo OPCIONAL "Pedido de Flota".
--     Sin pedido, todo igual que siempre (registrar_pesada_bascula, sin tocar).
--   - Una pesada suma a UN solo ítem: vínculo + camiones_recibidos +1 +
--     cantidad_real + neto (convertido a la unidad del ítem, TN o KG).
--   - Plantas NO cierra nada (estado_item / estado del pedido los maneja Flota).
--   - Stock: la regla de siempre (cantidad del remito), sin cambios.
--   - Flota puede vincular después una pesada sin pedido (últimos 7 días) y
--     desvincular mientras el pedido no esté cerrado: resta.
--   - Si se anula una pesada vinculada, se resta del ítem.
--   - Si al guardar en balanza el ítem ya no está pendiente (lo recibió
--     Alejandro), la pesada queda guardada SIN pedido.
--   - Sin foto ni avisos nuevos. Fuel oil: sin cambios (sigue en L → no se ofrece).
--
-- Cambios:
--   flota_pedido_item_ingresos_planta (tabla de Flota, hoy vacía, propuesta de
--     Flota): + cantidad_sumada (lo que se sumó, para restar exacto aunque
--     después se corrija el vale) + UNIQUE (ingreso_id).
--   plantas_auditoria_entidades: + bascula/vinculo_flota.
--   Funciones nuevas (SECURITY DEFINER):
--     plantas_pedidos_flota_pendientes()                    balanza: desplegable
--     registrar_ingreso_pedido_flota(...)                   balanza: pesada + vínculo
--     vincular_pesada_pedido_flota(p_ingreso_id, p_flota_item_id)        balanza y Flota
--     pesadas_sin_pedido_flota(p_flota_item_id, p_dias default 7)        Flota
--     desvincular_pesada_pedido_flota(p_ingreso_id, p_motivo)            Flota
--     plantas_restar_pesada_de_item(...)  interna (sin EXECUTE)
--     plantas_trg_ingreso_anulado_flota() + trigger en plantas_ingresos.anulado
--   Quién puede (vincular / listar / desvincular): rol de Plantas admin,
--   plantista o balancero, o usuario activo de Flota (fn_flota_es_usuario, el
--   mismo control que usan las tablas de pedidos de Flota).
--
-- No modifica registrar_pesada_bascula, anular_vale_bascula ni
-- corregir_vale_bascula. Limitación aceptada: corregir el neto de un vale ya
-- vinculado no recalcula lo sumado (al restar se usa cantidad_sumada).
--
-- Ensayo: supabase/scripts/dry_run_migracion_79.sql
-- Vuelta atrás: supabase/scripts/revertir_migracion_79.sql
-- ============================================================================

alter table public.flota_pedido_item_ingresos_planta
  add column cantidad_sumada numeric,
  add constraint flota_pedido_item_ingresos_planta_ingreso_unico unique (ingreso_id);

insert into plantas_auditoria_entidades (modulo, entidad, modulo_etiqueta, entidad_etiqueta, orden)
values ('bascula', 'vinculo_flota', 'Báscula', 'Pesada en pedido de Flota', 24);

-- Quién puede vincular/desvincular/listar: Plantas (balanza) o Flota (compras).
create or replace function public.plantas_puede_vincular_flota()
returns boolean language sql stable security definer set search_path to 'public'
as $f$
  select coalesce(plantas_rol_actual(), '') in ('admin', 'plantista', 'balancero') or fn_flota_es_usuario()
$f$;

-- ---------------------------------------------------------------------------
-- Listado para la puerta de Ingreso.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- LA función que suma una pesada a un ítem (balanza y Flota).
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Interna: resta una pesada vinculada de su ítem y borra el vínculo.
-- La usan desvincular (Flota) y el trigger de anulación.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Flota: desvincular (mientras el pedido no esté cerrado). Resta.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Flota: pesadas de balanza sin pedido, del material del ítem, últimos N días.
-- ---------------------------------------------------------------------------
create or replace function public.pesadas_sin_pedido_flota(p_flota_item_id uuid, p_dias integer default 7)
returns table (
  ingreso_id uuid, fecha timestamptz, numero_vale text, proveedor text, numero_remito text,
  cantidad_remito_tn numeric, neto numeric, unidad text, patente text
)
language plpgsql stable security definer set search_path to 'public'
as $f$
declare
  v_item flota_pedido_items;
begin
  if not plantas_puede_vincular_flota() then
    raise exception 'No tenés permiso para ver las pesadas de balanza.';
  end if;
  select * into v_item from flota_pedido_items where id = p_flota_item_id;
  if not found or v_item.material_planta_id is null then return; end if;

  return query
  select g.id, g.fecha_ingreso, 'I-' || v.numero_vale_arido, g.proveedor, g.numero_remito, g.cantidad,
         round(case when upper(v_item.unidad) = 'KG'
                    then (case when coalesce(v.unidad, 'tn') = 'kg' then v.peso_neto else v.peso_neto * 1000 end)
                    else (case when coalesce(v.unidad, 'tn') = 'kg' then v.peso_neto / 1000 else v.peso_neto end) end, 3),
         upper(v_item.unidad), v.patente
    from plantas_ingresos g
    join plantas_vales v on v.id = g.vale_id
   where plantas_buscar_material_id(g.material) = v_item.material_planta_id
     and not coalesce(g.anulado, false) and not coalesce(v.anulado, false)
     and g.fecha_ingreso >= now() - make_interval(days => greatest(coalesce(p_dias, 7), 1))
     and not exists (select 1 from flota_pedido_item_ingresos_planta l where l.ingreso_id = g.id)
   order by g.fecha_ingreso desc;
end;
$f$;

-- ---------------------------------------------------------------------------
-- Balanza: pesada de ingreso + vínculo en una sola transacción. Si el ítem ya
-- no está pendiente (o el pedido ya no está en compras), la pesada se guarda
-- igual, SIN pedido. Material distinto = error (no se guarda nada).
-- Devuelve {vale_id, vinculado, aviso}.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Anular una pesada vinculada resta del ítem (anular_vale_bascula marca
-- plantas_ingresos.anulado; no se modifica esa función).
-- ---------------------------------------------------------------------------
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

create trigger plantas_ingresos_anulado_flota
  after update of anulado on public.plantas_ingresos
  for each row execute function public.plantas_trg_ingreso_anulado_flota();

-- Permisos: nada para anon; internas sin EXECUTE para la app.
revoke execute on function public.plantas_puede_vincular_flota() from public, anon;
grant  execute on function public.plantas_puede_vincular_flota() to authenticated;
revoke execute on function public.plantas_pedidos_flota_pendientes() from public, anon;
grant  execute on function public.plantas_pedidos_flota_pendientes() to authenticated;
revoke execute on function public.vincular_pesada_pedido_flota(uuid, uuid) from public, anon;
grant  execute on function public.vincular_pesada_pedido_flota(uuid, uuid) to authenticated;
revoke execute on function public.desvincular_pesada_pedido_flota(uuid, text) from public, anon;
grant  execute on function public.desvincular_pesada_pedido_flota(uuid, text) to authenticated;
revoke execute on function public.pesadas_sin_pedido_flota(uuid, integer) from public, anon;
grant  execute on function public.pesadas_sin_pedido_flota(uuid, integer) to authenticated;
revoke execute on function public.registrar_ingreso_pedido_flota(uuid, numeric, numeric, text, text, text, numeric, text, text, text, timestamptz) from public, anon;
grant  execute on function public.registrar_ingreso_pedido_flota(uuid, numeric, numeric, text, text, text, numeric, text, text, text, timestamptz) to authenticated;
revoke execute on function public.plantas_restar_pesada_de_item(uuid, text, boolean) from public, anon, authenticated;
revoke execute on function public.plantas_trg_ingreso_anulado_flota() from public, anon, authenticated;
