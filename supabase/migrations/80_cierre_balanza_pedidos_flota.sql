-- ============================================================================
-- Migración 80: pedidos de Plantas cerrados por la balanza — 26/11/2026,
-- pedido de Federico (decisiones D1–D6) coordinado con la sesión de Flota.
-- Spec: vialtec-flota-v2/src/modules/pedidos/plantas-balanza.spec.md
-- REQUIERE ANTES la migración de Flota scripts/migraciones/pedidos_plantas_balanza.sql
-- (columnas cerrado_por_balanza/recibido_por_balanza, flota_avisos_compras y sus funciones).
--
--   plantas_flota_item_completo(ítem): por camión camiones_recibidos >= camiones;
--     por cantidad cantidad_real >= 95 % de lo pedido (D2).
--   vincular_pesada_pedido_flota: + ítem completo → recibido (proveedor y remitos
--     de las pesadas) y, sin ítems pendientes, pedido cerrado por la balanza
--     (vialtec.cierre_balanza = on → sale el mail a facturas). Resuelve avisos.
--   plantas_restar_pesada_de_item: lo que cerró la balanza se reabre si deja de
--     estar completo, con aviso a Compras (D4).
--   desvincular_pesada_pedido_flota: también en pedidos cerrados por la balanza.
--   plantas_trg_ingreso_anulado_flota: también descarta el aviso de pesada sin pedido.
--   pesadas_de_pedido_flota(p_pedido_id): detalle por camión para Flota.
--   Aviso "pesada sin pedido" (D6): constraint trigger diferido en plantas_ingresos
--     (al confirmar la transacción, así una pesada con pedido ya quedó vinculada).
--     Materiales: ASFALTO CA30, CEMENTO, FILLER, ASFALTO AM3, AM3 AUTOVIA, ADITIVO (D3).
-- No modifica registrar_pesada_bascula, anular_vale_bascula ni corregir_vale_bascula.
-- Ensayo: vialtec-flota-v2/scripts/migraciones/pedidos_plantas_balanza_ensayo.sql (las dos juntas)
-- Vuelta atrás: supabase/scripts/revertir_migracion_80.sql (antes que la de Flota)
-- ============================================================================

create function public.plantas_flota_item_completo(i public.flota_pedido_items)
returns boolean language sql immutable set search_path to 'public'
as $f$
  select case when i.pedido_por = 'camion' then coalesce(i.camiones_recibidos, 0) >= coalesce(i.camiones, 1)
              else coalesce(i.cantidad_real, 0) >= 0.95 * coalesce(i.cantidad, 0) and coalesce(i.cantidad, 0) > 0 end
