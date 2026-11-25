-- ============================================================================
-- Ensayo de la migración 79 (ingreso contra pedido de Flota + vincular después).
-- Correr DESPUÉS de 79_ingreso_contra_pedido_flota.sql, en la misma ejecución.
-- Termina SIEMPRE con ERROR "DRYRUN 79 OK — …" (todo revertido).
-- Incluye al final la prueba de la vuelta atrás (revertir_migracion_79.sql sin
-- begin/commit). La numeración de vales de áridos se devuelve a su valor.
-- Usa ítems reales pendientes (CEMENTO y ASFALTO CA30, en TN) y uno recibido.
-- ============================================================================
do $dry$
declare
  v_ok text[] := '{}'; v_seq_antes bigint; v_seq_llam boolean;
  v_cem flota_pedido_items; v_ca30 flota_pedido_items; v_rec flota_pedido_items; v_rec_mat text;
  v_r jsonb; v_it flota_pedido_items; v_vale plantas_vales; v_ing1 uuid; v_ing2 uuid; v_ing3 uuid;
  v_stock0 numeric; v_stock1 numeric; v_n int;
  v_otros text; v_otros_d text; v_est text; v_est_d text;
  v_md5 text; v_md5_d text;
  c_balanza   constant text := '{"email":"balanza@vialtec.com.ar","role":"authenticated"}';
  c_alejandro constant text := '{"email":"alejandro.fernandez@vialtec.com.ar","role":"authenticated"}';
  c_admin     constant text := '{"email":"federico.mazzeo@vialtec.com.ar","role":"authenticated"}';
  c_nadie     constant text := '{"email":"nadie.ensayo79@example.com","role":"authenticated"}';
