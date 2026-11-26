-- ============================================================================
-- Migración 81 — Los pedidos Plantas de Flota los cierra la balanza
-- (Federico, 26/11/2026). Alineada con la spec de Flota
-- vialtec-flota-v2/src/modules/pedidos/plantas-balanza.spec.md (D1–D6).
--
--   Al vincular una pesada (balanza o "vincular después" de Flota), si el ítem
--   queda completo pasa a `recibido` con proveedor y remito(s) de sus pesadas
--   (y `proveedor_id` si hay un único proveedor igual en core_proveedores).
--   Pedido: como `recomputarEstadoPedido` de Flota para Plantas — todos los
--   ítems resueltos (recibido/descartado) → `cerrado` + fecha_cierre; alguno →
--   `parcialmente_abierto`. Al cerrar se marca la transacción
--   `vialtec.cierre_balanza = on` (Flota la lee en fn_pedidos_avisos para el
--   mail a facturas — esa parte es de la migración de Flota).
--
--   Completo (D2): por camión, camiones recibidos >= pedidos; por cantidad en
--   TN, recibido >= 95 % de lo pedido; por cantidad en KG, >= 100 %.
--   (D6, ya en la 80: un camión de más, con el ítem completo, queda sin pedido.)
--
--   Reapertura (D4): al desvincular o anular una pesada de un ítem que cerró la
--   balanza, si deja de estar completo vuelve a `pendiente` y el pedido se
--   recalcula (cerrado → parcialmente_abierto o en_compras, sin fecha_cierre).
--   Queda en plantas_cierres_flota (reabierto_at) y la transacción se marca
--   `vialtec.reapertura_balanza = on`: el aviso a Alejandro lo arma Flota.
--   Lo que Alejandro recibió a mano (D1, respaldo) no se reabre solo.
--   Desvincular ahora acepta un pedido `cerrado` si lo cerró la balanza.
--
--   Nuevo:      plantas_cierres_flota (tabla, quién/cuándo cerró y reabrió)
--               plantas_vinculo_flota_autorizados + plantas_puede_vincular_despues()
--               trigger diferido plantas_ingresos_sin_pedido_flota (aviso D6)
--               plantas_cerrar_item_flota_si_completo(item)  (interna)
--               pesadas_de_pedido_flota(p_pedido_id)          (Flota: detalle por camión)
--   Reemplaza:  plantas_item_flota_completo (95 % en TN)
--               vincular_pesada_pedido_flota (solo autorizados; vincula con plantas_vincular_pesada_interna, que cierra)
--               registrar_ingreso_pedido_flota (la balanza vincula con la interna)
--               plantas_restar_pesada_de_item (reabre)
--               desvincular_pesada_pedido_flota (acepta cerrado por balanza)
--   Puesta al día: los ítems pendientes que YA están completos por pesadas
--   vinculadas se cierran al aplicar, SIN mandar mails (el trigger de avisos
--   se apaga solo durante ese paso). Correr después de la limpieza de Flota.
--
--   Permisos (Federico, 26/11): al pesar, la balanza sigue eligiendo el pedido
--   (registrar_ingreso_pedido_flota). Vincular o desvincular DESPUÉS (Pesadas
--   sin pedido / Avisos) solo: admin de Plantas, Flota Admin o gerente_compras
--   (Alejandro), y los mails de plantas_vinculo_flota_autorizados (Félix).
--   Balanceros y demás plantistas no.
--
--   Aviso "pesada sin pedido" (D6, con Flota): al confirmar una pesada de
--   ingreso de un material que se pide por Flota (se_pide_por_flota, TN/KG) que
--   no quedó vinculada, se crea el aviso a Compras (flota_aviso_compras_crear,
--   tipo 'pesada_sin_pedido'). Trigger diferido: corre al final de la
--   transacción, cuando la balanza ya vinculó (o no). Al anular la pesada, el
--   aviso se descarta solo. Si los avisos de Flota fallan, la pesada se guarda
--   igual (solo queda un warning).
--
--   REQUIERE ANTES: limpieza de pedidos y pedidos_plantas_balanza.sql (Flota 1).
--   DESPUÉS: pedidos_plantas_balanza_post81.sql (Flota 2).
--
-- No toca registrar_pesada_bascula / anular / corregir, ni fn_pedidos_avisos.
-- Ensayo:       supabase/scripts/dry_run_migracion_81.sql
-- Vuelta atrás: supabase/scripts/revertir_migracion_81.sql
-- ============================================================================

