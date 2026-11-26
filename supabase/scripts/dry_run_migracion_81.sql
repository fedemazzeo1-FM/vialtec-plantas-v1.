-- ============================================================================
-- Ensayo de la migración 81 (cierre automático de pedidos Plantas por la balanza).
-- Una sola ejecución: [ANTES] (abajo, comentado), la 81, y este DO.
-- Termina SIEMPRE con ERROR "DRYRUN 81 OK — …" (todo revertido, numeración de
-- vales de áridos devuelta). Usa los pedidos reales abiertos (PED-0514, 0528,
-- 0531, 0536 al 26/11) e incluye la vuelta atrás (revertir_migracion_81.sql).
-- [ANTES]:
--   create temp table _md5_80 on commit drop as select proname, md5(pg_get_functiondef(oid)) h from pg_proc
--    where proname in ('vincular_pesada_pedido_flota','plantas_restar_pesada_de_item','desvincular_pesada_pedido_flota','plantas_item_flota_completo','registrar_ingreso_pedido_flota','plantas_trg_ingreso_anulado_flota');
--   Si la migración de Flota (pedidos_plantas_balanza.sql) todavía no está aplicada, antes de la 81 crear
--   dobles de sus dos funciones de avisos que anotan las llamadas (se deshacen con el ensayo):
--   create temp table _avisos (accion text, tipo text, ingreso_id uuid, titulo text) on commit drop;
--   create function public.flota_aviso_compras_crear(p_tipo text, p_pedido_id uuid, p_ingreso_id uuid, p_titulo text, p_detalle jsonb, p_html text)
--   returns bigint language sql as $s$ insert into pg_temp._avisos values ('crear', p_tipo, p_ingreso_id, p_titulo) returning 1::bigint $s$;
--   create function public.flota_aviso_compras_resolver_auto(p_tipo text, p_pedido_id uuid, p_ingreso_id uuid, p_nota text, p_estado text default 'resuelto')
--   returns integer language sql as $s$ insert into pg_temp._avisos values (p_estado, p_tipo, p_ingreso_id, p_nota) returning 1 $s$;
--   (con la de Flota aplicada, los avisos van a flota_avisos_compras: cambiar pg_temp._avisos por esa tabla en K)
-- ============================================================================
do $dry$
declare
  v_ok text[] := '{}'; v_seq_antes bigint; v_seq_llam boolean;
  v_531 flota_pedido_items; v_536 flota_pedido_items; v_528 flota_pedido_items; v_514 flota_pedido_items; v_it flota_pedido_items;
  v_p flota_pedidos; v_c plantas_cierres_flota; v_r jsonb; v_n int; v_ing uuid; v_ing2 uuid; v_link_528 uuid;
  v_otros text; v_otros_d text; v_md5 text; v_md5_d text; v_items_536 int; v_ing_b uuid; v_ing_k uuid;
  c_balanza   constant text := '{"email":"balanza@vialtec.com.ar","role":"authenticated"}';
  c_alejandro constant text := '{"email":"alejandro.fernandez@vialtec.com.ar","role":"authenticated"}';
  c_nadie     constant text := '{"email":"nadie.ensayo81@example.com","role":"authenticated"}';