$f$;

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
  v_d      record;
  v_item_rec boolean := false;
  v_cerro  boolean := false;
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

  -- 80 (26/11): la pesada vinculada resuelve sus avisos y, si el ítem quedó completo, la balanza lo da por recibido y
  -- cierra el pedido cuando no queda ningún ítem pendiente (marca vialtec.cierre_balanza: sale el mail a facturas).
  perform flota_aviso_compras_resolver_auto('pesada_sin_pedido', null, p_ingreso_id, 'Vinculada a ' || v_pedido.numero);
  perform flota_aviso_compras_resolver_auto('pedido_sin_camiones', v_pedido.id, null, 'Entró un camión (vale I-' || v_vale.numero_vale_arido || ')');
  if plantas_flota_item_completo(v_item) then
    select * into v_d from flota_item_datos_balanza(v_item.id);
    update flota_pedido_items
       set estado_item = 'recibido', recibido_por_balanza = true,
           proveedor = case when proveedor is null then v_d.proveedor else proveedor end,
           proveedor_id = case when proveedor is null then v_d.proveedor_id else proveedor_id end,
           nro_remito = coalesce(nullif(nro_remito, ''), v_d.remitos)
     where id = v_item.id;
    v_item_rec := true;
    if not exists (select 1 from flota_pedido_items where pedido_id = v_pedido.id and estado_item = 'pendiente') then
      perform set_config('vialtec.cierre_balanza', 'on', true);
      update flota_pedidos
         set estado = 'cerrado', fecha_cierre = (now() at time zone 'America/Argentina/Buenos_Aires')::date, cerrado_por_balanza = true
       where id = v_pedido.id;
      perform set_config('vialtec.cierre_balanza', 'off', true);
      perform flota_aviso_compras_resolver_auto('pedido_reabierto', v_pedido.id, null, 'Lo volvió a cerrar la balanza');
      v_cerro := true;
    elsif v_pedido.estado = 'en_compras' then
      update flota_pedidos set estado = 'parcialmente_abierto' where id = v_pedido.id;
    end if;
  end if;

  return jsonb_build_object('item_id', v_item.id, 'pedido', v_pedido.numero, 'sumado', v_neto,
                            'camiones_recibidos', v_item.camiones_recibidos, 'cantidad_real', v_item.cantidad_real,
                            'item_recibido', v_item_rec, 'pedido_cerrado', v_cerro);
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
  v_ped     flota_pedidos;
  v_reabre  boolean := false;
  v_nuevo   flota_pedido_items;
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
  -- 80: lo que dio por recibido la balanza vuelve a pendiente si deja de estar completo (D4). Un ítem por camión
  -- recibido a mano no puede quedar con 0 camiones (regla de Flota).
  v_nuevo := v_item;
  v_nuevo.camiones_recibidos := v_cam;
  v_nuevo.cantidad_real := v_cant;
  if v_item.estado_item = 'recibido' and v_item.recibido_por_balanza and not plantas_flota_item_completo(v_nuevo) then
    v_reabre := true;
  elsif v_item.pedido_por = 'camion' and v_item.estado_item = 'recibido' then
    v_cam := greatest(v_cam, 1);
  end if;
  -- Sin vínculos y en 0: vuelve a vacío, como antes de la primera pesada.
  if v_quedan = 0 and v_cant = 0 then v_cant := null; end if;
  if v_quedan = 0 and v_cam = 0 then v_cam := null; end if;

  update flota_pedido_items
     set camiones_recibidos = v_cam, cantidad_real = v_cant,
         estado_item = case when v_reabre then 'pendiente' else estado_item end,
         recibido_por_balanza = case when v_reabre then false else recibido_por_balanza end
   where id = v_item.id;

  if v_reabre then
    select * into v_ped from flota_pedidos where id = v_item.pedido_id for update;
    if v_ped.estado = 'cerrado' and v_ped.cerrado_por_balanza then
      update flota_pedidos
         set estado = case when exists (select 1 from flota_pedido_items where pedido_id = v_ped.id and estado_item <> 'pendiente')
                           then 'parcialmente_abierto' else 'en_compras' end,
             fecha_cierre = null, cerrado_por_balanza = false
       where id = v_ped.id;
      perform flota_aviso_compras_crear('pedido_reabierto', v_ped.id, null,
        'Pedido ' || v_ped.numero || ' reabierto',
        jsonb_build_object('pedido', v_ped.numero, 'vale', 'I-' || v_vale_n, 'motivo', coalesce(p_motivo, case when p_por_anulacion then 'Pesada anulada' end)),
        '<p>El pedido de Plantas <b>' || v_ped.numero || '</b> lo había cerrado la balanza y se volvió a abrir: '
          || case when p_por_anulacion then 'se anuló' else 'se desvinculó' end || ' la pesada I-' || v_vale_n
          || coalesce(' (' || p_motivo || ')', '') || '.</p>');
    elsif v_ped.estado = 'parcialmente_abierto'
          and not exists (select 1 from flota_pedido_items where pedido_id = v_ped.id and estado_item <> 'pendiente') then
      update flota_pedidos set estado = 'en_compras' where id = v_ped.id;
    end if;
  end if;

  perform plantas_auditar('ELIMINAR', 'bascula', 'vinculo_flota', p_ingreso_id::text,
    'Vale I-' || v_vale_n || ' → ' || v_numero,
    coalesce(p_motivo, case when p_por_anulacion then 'Pesada anulada' end),
    jsonb_build_object('pedido', v_numero, 'sumado', v_link.cantidad_sumada,
                       'camiones_recibidos', v_item.camiones_recibidos, 'cantidad_real', v_item.cantidad_real),
    jsonb_build_object('camiones_recibidos', v_cam, 'cantidad_real', v_cant, 'por_anulacion', p_por_anulacion, 'reabierto', v_reabre));
end;
$f$;