do $pre$
begin
  if to_regprocedure('public.flota_aviso_compras_crear(text, uuid, uuid, text, jsonb, text)') is null
     or to_regprocedure('public.flota_aviso_compras_resolver_auto(text, uuid, uuid, text, text)') is null then
    raise exception 'Falta la migración de Flota pedidos_plantas_balanza.sql: aplicarla antes que la 81.';
  end if;
end $pre$;

insert into plantas_auditoria_entidades (modulo, entidad, modulo_etiqueta, entidad_etiqueta, orden)
values ('bascula', 'cierre_flota', 'Báscula', 'Cierre de pedido de Flota', 25);

create table public.plantas_cierres_flota (
  id            bigint generated always as identity primary key,
  item_id       uuid not null references flota_pedido_items(id) on delete cascade,
  pedido_id     uuid not null references flota_pedidos(id) on delete cascade,
  cerro_pedido  boolean not null default false,
  cerrado_at    timestamptz not null default now(),
  cerrado_por   text,
  reabierto_at  timestamptz,
  reabierto_por text,
  motivo_reapertura text
);
create unique index plantas_cierres_flota_activo on public.plantas_cierres_flota (item_id) where reabierto_at is null;
create index plantas_cierres_flota_pedido on public.plantas_cierres_flota (pedido_id);
alter table public.plantas_cierres_flota enable row level security;
create policy plantas_cierres_flota_leer on public.plantas_cierres_flota
  for select to authenticated using (plantas_puede_vincular_flota());
revoke all on public.plantas_cierres_flota from anon;
revoke insert, update, delete on public.plantas_cierres_flota from authenticated;

-- Quién vincula/desvincula DESPUÉS de pesar (además de los roles de abajo).
create table public.plantas_vinculo_flota_autorizados (
  email     text primary key check (email = lower(btrim(email))),
  nota      text,
  creado_at timestamptz not null default now()
);
alter table public.plantas_vinculo_flota_autorizados enable row level security;
revoke all on public.plantas_vinculo_flota_autorizados from anon, authenticated;
insert into public.plantas_vinculo_flota_autorizados (email, nota)
values ('felix.pereyra@vialtec.com.ar', 'Félix — Federico 26/11');

create or replace function public.plantas_puede_vincular_despues()
returns boolean language sql stable security definer set search_path to 'public'
as $f$
  select coalesce(plantas_rol_actual(), '') = 'admin'
      or exists (select 1 from flota_usuarios_email u
                  where lower(u.email) = lower(auth.email()) and u.activo and u.rol in ('Admin', 'gerente_compras'))
      or exists (select 1 from plantas_vinculo_flota_autorizados a where a.email = lower(auth.email()))
$f$;

-- D2: 95 % en TN.
create or replace function public.plantas_item_flota_completo(i flota_pedido_items)
returns boolean language sql immutable set search_path to 'public'
as $f$
  select case
    when i.pedido_por = 'camion'   then i.camiones is not null and coalesce(i.camiones_recibidos, 0) >= i.camiones
    when i.pedido_por = 'cantidad' and upper(coalesce(i.unidad, '')) = 'TN'
                                   then i.cantidad is not null and coalesce(i.cantidad_real, 0) >= round(i.cantidad * 0.95, 3)
    when i.pedido_por = 'cantidad' then i.cantidad is not null and coalesce(i.cantidad_real, 0) >= i.cantidad
    else false
  end
$f$;

-- Estado del pedido Plantas según sus ítems (mismo criterio que la pantalla de Flota).
create or replace function public.plantas_recalcular_pedido_flota(p_pedido_id uuid)
returns text language plpgsql security definer set search_path to 'public'
as $f$
declare
  v_pedido  flota_pedidos;
  v_total   int;
  v_resuel  int;
  v_nuevo   text;
  v_hoy     date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  select * into v_pedido from flota_pedidos where id = p_pedido_id for update;
  if v_pedido.modulo is distinct from 'plantas' or v_pedido.estado not in ('en_compras', 'parcialmente_abierto', 'cerrado') then
    return v_pedido.estado;
  end if;
  select count(*), count(*) filter (where estado_item in ('recibido', 'descartado'))
    into v_total, v_resuel from flota_pedido_items where pedido_id = p_pedido_id;
  v_nuevo := case when v_total > 0 and v_resuel = v_total then 'cerrado'
                  when v_resuel > 0 then 'parcialmente_abierto'
                  else 'en_compras' end;
  if v_nuevo is distinct from v_pedido.estado then
    if v_nuevo = 'cerrado' then
      perform set_config('vialtec.cierre_balanza', 'on', true);
      update flota_pedidos set estado = 'cerrado', fecha_cierre = v_hoy, fecha_recepcion = coalesce(fecha_recepcion, v_hoy)
       where id = p_pedido_id;
    else
      if v_pedido.estado = 'cerrado' then perform set_config('vialtec.reapertura_balanza', 'on', true); end if;
      update flota_pedidos set estado = v_nuevo, fecha_cierre = null where id = p_pedido_id;
    end if;
  end if;
  return v_nuevo;