begin
  select last_value, is_called into v_seq_antes, v_seq_llam from plantas_vales_numero_arido_seq;
  select i.* into v_531 from flota_pedido_items i join flota_pedidos p on p.id = i.pedido_id where p.numero = 'PED-0531';
  select i.* into v_536 from flota_pedido_items i join flota_pedidos p on p.id = i.pedido_id where p.numero = 'PED-0536';
  select i.* into v_528 from flota_pedido_items i join flota_pedidos p on p.id = i.pedido_id where p.numero = 'PED-0528';
  select i.* into v_514 from flota_pedido_items i join flota_pedidos p on p.id = i.pedido_id where p.numero = 'PED-0514';
  if v_531.id is null or v_536.id is null or v_528.id is null or v_514.id is null then raise exception 'Precondición: faltan pedidos'; end if;
  select count(*) into v_items_536 from flota_pedido_items where pedido_id = v_536.pedido_id;
  v_otros := (select md5(string_agg(i::text, ',' order by i.id)) from flota_pedido_items i where i.pedido_id not in (v_531.pedido_id, v_536.pedido_id, v_528.pedido_id, v_514.pedido_id));
  v_md5 := (select string_agg(md5(pg_get_functiondef(oid)), ',' order by proname) from pg_proc
             where proname in ('registrar_pesada_bascula', 'anular_vale_bascula', 'corregir_vale_bascula', 'fn_pedidos_avisos',
                               'plantas_pedidos_flota_pendientes', 'pesadas_sin_pedido_flota'));

  -- A. Puesta al día: PED-0531 (1 de 1 con pesada) quedó recibido y el pedido cerrado.
  select * into v_it from flota_pedido_items where id = v_531.id;
  select * into v_p from flota_pedidos where id = v_531.pedido_id;
  select * into v_c from plantas_cierres_flota where item_id = v_531.id and reabierto_at is null;
  if v_it.estado_item <> 'recibido' or v_p.estado <> 'cerrado' or v_p.fecha_cierre is null or v_c.id is null or not v_c.cerro_pedido
     or v_it.nro_remito is null or v_it.proveedor is null then
    raise exception 'A: % / % / cierre % / prov % / remito %', v_it.estado_item, v_p.estado, v_c.id, v_it.proveedor, v_it.nro_remito; end if;
  if current_setting('vialtec.cierre_balanza', true) is distinct from 'on' then raise exception 'A: sin marca cierre_balanza'; end if;
  if exists (select 1 from flota_pedido_items i join flota_pedidos p on p.id = i.pedido_id where i.id in (v_536.id, v_528.id, v_514.id) and (i.estado_item <> 'pendiente' or p.estado = 'cerrado')) then
    raise exception 'A: la puesta al día tocó un pedido incompleto'; end if;
  if (select tgenabled from pg_trigger where tgname = 'trg_pedidos_avisos') <> 'O' then raise exception 'A: trigger de avisos quedó apagado'; end if;
  if exists (select 1 from core_notificaciones where created_at >= now()) then raise exception 'A: la puesta al día generó avisos'; end if;
  v_ok := v_ok || ('A puesta al día: PED-0531 recibido (' || v_it.proveedor || ', remito ' || v_it.nro_remito || ') y cerrado; los incompletos no')::text;

  -- B. PED-0536 (1 de 2): el 2º camión por balanza lo completa → recibido + pedido cerrado.
  perform set_config('request.jwt.claims', c_balanza, true);
  perform set_config('vialtec.cierre_balanza', '', true);
  v_r := registrar_ingreso_pedido_flota(v_536.id, 40, 13, 'ASFALTO CA30', 'PROVEEDOR ENSAYO 81', 'ENSAYO81-B', 27);
  if not (v_r->>'vinculado')::boolean then raise exception 'B1: %', v_r; end if;
  select id into v_ing from plantas_ingresos where vale_id = (v_r->>'vale_id')::uuid;
  v_ing_b := v_ing;
  select * into v_it from flota_pedido_items where id = v_536.id;
  select * into v_p from flota_pedidos where id = v_536.pedido_id;
  if v_it.estado_item <> 'recibido' or v_it.camiones_recibidos <> 2 or v_it.nro_remito not like '%ENSAYO81-B%' then raise exception 'B2: % % %', v_it.estado_item, v_it.camiones_recibidos, v_it.nro_remito; end if;
  if (v_items_536 = 1 and v_p.estado <> 'cerrado') or current_setting('vialtec.cierre_balanza', true) is distinct from 'on' and v_items_536 = 1 then raise exception 'B3: pedido %', v_p.estado; end if;
  if exists (select 1 from plantas_pedidos_flota_pendientes() where item_id = v_536.id) then raise exception 'B4: sigue en el desplegable'; end if;
  v_ok := v_ok || ('B 2º camión: ítem recibido, pedido ' || v_p.estado || ', marca cierre_balanza, fuera del desplegable')::text;

  -- C. D4: Alejandro desvincula esa pesada → ítem pendiente, pedido reabierto, cierre marcado reabierto.
  perform set_config('request.jwt.claims', c_alejandro, true);
  perform desvincular_pesada_pedido_flota(v_ing, 'Ensayo 81: pesada equivocada');
  select * into v_it from flota_pedido_items where id = v_536.id;
  select * into v_p from flota_pedidos where id = v_536.pedido_id;
  select * into v_c from plantas_cierres_flota where item_id = v_536.id order by id desc limit 1;
  if v_it.estado_item <> 'pendiente' or v_it.camiones_recibidos <> 1 or v_p.estado = 'cerrado' or v_p.fecha_cierre is not null
     or v_c.reabierto_at is null or v_c.motivo_reapertura not like '%Ensayo 81%' or current_setting('vialtec.reapertura_balanza', true) is distinct from 'on' then
    raise exception 'C: % % % % %', v_it.estado_item, v_it.camiones_recibidos, v_p.estado, v_c.reabierto_at, v_c.motivo_reapertura; end if;
  v_ok := v_ok || ('C desvincular: ítem pendiente (1 de 2), pedido ' || v_p.estado || ', reapertura registrada y marcada')::text;

  -- D. D4 por anulación: se vuelve a vincular (cierra) y se anula la pesada → reabre.
  perform set_config('request.jwt.claims', c_balanza, true);
  v_r := registrar_ingreso_pedido_flota(v_536.id, 40, 13, 'ASFALTO CA30', 'PROVEEDOR ENSAYO 81', 'ENSAYO81-D', 27);
  select id into v_ing2 from plantas_ingresos where vale_id = (v_r->>'vale_id')::uuid;
  if (select estado_item from flota_pedido_items where id = v_536.id) <> 'recibido' then raise exception 'D1'; end if;
  update plantas_ingresos set anulado = true where id = v_ing2;
  select * into v_it from flota_pedido_items where id = v_536.id;
  select count(*) into v_n from plantas_cierres_flota where item_id = v_536.id and reabierto_at is null;
  if v_it.estado_item <> 'pendiente' or v_it.camiones_recibidos <> 1 or v_n <> 0 or (select estado from flota_pedidos where id = v_536.pedido_id) = 'cerrado' then
    raise exception 'D2: % % %', v_it.estado_item, v_it.camiones_recibidos, v_n; end if;
  v_ok := v_ok || 'D anular: vuelve a cerrar al vincular y reabre al anular'::text;

  -- E. D1: lo recibido a mano por Alejandro NO se reabre solo (subtransacción, se deshace).
  begin
    select ingreso_id into v_link_528 from flota_pedido_item_ingresos_planta where item_id = v_528.id limit 1;
    update flota_pedido_items set estado_item = 'recibido' where id = v_528.id;
    update flota_pedidos set estado = 'cerrado', fecha_cierre = current_date where id = v_528.pedido_id;
    perform set_config('request.jwt.claims', c_alejandro, true);
    begin perform desvincular_pesada_pedido_flota(v_link_528, 'x'); raise exception 'E1';
    exception when others then if sqlerrm not like '%ya no se puede desvincular%' then raise; end if; end;
    update flota_pedidos set estado = 'parcialmente_abierto', fecha_cierre = null where id = v_528.pedido_id;
    perform desvincular_pesada_pedido_flota(v_link_528, 'Ensayo 81 manual');
    select * into v_it from flota_pedido_items where id = v_528.id;
    if v_it.estado_item <> 'recibido' or v_it.camiones_recibidos <> 1 then raise exception 'E2: % %', v_it.estado_item, v_it.camiones_recibidos; end if;
    raise exception 'E_OK';
  exception when others then if sqlerrm <> 'E_OK' then raise; end if; end;
  if (select estado_item from flota_pedido_items where id = v_528.id) <> 'pendiente' then raise exception 'E3: no se deshizo'; end if;
  v_ok := v_ok || 'E recibido a mano: no se desvincula con pedido cerrado a mano, y al desvincular sigue recibido'::text;

  -- F. D2: por cantidad en TN al 95 %; en KG al 100 %.
  v_it := v_528; v_it.pedido_por := 'cantidad'; v_it.camiones := null; v_it.cantidad := 60; v_it.cantidad_real := 56.99;
  if plantas_item_flota_completo(v_it) then raise exception 'F1'; end if;
  v_it.cantidad_real := 57; if not plantas_item_flota_completo(v_it) then raise exception 'F2'; end if;
  v_it.unidad := 'KG'; if plantas_item_flota_completo(v_it) then raise exception 'F3'; end if;
  v_it.cantidad_real := 60; if not plantas_item_flota_completo(v_it) then raise exception 'F4'; end if;
  perform set_config('request.jwt.claims', c_balanza, true);
  update flota_pedido_items set pedido_por = 'cantidad', camiones = null, cantidad = 60 where id = v_528.id;  -- ya tiene 33,74
  v_r := registrar_ingreso_pedido_flota(v_528.id, 36, 12.7, 'CEMENTO', 'PROVEEDOR ENSAYO 81', 'ENSAYO81-F', 23.3);  -- +23,3 = 57,04 (95 %)
  if not (v_r->>'vinculado')::boolean or (select estado_item from flota_pedido_items where id = v_528.id) <> 'recibido' then raise exception 'F5: %', v_r; end if;
  v_ok := v_ok || 'F 95 %: TN 56,99/60 no, 57/60 sí (cierra con 57,04); KG pide el 100 %'::text;

  -- G. Detalle por camión para Flota.
  perform set_config('request.jwt.claims', c_alejandro, true);
  select count(*) into v_n from pesadas_de_pedido_flota(v_528.pedido_id) where numero_vale like 'I-%' and neto_tn > 0;
  if v_n <> 2 then raise exception 'G1: % filas', v_n; end if;
  perform set_config('request.jwt.claims', c_nadie, true);
  begin perform * from pesadas_de_pedido_flota(v_528.pedido_id); raise exception 'G2';
  exception when others then if sqlerrm not like '%No tenés permiso para ver%' then raise; end if; end;
  v_ok := v_ok || 'G pesadas_de_pedido_flota: 2 camiones de PED-0528 para Compras; sin permiso, rechaza'::text;

  -- J. Permisos: vincular/desvincular DESPUÉS solo admin, Compras/Admin de Flota y autorizados (Félix).
  perform set_config('request.jwt.claims', c_balanza, true);
  v_r := registrar_ingreso_pedido_flota(v_514.id, 40, 13, 'ASFALTO CA30', 'PROVEEDOR ENSAYO 81', 'ENSAYO81-J', 27);  -- balanza al pesar: sí
  if not (v_r->>'vinculado')::boolean then raise exception 'J1: la balanza no pudo pesar contra el pedido'; end if;
  select id into v_ing from plantas_ingresos where vale_id = (v_r->>'vale_id')::uuid;
  begin perform desvincular_pesada_pedido_flota(v_ing, 'x'); raise exception 'J2';
  exception when others then if sqlerrm not like '%lo hacen admin, Félix o Compras%' then raise; end if; end;
  perform set_config('request.jwt.claims', '{"email":"juan.marun@vialtec.com.ar","role":"authenticated"}', true);  -- otro plantista: no
  begin perform desvincular_pesada_pedido_flota(v_ing, 'x'); raise exception 'J3';
  exception when others then if sqlerrm not like '%lo hacen admin, Félix o Compras%' then raise; end if; end;
  perform set_config('request.jwt.claims', '{"email":"felix.pereyra@vialtec.com.ar","role":"authenticated"}', true);  -- Félix: sí
  perform desvincular_pesada_pedido_flota(v_ing, 'Ensayo 81 Félix');
  perform set_config('request.jwt.claims', c_balanza, true);
  begin perform vincular_pesada_pedido_flota(v_ing, v_514.id); raise exception 'J4';
  exception when others then if sqlerrm not like '%lo hacen admin, Félix o Compras%' then raise; end if; end;
  perform set_config('request.jwt.claims', '{"email":"federico.mazzeo@vialtec.com.ar","role":"authenticated"}', true);  -- admin: sí
  v_r := vincular_pesada_pedido_flota(v_ing, v_514.id);
  if not (v_r->>'item_recibido')::boolean then raise exception 'J5: %', v_r; end if;
  if has_function_privilege('authenticated', 'plantas_vincular_pesada_interna(uuid, uuid)', 'execute') then raise exception 'J6: interna expuesta'; end if;
  v_ok := v_ok || 'J permisos: balanza pesa contra pedido; balancero y otro plantista no vinculan/desvinculan después; Félix, Alejandro y admin sí'::text;

  -- K. D6: aviso "pesada sin pedido" al confirmar (trigger diferido), y descartado al anular.
  perform set_config('request.jwt.claims', c_balanza, true);
  v_r := registrar_ingreso_pedido_flota(v_531.id, 40, 13, 'ASFALTO CA30', 'PROVEEDOR ENSAYO 81', 'ENSAYO81-K', 27);  -- 0531 ya recibido: sin pedido
  if (v_r->>'vinculado')::boolean then raise exception 'K1: %', v_r; end if;
  select id into v_ing_k from plantas_ingresos where vale_id = (v_r->>'vale_id')::uuid;
  if exists (select 1 from pg_temp._avisos where ingreso_id = v_ing_k) then raise exception 'K2: el aviso salió antes de confirmar'; end if;
  set constraints plantas_ingresos_sin_pedido_flota immediate;  -- como al confirmar la transacción
  if not exists (select 1 from pg_temp._avisos where accion = 'crear' and tipo = 'pesada_sin_pedido' and ingreso_id = v_ing_k and titulo like '%ASFALTO CA30%') then raise exception 'K3: sin aviso'; end if;
  if not exists (select 1 from pg_temp._avisos where accion = 'crear' and ingreso_id = v_ing_b) then raise exception 'K4: la desvinculada (B/C) no avisó'; end if;
  if exists (select 1 from pg_temp._avisos where accion = 'crear' and ingreso_id = v_ing) then raise exception 'K5: avisó una pesada vinculada (J)'; end if;
  update plantas_ingresos set anulado = true where id = v_ing_k;
  if not exists (select 1 from pg_temp._avisos where accion = 'descartado' and tipo = 'pesada_sin_pedido' and ingreso_id = v_ing_k) then raise exception 'K6: no se descartó al anular'; end if;
  v_ok := v_ok || 'K aviso pesada sin pedido: sale al confirmar (no antes), también la desvinculada, no la vinculada; al anular se descarta'::text;

  -- H. Nada más cambió.
  v_otros_d := (select md5(string_agg(i::text, ',' order by i.id)) from flota_pedido_items i where i.pedido_id not in (v_531.pedido_id, v_536.pedido_id, v_528.pedido_id, v_514.pedido_id));
  v_md5_d := (select string_agg(md5(pg_get_functiondef(oid)), ',' order by proname) from pg_proc
               where proname in ('registrar_pesada_bascula', 'anular_vale_bascula', 'corregir_vale_bascula', 'fn_pedidos_avisos',
                                 'plantas_pedidos_flota_pendientes', 'pesadas_sin_pedido_flota'));
  if v_otros_d <> v_otros then raise exception 'H1: se movieron otros pedidos'; end if;
  if v_md5_d <> v_md5 then raise exception 'H2: cambió una función que no debía'; end if;
  if has_function_privilege('authenticated', 'plantas_cerrar_item_flota_si_completo(uuid)', 'execute')
     or has_function_privilege('authenticated', 'plantas_recalcular_pedido_flota(uuid)', 'execute')
     or has_function_privilege('anon', 'pesadas_de_pedido_flota(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'pesadas_de_pedido_flota(uuid)', 'execute')
     or has_table_privilege('authenticated', 'plantas_cierres_flota', 'insert')
     or has_table_privilege('authenticated', 'plantas_vinculo_flota_autorizados', 'select')
     or has_function_privilege('authenticated', 'plantas_trg_ingreso_sin_pedido_flota()', 'execute') then
    raise exception 'H3: permisos'; end if;
  v_ok := v_ok || 'H otros pedidos y funciones intactos, permisos OK'::text;

  -- I. Vuelta atrás (revertir_migracion_81.sql sin begin/commit).
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
  if exists (select 1 from pg_proc where proname in ('pesadas_de_pedido_flota', 'plantas_cerrar_item_flota_si_completo', 'plantas_recalcular_pedido_flota',
                                                     'plantas_vincular_pesada_interna', 'plantas_puede_vincular_despues', 'plantas_trg_ingreso_sin_pedido_flota'))
     or to_regclass('public.plantas_vinculo_flota_autorizados') is not null
     or exists (select 1 from pg_trigger where tgname = 'plantas_ingresos_sin_pedido_flota')
     or to_regclass('public.plantas_cierres_flota') is not null
     or exists (select 1 from pg_proc p join pg_temp._md5_80 a on a.proname = p.proname where md5(pg_get_functiondef(p.oid)) <> a.h)
     or (select count(*) from pg_temp._md5_80) <> 6 then
    raise exception 'I: la vuelta atrás dejó restos o funciones distintas'; end if;
  v_ok := v_ok || 'I vuelta atrás: las 6 funciones como antes de la 81, tablas, trigger y funciones nuevas borradas'::text;

  perform setval('plantas_vales_numero_arido_seq', v_seq_antes, v_seq_llam);
  raise exception 'DRYRUN 81 OK — %', array_to_string(v_ok, ' || ');
exception when others then
  if v_seq_antes is not null then perform setval('plantas_vales_numero_arido_seq', v_seq_antes, v_seq_llam); end if;
  raise;
end;
$dry$;