create or replace function public.desvincular_pesada_pedido_flota(p_ingreso_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path to 'public'
as $f$
declare
  v_estado text;
  v_numero text;
  v_balanza boolean;
begin
  if not plantas_puede_vincular_flota() then
    raise exception 'No tenés permiso para desvincular pesadas de pedidos de Flota.';
  end if;
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'El motivo es obligatorio para desvincular una pesada.';
  end if;
  select p.estado, p.numero, p.cerrado_por_balanza into v_estado, v_numero, v_balanza
    from flota_pedido_item_ingresos_planta l
    join flota_pedido_items i on i.id = l.item_id
    join flota_pedidos p on p.id = i.pedido_id
   where l.ingreso_id = p_ingreso_id;
  if not found then raise exception 'La pesada no está vinculada a ningún pedido.'; end if;
  -- 80: también si lo cerró la balanza (se reabre solo, D4).
  if v_estado not in ('en_compras', 'parcialmente_abierto') and not (v_estado = 'cerrado' and v_balanza) then
    raise exception 'El pedido % está % — ya no se puede desvincular.', v_numero, v_estado;
  end if;
  perform plantas_restar_pesada_de_item(p_ingreso_id, btrim(p_motivo), false);
end;
$f$;

create or replace function public.plantas_trg_ingreso_anulado_flota()
returns trigger language plpgsql security definer set search_path to 'public'
as $f$
begin
  if new.anulado and not coalesce(old.anulado, false) then
    perform plantas_restar_pesada_de_item(new.id, null, true);
    perform flota_aviso_compras_resolver_auto('pesada_sin_pedido', null, new.id, 'Pesada anulada', 'descartado');
  end if;
  return new;
end;
$f$;

-- ---------------------------------------------------------------------------
-- Flota: detalle por camión de un pedido (Ver detalle).
-- ---------------------------------------------------------------------------
create function public.pesadas_de_pedido_flota(p_pedido_id uuid)
returns table (
  item_id uuid, ingreso_id uuid, fecha timestamptz, numero_vale text, proveedor text, numero_remito text,
  patente text, cantidad numeric, unidad text, vinculada_por text, vinculada_at timestamptz
)
language plpgsql stable security definer set search_path to 'public'
as $f$
begin
  if not plantas_puede_vincular_flota() then
    raise exception 'No tenés permiso para ver las pesadas de balanza.';
  end if;
  return query
  select l.item_id, g.id, g.fecha_ingreso, 'I-' || v.numero_vale_arido, g.proveedor, g.numero_remito, v.patente,
         l.cantidad_sumada, upper(i.unidad), l.creado_por, l.creado_at
    from flota_pedido_item_ingresos_planta l
    join flota_pedido_items i on i.id = l.item_id
    join plantas_ingresos g on g.id = l.ingreso_id
    join plantas_vales v on v.id = g.vale_id
   where i.pedido_id = p_pedido_id
   order by g.fecha_ingreso;
end;
$f$;

-- ---------------------------------------------------------------------------
-- Aviso a Compras: pesada de un material de pedidos de Plantas que quedó sin pedido.
-- Diferido: corre al confirmar, cuando la balanza ya vinculó (si eligió pedido). Nunca frena la pesada.
-- ---------------------------------------------------------------------------
create function public.plantas_trg_ingreso_sin_pedido_flota()
returns trigger language plpgsql security definer set search_path to 'public'
as $f$
declare
  v_vale plantas_vales;
  v_mat  text;
begin
  if new.vale_id is null or coalesce(new.anulado, false) then return null; end if;
  select nombre into v_mat from plantas_materiales
   where id = plantas_buscar_material_id(new.material)
     and nombre in ('ASFALTO CA30', 'CEMENTO', 'FILLER', 'ASFALTO AM3', 'AM3 AUTOVIA', 'ADITIVO');
  if v_mat is null then return null; end if;
  if exists (select 1 from flota_pedido_item_ingresos_planta where ingreso_id = new.id) then return null; end if;
  select * into v_vale from plantas_vales where id = new.vale_id;
  begin
    perform flota_aviso_compras_crear('pesada_sin_pedido', null, new.id,
      'Pesada sin pedido: ' || v_mat || ' (vale I-' || v_vale.numero_vale_arido || ')',
      jsonb_build_object('material', v_mat, 'vale', 'I-' || v_vale.numero_vale_arido, 'proveedor', new.proveedor,
                         'remito', new.numero_remito, 'neto', v_vale.peso_neto, 'unidad', coalesce(v_vale.unidad, 'tn'),
                         'patente', v_vale.patente, 'fecha', new.fecha_ingreso),
      '<p>Entró por balanza <b>' || v_mat || '</b> sin pedido de Flota: vale I-' || v_vale.numero_vale_arido
        || coalesce(', ' || new.proveedor, '') || coalesce(', remito ' || new.numero_remito, '')
        || ', ' || v_vale.peso_neto || ' ' || coalesce(v_vale.unidad, 'tn') || '.</p><p>Vinculalo al pedido que corresponde desde Avisos.</p>');
  exception when others then
    raise warning 'Aviso de pesada sin pedido (%) no anotado: %', new.id, sqlerrm;
  end;
  return null;
end;
$f$;

create constraint trigger plantas_ingresos_sin_pedido_flota
  after insert on public.plantas_ingresos
  deferrable initially deferred
  for each row execute function public.plantas_trg_ingreso_sin_pedido_flota();

revoke execute on function public.plantas_flota_item_completo(public.flota_pedido_items) from public, anon;
grant  execute on function public.plantas_flota_item_completo(public.flota_pedido_items) to authenticated;
revoke execute on function public.pesadas_de_pedido_flota(uuid) from public, anon;
grant  execute on function public.pesadas_de_pedido_flota(uuid) to authenticated;
revoke execute on function public.plantas_trg_ingreso_sin_pedido_flota() from public, anon, authenticated;