begin
  select last_value, is_called into v_seq_antes, v_seq_llam from plantas_vales_numero_arido_seq;

  select i.* into v_cem from flota_pedido_items i join flota_pedidos p on p.id = i.pedido_id join plantas_materiales m on m.id = i.material_planta_id
   where p.modulo = 'plantas' and p.estado in ('en_compras','parcialmente_abierto') and i.estado_item = 'pendiente' and m.nombre = 'CEMENTO' and upper(i.unidad) = 'TN' limit 1;
  select i.* into v_ca30 from flota_pedido_items i join flota_pedidos p on p.id = i.pedido_id join plantas_materiales m on m.id = i.material_planta_id
   where p.modulo = 'plantas' and p.estado in ('en_compras','parcialmente_abierto') and i.estado_item = 'pendiente' and m.nombre = 'ASFALTO CA30' and upper(i.unidad) = 'TN' limit 1;
  select i.* into v_rec from flota_pedido_items i join flota_pedidos p on p.id = i.pedido_id join plantas_materiales m on m.id = i.material_planta_id
   where p.modulo = 'plantas' and i.estado_item = 'recibido' and upper(i.unidad) = 'TN' limit 1;
  select nombre into v_rec_mat from plantas_materiales where id = v_rec.material_planta_id;
  if v_cem.id is null or v_ca30.id is null or v_rec.id is null then raise exception 'Precondición: faltan ítems'; end if;

  v_otros := (select md5(string_agg(i::text, ',' order by i.id)) from flota_pedido_items i where i.id not in (v_cem.id, v_ca30.id));
  v_est := (select md5(string_agg(p.id::text || p.estado, ',' order by p.id)) from flota_pedidos p)
        || (select md5(string_agg(i.id::text || coalesce(i.estado_item, ''), ',' order by i.id)) from flota_pedido_items i);
  v_stock0 := (select s.cantidad_kg from plantas_stock s join plantas_materiales m on m.id = s.material_id where m.nombre = 'CEMENTO');
  v_md5 := (select string_agg(md5(pg_get_functiondef(oid)), ',' order by proname) from pg_proc
             where proname in ('registrar_pesada_bascula', 'anular_vale_bascula', 'corregir_vale_bascula'));

  -- A. Sin permiso (autenticado, ni Plantas ni Flota): todo rechazado.
  perform set_config('request.jwt.claims', c_nadie, true);
  begin perform * from plantas_pedidos_flota_pendientes(); raise exception 'A1';
  exception when others then if sqlerrm not like '%no puede ver los pedidos de Flota%' then raise; end if; end;
  begin perform registrar_ingreso_pedido_flota(v_cem.id, 40, 12, 'CEMENTO', 'X', 'ENSAYO79-A', 28); raise exception 'A2';
  exception when others then if sqlerrm not like '%no puede registrar pesadas%' then raise; end if; end;
  begin perform vincular_pesada_pedido_flota(gen_random_uuid(), v_cem.id); raise exception 'A3';
  exception when others then if sqlerrm not like '%No tenés permiso para vincular%' then raise; end if; end;
  begin perform * from pesadas_sin_pedido_flota(v_cem.id); raise exception 'A4';
  exception when others then if sqlerrm not like '%No tenés permiso para ver%' then raise; end if; end;
  begin perform desvincular_pesada_pedido_flota(gen_random_uuid(), 'x'); raise exception 'A5';
  exception when others then if sqlerrm not like '%No tenés permiso para desvincular%' then raise; end if; end;
  v_ok := v_ok || 'A sin permiso: las 5 funciones rechazan'::text;

  -- B. Balanza: listado con los pendientes, sin L ni recibidos.
  perform set_config('request.jwt.claims', c_balanza, true);
  select count(*) into v_n from plantas_pedidos_flota_pendientes() l where l.item_id in (v_cem.id, v_ca30.id);
  if v_n <> 2 then raise exception 'B: listado (%)', v_n; end if;
  if exists (select 1 from plantas_pedidos_flota_pendientes() l where l.unidad not in ('TN','KG') or l.item_id = v_rec.id) then raise exception 'B: L o recibidos'; end if;
  v_ok := v_ok || 'B listado de balanza OK'::text;

  -- C. Material distinto: error y no se guarda nada.
  select count(*) into v_n from plantas_ingresos;
  begin perform registrar_ingreso_pedido_flota(v_ca30.id, 40, 12, 'CEMENTO', 'X', 'ENSAYO79-C', 28); raise exception 'C';
  exception when others then if sqlerrm not like '%es de ASFALTO CA30, no de CEMENTO%' then raise; end if; end;
  if (select count(*) from plantas_ingresos) <> v_n then raise exception 'C: guardó algo'; end if;
  v_ok := v_ok || 'C material distinto: rechazado, nada guardado'::text;

  -- D. Balanza pesa CEMENTO contra el pedido: vinculado, +1 camión, +28 tn, stock +28,5 (remito).
  v_r := registrar_ingreso_pedido_flota(v_cem.id, 40, 12, 'CEMENTO', 'PROVEEDOR ENSAYO', 'ENSAYO79-D', 28.5, 'AAA000');
  if not (v_r ->> 'vinculado')::boolean then raise exception 'D: no vinculó %', v_r; end if;
  select id into v_ing1 from plantas_ingresos where vale_id = (v_r ->> 'vale_id')::uuid;
  select * into v_it from flota_pedido_items where id = v_cem.id;
  if v_it.camiones_recibidos is distinct from coalesce(v_cem.camiones_recibidos, 0) + 1
     or v_it.cantidad_real is distinct from coalesce(v_cem.cantidad_real, 0) + 28 or v_it.estado_item <> 'pendiente' then
    raise exception 'D: ítem % / % / %', v_it.camiones_recibidos, v_it.cantidad_real, v_it.estado_item; end if;
  if not exists (select 1 from flota_pedido_item_ingresos_planta where ingreso_id = v_ing1 and cantidad_sumada = 28 and creado_por = 'balanza@vialtec.com.ar') then
    raise exception 'D: vínculo'; end if;
  v_stock1 := (select s.cantidad_kg from plantas_stock s join plantas_materiales m on m.id = s.material_id where m.nombre = 'CEMENTO');
  if v_stock1 - v_stock0 <> 28500 then raise exception 'D: stock %', v_stock1 - v_stock0; end if;
  v_ok := v_ok || 'D balanza con pedido: vínculo (28), +1 camión, +28 tn, ítem pendiente, stock +28,5 tn por remito'::text;

  -- E. Dos pesadas de CEMENTO sin pedido (camino de siempre).
  v_vale := registrar_pesada_bascula(p_tipo_vale => 'ingreso_arido', p_peso_bruto => 42, p_tara => 12, p_material => 'CEMENTO',
              p_proveedor => 'PROVEEDOR ENSAYO', p_numero_remito => 'ENSAYO79-E1', p_cantidad_remito => 30);
  select id into v_ing2 from plantas_ingresos where vale_id = v_vale.id;
  v_vale := registrar_pesada_bascula(p_tipo_vale => 'ingreso_arido', p_peso_bruto => 41, p_tara => 12, p_material => 'CEMENTO',
              p_proveedor => 'PROVEEDOR ENSAYO', p_numero_remito => 'ENSAYO79-E2', p_cantidad_remito => 29);
  select id into v_ing3 from plantas_ingresos where vale_id = v_vale.id;

  -- F. Alejandro (Flota) las ve, vincula una, y no puede repetir ni cruzar material.
  perform set_config('request.jwt.claims', c_alejandro, true);
  if (select count(*) from pesadas_sin_pedido_flota(v_cem.id) where ingreso_id in (v_ing2, v_ing3)) <> 2
     or exists (select 1 from pesadas_sin_pedido_flota(v_cem.id) where ingreso_id = v_ing1) then
    raise exception 'F: listado sin pedido'; end if;
  if (select neto from pesadas_sin_pedido_flota(v_cem.id) where ingreso_id = v_ing2) <> 30 then raise exception 'F: neto del listado'; end if;
  v_r := vincular_pesada_pedido_flota(v_ing2, v_cem.id);
  select * into v_it from flota_pedido_items where id = v_cem.id;
  if v_it.camiones_recibidos <> coalesce(v_cem.camiones_recibidos, 0) + 2 or v_it.cantidad_real <> coalesce(v_cem.cantidad_real, 0) + 58 then
    raise exception 'F: ítem % / %', v_it.camiones_recibidos, v_it.cantidad_real; end if;
  begin perform vincular_pesada_pedido_flota(v_ing2, v_cem.id); raise exception 'F2';
  exception when others then if sqlerrm not like '%ya está vinculada%' then raise; end if; end;
  begin perform vincular_pesada_pedido_flota(v_ing3, v_ca30.id); raise exception 'F3';
  exception when others then if sqlerrm not like '%es de ASFALTO CA30, la pesada es de CEMENTO%' then raise; end if; end;
  begin insert into flota_pedido_item_ingresos_planta (item_id, ingreso_id) values (v_ca30.id, v_ing2); raise exception 'F4';
  exception when unique_violation then null; end;
  begin perform vincular_pesada_pedido_flota(v_ing3, v_rec.id); raise exception 'F5';
  exception when others then if sqlerrm not like '%no recibe pesadas%' then raise; end if; end;
  v_ok := v_ok || 'F Flota: ve 2 sin pedido (7 días), vincula 1 (+30 → 58 tn), rechaza repetir, otro material, doble vínculo (UNIQUE) e ítem recibido'::text;

  -- G. Alejandro desvincula: exige motivo y resta.
  begin perform desvincular_pesada_pedido_flota(v_ing2, ' '); raise exception 'G1';
  exception when others then if sqlerrm not like '%motivo es obligatorio%' then raise; end if; end;
  perform desvincular_pesada_pedido_flota(v_ing2, 'Ensayo: era de otro pedido');
  select * into v_it from flota_pedido_items where id = v_cem.id;
  if v_it.camiones_recibidos <> coalesce(v_cem.camiones_recibidos, 0) + 1 or v_it.cantidad_real <> coalesce(v_cem.cantidad_real, 0) + 28 then
    raise exception 'G: ítem % / %', v_it.camiones_recibidos, v_it.cantidad_real; end if;
  if not exists (select 1 from pesadas_sin_pedido_flota(v_cem.id) where ingreso_id = v_ing2) then raise exception 'G: no volvió a sin pedido'; end if;
  v_ok := v_ok || 'G desvincular: motivo obligatorio, resta (vuelve a 1 camión / 28 tn), la pesada vuelve a "sin pedido"'::text;

  -- H. Anular en Báscula la pesada vinculada (D): resta y el ítem vuelve a vacío.
  perform set_config('request.jwt.claims', c_admin, true);
  perform anular_vale_bascula((select vale_id from plantas_ingresos where id = v_ing1), 'Ensayo 79');
  select * into v_it from flota_pedido_items where id = v_cem.id;
  if v_it.camiones_recibidos is distinct from v_cem.camiones_recibidos or v_it.cantidad_real is distinct from v_cem.cantidad_real then
    raise exception 'H: ítem % / % (antes % / %)', v_it.camiones_recibidos, v_it.cantidad_real, v_cem.camiones_recibidos, v_cem.cantidad_real; end if;
  if exists (select 1 from flota_pedido_item_ingresos_planta where ingreso_id = v_ing1) then raise exception 'H: quedó el vínculo'; end if;
  v_ok := v_ok || 'H anular pesada vinculada: resta, ítem como antes, vínculo fuera'::text;

  -- I. Balanza pesa contra un ítem ya recibido: se guarda SIN pedido, con aviso.
  perform set_config('request.jwt.claims', c_balanza, true);
  v_r := registrar_ingreso_pedido_flota(v_rec.id, 40, 12, v_rec_mat, 'PROVEEDOR ENSAYO', 'ENSAYO79-I', 28);
  if (v_r ->> 'vinculado')::boolean or v_r ->> 'aviso' not like '%SIN pedido%' then raise exception 'I: %', v_r; end if;
  if exists (select 1 from flota_pedido_item_ingresos_planta l join plantas_ingresos g on g.id = l.ingreso_id where g.vale_id = (v_r ->> 'vale_id')::uuid) then
    raise exception 'I: vinculó'; end if;
  v_ok := v_ok || 'I ítem ya recibido: pesada guardada sin pedido, con aviso'::text;

  -- J. Pesada en kg sobre ítem en TN.
  v_r := registrar_ingreso_pedido_flota(v_ca30.id, 40000, 12000, 'ASFALTO CA30', 'PROVEEDOR ENSAYO', 'ENSAYO79-J', 28, null, 'kg');
  select * into v_it from flota_pedido_items where id = v_ca30.id;
  if v_it.cantidad_real <> coalesce(v_ca30.cantidad_real, 0) + 28 then raise exception 'J: %', v_it.cantidad_real; end if;
  v_ok := v_ok || 'J pesada en kg → +28 tn'::text;

  -- K. Nada más se movió; funciones de Báscula intactas; permisos; auditoría.
  v_otros_d := (select md5(string_agg(i::text, ',' order by i.id)) from flota_pedido_items i where i.id not in (v_cem.id, v_ca30.id));
  v_est_d := (select md5(string_agg(p.id::text || p.estado, ',' order by p.id)) from flota_pedidos p)
          || (select md5(string_agg(i.id::text || coalesce(i.estado_item, ''), ',' order by i.id)) from flota_pedido_items i);
  if v_otros_d <> v_otros or v_est_d <> v_est then raise exception 'K: se movió algo más de Flota'; end if;
  v_md5_d := (select string_agg(md5(pg_get_functiondef(oid)), ',' order by proname) from pg_proc
               where proname in ('registrar_pesada_bascula', 'anular_vale_bascula', 'corregir_vale_bascula'));
  if v_md5_d <> v_md5 then raise exception 'K: cambió una función de Báscula'; end if;
  if has_function_privilege('authenticated', 'plantas_restar_pesada_de_item(uuid, text, boolean)', 'execute')
     or has_function_privilege('anon', 'vincular_pesada_pedido_flota(uuid, uuid)', 'execute')
     or has_function_privilege('anon', 'pesadas_sin_pedido_flota(uuid, integer)', 'execute')
     or not has_function_privilege('authenticated', 'desvincular_pesada_pedido_flota(uuid, text)', 'execute') then
    raise exception 'K: permisos'; end if;
  select count(*) into v_n from plantas_auditoria where modulo = 'bascula' and entidad = 'vinculo_flota';
  if v_n <> 5 then raise exception 'K: auditoría % (esperado 5: 3 vínculos + desvincular + anulación)', v_n; end if;
  v_ok := v_ok || 'K otros ítems y estados de Flota intactos, Báscula intacta, permisos OK, 5 filas de auditoría'::text;

  -- L. Vuelta atrás (revertir_migracion_79.sql sin begin/commit).
  drop trigger if exists plantas_ingresos_anulado_flota on public.plantas_ingresos;
  drop function if exists public.plantas_trg_ingreso_anulado_flota();
  drop function if exists public.registrar_ingreso_pedido_flota(uuid, numeric, numeric, text, text, text, numeric, text, text, text, timestamptz);
  drop function if exists public.pesadas_sin_pedido_flota(uuid, integer);
  drop function if exists public.desvincular_pesada_pedido_flota(uuid, text);
  drop function if exists public.plantas_restar_pesada_de_item(uuid, text, boolean);
  drop function if exists public.vincular_pesada_pedido_flota(uuid, uuid);
  drop function if exists public.plantas_pedidos_flota_pendientes();
  drop function if exists public.plantas_puede_vincular_flota();
  alter table public.flota_pedido_item_ingresos_planta
    drop constraint if exists flota_pedido_item_ingresos_planta_ingreso_unico,
    drop column if exists cantidad_sumada;
  if exists (select 1 from pg_proc where proname in ('vincular_pesada_pedido_flota','registrar_ingreso_pedido_flota','plantas_puede_vincular_flota'))
     or exists (select 1 from pg_trigger where tgname = 'plantas_ingresos_anulado_flota')
     or (select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns
          where table_schema = 'public' and table_name = 'flota_pedido_item_ingresos_planta') <> 'item_id,ingreso_id,creado_at,creado_por' then
    raise exception 'L: la vuelta atrás dejó restos'; end if;
  v_ok := v_ok || 'L vuelta atrás: sin funciones ni trigger, tabla de Flota como antes'::text;

  perform setval('plantas_vales_numero_arido_seq', v_seq_antes, v_seq_llam);
  raise exception 'DRYRUN 79 OK — %', array_to_string(v_ok, ' || ');
exception when others then
  if v_seq_antes is not null then perform setval('plantas_vales_numero_arido_seq', v_seq_antes, v_seq_llam); end if;
  raise;
end;
$dry$;