end;
$f$;

-- Cierra el ítem si está completo (interna: la usan vincular y la puesta al día).
create or replace function public.plantas_cerrar_item_flota_si_completo(p_item_id uuid)
returns boolean language plpgsql security definer set search_path to 'public'
as $f$
declare
  v_item     flota_pedido_items;
  v_numero   text;
  v_provs    text;
  v_nprov    int;
  v_remitos  text;
  v_prov_id  uuid;
  v_estado   text;
begin
  select * into v_item from flota_pedido_items where id = p_item_id for update;
  if not found or v_item.estado_item is distinct from 'pendiente' or not plantas_item_flota_completo(v_item) then
    return false;
  end if;
  select numero into v_numero from flota_pedidos where id = v_item.pedido_id;

  select string_agg(distinct nullif(btrim(g.proveedor), ''), ' / '), count(distinct lower(nullif(btrim(g.proveedor), ''))),
         string_agg(distinct nullif(btrim(g.numero_remito), ''), ' / ')
    into v_provs, v_nprov, v_remitos
    from flota_pedido_item_ingresos_planta l join plantas_ingresos g on g.id = l.ingreso_id
   where l.item_id = v_item.id;
  if v_nprov = 1 then
    select min(c.id::text)::uuid into v_prov_id from core_proveedores c
     where c.activo and c.unido_a is null and lower(btrim(c.nombre)) = lower(v_provs)
    having count(*) = 1;
  end if;

  update flota_pedido_items
     set estado_item = 'recibido',
         proveedor   = coalesce(v_provs, proveedor),
         proveedor_id = coalesce(v_prov_id, proveedor_id),
         nro_remito  = coalesce(v_remitos, nro_remito)
   where id = v_item.id;

  v_estado := plantas_recalcular_pedido_flota(v_item.pedido_id);
  insert into plantas_cierres_flota (item_id, pedido_id, cerro_pedido, cerrado_por)
  values (v_item.id, v_item.pedido_id, v_estado = 'cerrado', coalesce(nullif(auth.email(), ''), 'sistema (SQL)'));

  perform plantas_auditar('CAMBIAR_ESTADO', 'bascula', 'cierre_flota', v_item.id::text,
    v_numero || ' — ítem recibido por la balanza' || case when v_estado = 'cerrado' then ' (pedido cerrado)' else '' end, null,
    jsonb_build_object('estado_item', 'pendiente'),
    jsonb_build_object('estado_item', 'recibido', 'pedido', v_numero, 'estado_pedido', v_estado, 'proveedor', v_provs,
                       'remitos', v_remitos, 'camiones_recibidos', v_item.camiones_recibidos, 'cantidad_real', v_item.cantidad_real));
  return true;
end;
$f$;

-- ---------------------------------------------------------------------------
-- Vincular (interna, sin control de quién): igual que la 79 + cierre al
-- completar. La usan la balanza al pesar y vincular_pesada_pedido_flota.
-- ---------------------------------------------------------------------------
create or replace function public.plantas_vincular_pesada_interna(p_ingreso_id uuid, p_flota_item_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $f$
declare
  v_ing    plantas_ingresos;
  v_vale   plantas_vales;
  v_item   flota_pedido_items;
  v_pedido flota_pedidos;
  v_mat    text;
  v_neto   numeric;
  v_cerro  boolean;
begin
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

  v_cerro := plantas_cerrar_item_flota_si_completo(v_item.id);

  return jsonb_build_object('item_id', v_item.id, 'pedido', v_pedido.numero, 'sumado', v_neto,
                            'camiones_recibidos', v_item.camiones_recibidos, 'cantidad_real', v_item.cantidad_real,
                            'item_recibido', v_cerro,
                            'pedido_cerrado', (select estado = 'cerrado' from flota_pedidos where id = v_item.pedido_id));
end;
$f$;

-- Vincular DESPUÉS (Pesadas sin pedido / Avisos): solo los autorizados.
create or replace function public.vincular_pesada_pedido_flota(p_ingreso_id uuid, p_flota_item_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $f$
begin
  if not plantas_puede_vincular_despues() then
    raise exception 'Vincular una pesada después de pesar lo hacen admin, Félix o Compras.';
  end if;
  return plantas_vincular_pesada_interna(p_ingreso_id, p_flota_item_id);
end;
$f$;

-- Balanza al pesar: igual que la 80, pero vincula con la interna (el balancero
-- elige el pedido en la puerta, como hoy).
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
    perform plantas_vincular_pesada_interna(v_ingreso_id, v_item.id);
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

-- ---------------------------------------------------------------------------
-- Restar (desvincular / anular): igual que la 79 + reapertura (D4).
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
  v_cierre  plantas_cierres_flota;
  v_reabre  boolean := false;
  v_estado  text;
  v_prueba  flota_pedido_items;
begin
  select * into v_link from flota_pedido_item_ingresos_planta where ingreso_id = p_ingreso_id;
  if not found then return; end if;
  select * into v_item from flota_pedido_items where id = v_link.item_id for update;
  select numero into v_numero from flota_pedidos where id = v_item.pedido_id;
  select v.numero_vale_arido into v_vale_n from plantas_ingresos g join plantas_vales v on v.id = g.vale_id where g.id = p_ingreso_id;
  select * into v_cierre from plantas_cierres_flota where item_id = v_item.id and reabierto_at is null;

  delete from flota_pedido_item_ingresos_planta where ingreso_id = p_ingreso_id;
  select count(*) into v_quedan from flota_pedido_item_ingresos_planta where item_id = v_item.id;

  v_cam  := greatest(coalesce(v_item.camiones_recibidos, 0) - 1, 0);
  v_cant := greatest(coalesce(v_item.cantidad_real, 0) - coalesce(v_link.cantidad_sumada, 0), 0);

  -- D4: lo cerró la balanza y deja de estar completo → vuelve a pendiente.
  if v_cierre.id is not null and v_item.estado_item = 'recibido' then
    v_prueba := v_item; v_prueba.camiones_recibidos := v_cam; v_prueba.cantidad_real := v_cant;
    v_reabre := not plantas_item_flota_completo(v_prueba);
  end if;

  -- Un ítem por camión que sigue recibido no puede quedar con 0 camiones (regla de Flota).
  if v_item.pedido_por = 'camion' and v_item.estado_item = 'recibido' and not v_reabre then v_cam := greatest(v_cam, 1); end if;
  -- Sin vínculos y en 0: vuelve a vacío, como antes de la primera pesada.
  if v_quedan = 0 and v_cant = 0 then v_cant := null; end if;
  if v_quedan = 0 and v_cam = 0 then v_cam := null; end if;

  update flota_pedido_items
     set camiones_recibidos = v_cam, cantidad_real = v_cant,
         estado_item = case when v_reabre then 'pendiente' else estado_item end
   where id = v_item.id;

  perform plantas_auditar('ELIMINAR', 'bascula', 'vinculo_flota', p_ingreso_id::text,
    'Vale I-' || v_vale_n || ' → ' || v_numero,
    coalesce(p_motivo, case when p_por_anulacion then 'Pesada anulada' end),
    jsonb_build_object('pedido', v_numero, 'sumado', v_link.cantidad_sumada,
                       'camiones_recibidos', v_item.camiones_recibidos, 'cantidad_real', v_item.cantidad_real),
    jsonb_build_object('camiones_recibidos', v_cam, 'cantidad_real', v_cant, 'por_anulacion', p_por_anulacion));

  if v_reabre then
    v_estado := plantas_recalcular_pedido_flota(v_item.pedido_id);
    update plantas_cierres_flota
       set reabierto_at = now(), reabierto_por = coalesce(nullif(auth.email(), ''), 'sistema (SQL)'),
           motivo_reapertura = coalesce(p_motivo, case when p_por_anulacion then 'Pesada anulada' end) || ' (vale I-' || v_vale_n || ')'
     where id = v_cierre.id;
    perform plantas_auditar('CAMBIAR_ESTADO', 'bascula', 'cierre_flota', v_item.id::text,
      v_numero || ' — ítem reabierto (se sacó el vale I-' || v_vale_n || ')',
      coalesce(p_motivo, case when p_por_anulacion then 'Pesada anulada' end),
      jsonb_build_object('estado_item', 'recibido'),
      jsonb_build_object('estado_item', 'pendiente', 'pedido', v_numero, 'estado_pedido', v_estado));
  end if;
end;
$f$;

-- ---------------------------------------------------------------------------
-- Desvincular: también con el pedido cerrado, si lo cerró la balanza (D4).
-- ---------------------------------------------------------------------------
create or replace function public.desvincular_pesada_pedido_flota(p_ingreso_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path to 'public'
as $f$
declare
  v_estado  text;
  v_numero  text;
  v_item_id uuid;
begin
  if not plantas_puede_vincular_despues() then
    raise exception 'Desvincular una pesada lo hacen admin, Félix o Compras.';
  end if;
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'El motivo es obligatorio para desvincular una pesada.';
  end if;
  select p.estado, p.numero, i.id into v_estado, v_numero, v_item_id
    from flota_pedido_item_ingresos_planta l
    join flota_pedido_items i on i.id = l.item_id
    join flota_pedidos p on p.id = i.pedido_id
   where l.ingreso_id = p_ingreso_id;
  if not found then raise exception 'La pesada no está vinculada a ningún pedido.'; end if;
  if v_estado not in ('en_compras', 'parcialmente_abierto')
     and not (v_estado = 'cerrado' and exists (select 1 from plantas_cierres_flota c where c.item_id = v_item_id and c.reabierto_at is null)) then
    raise exception 'El pedido % está % — ya no se puede desvincular.', v_numero, v_estado;
  end if;
  perform plantas_restar_pesada_de_item(p_ingreso_id, btrim(p_motivo), false);
end;
$f$;

-- ---------------------------------------------------------------------------
-- Flota: detalle por camión de un pedido Plantas (Compras no lee plantas_*).
-- ---------------------------------------------------------------------------
create or replace function public.pesadas_de_pedido_flota(p_pedido_id uuid)
returns table (
  item_id uuid, material text, ingreso_id uuid, fecha timestamptz, numero_vale text, proveedor text,
  numero_remito text, patente text, neto_tn numeric, cantidad_sumada numeric, unidad text
)
language plpgsql stable security definer set search_path to 'public'
as $f$
begin
  if not plantas_puede_vincular_flota() then
    raise exception 'No tenés permiso para ver las pesadas de balanza.';
  end if;
  return query
  select i.id, m.nombre, g.id, coalesce(v.fecha_pesada, g.fecha_ingreso), 'I-' || v.numero_vale_arido, g.proveedor,
         g.numero_remito, v.patente,
         round(case when coalesce(v.unidad, 'tn') = 'kg' then v.peso_neto / 1000 else v.peso_neto end, 3),
         l.cantidad_sumada, upper(i.unidad)
    from flota_pedido_items i
    join flota_pedido_item_ingresos_planta l on l.item_id = i.id
    join plantas_ingresos g on g.id = l.ingreso_id
    join plantas_vales v on v.id = g.vale_id
    left join plantas_materiales m on m.id = i.material_planta_id
   where i.pedido_id = p_pedido_id
   order by m.nombre, coalesce(v.fecha_pesada, g.fecha_ingreso);
end;
$f$;

-- ---------------------------------------------------------------------------
-- D6: aviso a Compras por pesada de ingreso sin pedido (trigger diferido).
-- ---------------------------------------------------------------------------
create or replace function public.plantas_trg_ingreso_sin_pedido_flota()
returns trigger language plpgsql security definer set search_path to 'public'
as $f$
declare
  v_ing  plantas_ingresos;
  v_vale plantas_vales;
  v_mat  plantas_materiales;
  v_neto numeric;
begin
  select * into v_ing from plantas_ingresos where id = new.id;
  if not found or v_ing.vale_id is null or coalesce(v_ing.anulado, false) then return null; end if;
  if exists (select 1 from flota_pedido_item_ingresos_planta where ingreso_id = v_ing.id) then return null; end if;
  select * into v_mat from plantas_materiales where id = plantas_buscar_material_id(v_ing.material);
  if not coalesce(v_mat.se_pide_por_flota, false) or upper(coalesce(v_mat.unidad, '')) not in ('TN', 'KG') then return null; end if;
  select * into v_vale from plantas_vales where id = v_ing.vale_id;
  if coalesce(v_vale.anulado, false) then return null; end if;
  if to_regprocedure('public.flota_aviso_compras_crear(text, uuid, uuid, text, jsonb, text)') is null then return null; end if;
  v_neto := round(case when coalesce(v_vale.unidad, 'tn') = 'kg' then v_vale.peso_neto / 1000 else v_vale.peso_neto end, 3);
  begin
    perform flota_aviso_compras_crear('pesada_sin_pedido', null, v_ing.id,
      'Pesada sin pedido: ' || v_mat.nombre || ' (vale I-' || v_vale.numero_vale_arido || ')',
      jsonb_build_object('material', v_mat.nombre, 'vale', 'I-' || v_vale.numero_vale_arido, 'proveedor', v_ing.proveedor,
                         'remito', v_ing.numero_remito, 'patente', v_vale.patente, 'neto', v_neto, 'unidad', 'TN',
                         'fecha', coalesce(v_vale.fecha_pesada, v_ing.fecha_ingreso)),
      format('<p>Entró a la planta una pesada de <b>%s</b> sin pedido de Flota: vale I-%s, %s TN, proveedor %s, remito %s, patente %s.</p>',
             v_mat.nombre, v_vale.numero_vale_arido, replace(v_neto::text, '.', ','),
             coalesce(nullif(v_ing.proveedor, ''), '—'), coalesce(nullif(v_ing.numero_remito, ''), '—'), coalesce(nullif(v_vale.patente, ''), '—')));
  exception when others then
    raise warning 'Pesada I-% sin aviso a Compras: %', v_vale.numero_vale_arido, sqlerrm;
  end;
  return null;
end;
$f$;

create constraint trigger plantas_ingresos_sin_pedido_flota
  after insert on public.plantas_ingresos
  deferrable initially deferred
  for each row execute function public.plantas_trg_ingreso_sin_pedido_flota();

-- Anular la pesada: resta del ítem (79) y descarta su aviso de "sin pedido".
create or replace function public.plantas_trg_ingreso_anulado_flota()
returns trigger language plpgsql security definer set search_path to 'public'
as $f$
begin
  if new.anulado and not coalesce(old.anulado, false) then
    perform plantas_restar_pesada_de_item(new.id, null, true);
    if to_regprocedure('public.flota_aviso_compras_resolver_auto(text, uuid, uuid, text, text)') is not null then
      begin
        perform flota_aviso_compras_resolver_auto('pesada_sin_pedido', null, new.id, 'Pesada anulada', 'descartado');
      exception when others then
        raise warning 'Aviso de la pesada % sin descartar: %', new.id, sqlerrm;
      end;
    end if;
  end if;
  return new;
end;
$f$;

revoke execute on function public.plantas_trg_ingreso_sin_pedido_flota() from public, anon, authenticated;
revoke execute on function public.plantas_recalcular_pedido_flota(uuid) from public, anon, authenticated;
revoke execute on function public.plantas_cerrar_item_flota_si_completo(uuid) from public, anon, authenticated;
revoke execute on function public.plantas_vincular_pesada_interna(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.plantas_puede_vincular_despues() from public, anon;
grant  execute on function public.plantas_puede_vincular_despues() to authenticated;
revoke execute on function public.pesadas_de_pedido_flota(uuid) from public, anon;
grant  execute on function public.pesadas_de_pedido_flota(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Puesta al día: ítems pendientes ya completos por pesadas vinculadas.
-- SIN mails (Federico, 26/11): el trigger de avisos de pedidos se apaga solo
-- dentro de esta transacción (la tabla queda bloqueada mientras tanto, así que
-- nadie más pierde avisos) y se vuelve a prender antes de terminar.
-- ---------------------------------------------------------------------------
alter table public.flota_pedidos disable trigger trg_pedidos_avisos;
select plantas_cerrar_item_flota_si_completo(i.id)
  from flota_pedido_items i join flota_pedidos p on p.id = i.pedido_id
 where p.modulo = 'plantas' and p.estado in ('en_compras', 'parcialmente_abierto') and i.estado_item = 'pendiente'
   and exists (select 1 from flota_pedido_item_ingresos_planta l where l.item_id = i.id)
   and plantas_item_flota_completo(i);
alter table public.flota_pedidos enable trigger trg_pedidos_avisos;
