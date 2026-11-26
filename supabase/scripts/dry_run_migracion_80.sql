-- ============================================================================
-- Ensayo de la migración 80 (pedido de Flota completo sale de balanza).
-- Correr en UNA sola ejecución: este bloque de "antes", luego
-- 80_pedido_flota_completo_sale_de_balanza.sql, luego el DO de abajo.
-- Termina SIEMPRE con ERROR "DRYRUN 80 OK — …" (todo revertido, incluida la
-- numeración de vales de áridos). Usa ítems reales pendientes: CA30 de 1
-- camión, CA30 de 2 camiones y CEMENTO (pasado a "por cantidad" dentro del
-- ensayo). Incluye la vuelta atrás (revertir_migracion_80.sql sin begin/commit).
-- ============================================================================
-- [ANTES] md5 de las dos funciones tal como las dejó la 79:
--   create temp table _md5_79 on commit drop as
--   select proname, md5(pg_get_functiondef(oid)) h from pg_proc
--    where proname in ('plantas_pedidos_flota_pendientes', 'registrar_ingreso_pedido_flota');
do $dry$
declare
  v_ok text[] := '{}'; v_seq_antes bigint; v_seq_llam boolean;
  v_uno flota_pedido_items; v_dos flota_pedido_items; v_cem flota_pedido_items; v_it flota_pedido_items;
  v_r jsonb; v_n int; v_otros text; v_otros_d text; v_md5 text; v_md5_d text;
  c_balanza constant text := '{"email":"balanza@vialtec.com.ar","role":"authenticated"}';
begin
  select last_value, is_called into v_seq_antes, v_seq_llam from plantas_vales_numero_arido_seq;
  perform set_config('request.jwt.claims', c_balanza, true);

  select i.* into v_uno from flota_pedido_items i join flota_pedidos p on p.id = i.pedido_id join plantas_materiales m on m.id = i.material_planta_id
   where p.modulo = 'plantas' and p.estado in ('en_compras','parcialmente_abierto') and i.estado_item = 'pendiente'
     and m.nombre = 'ASFALTO CA30' and i.pedido_por = 'camion' and i.camiones = 1 and coalesce(i.camiones_recibidos, 0) = 0 order by p.numero limit 1;
  select i.* into v_dos from flota_pedido_items i join flota_pedidos p on p.id = i.pedido_id join plantas_materiales m on m.id = i.material_planta_id
   where p.modulo = 'plantas' and p.estado in ('en_compras','parcialmente_abierto') and i.estado_item = 'pendiente'
     and m.nombre = 'ASFALTO CA30' and i.pedido_por = 'camion' and i.camiones = 2 and coalesce(i.camiones_recibidos, 0) = 0 order by p.numero limit 1;
  select i.* into v_cem from flota_pedido_items i join flota_pedidos p on p.id = i.pedido_id join plantas_materiales m on m.id = i.material_planta_id
   where p.modulo = 'plantas' and p.estado in ('en_compras','parcialmente_abierto') and i.estado_item = 'pendiente'
     and m.nombre = 'CEMENTO' and upper(i.unidad) = 'TN' and coalesce(i.camiones_recibidos, 0) = 0 order by p.numero limit 1;
  if v_uno.id is null or v_dos.id is null or v_cem.id is null then raise exception 'Precondición: faltan ítems pendientes'; end if;

  v_otros := (select md5(string_agg(i::text, ',' order by i.id)) from flota_pedido_items i where i.id not in (v_uno.id, v_dos.id, v_cem.id));
  v_md5 := (select string_agg(md5(pg_get_functiondef(oid)), ',' order by proname) from pg_proc
             where proname in ('vincular_pesada_pedido_flota', 'desvincular_pesada_pedido_flota', 'pesadas_sin_pedido_flota',
                               'registrar_pesada_bascula', 'anular_vale_bascula', 'corregir_vale_bascula'));

  -- A. Regla de "completo" sobre copias en memoria.
  v_it := v_dos; v_it.camiones_recibidos := 1;      if plantas_item_flota_completo(v_it) then raise exception 'A1'; end if;
  v_it.camiones_recibidos := 2;                      if not plantas_item_flota_completo(v_it) then raise exception 'A2'; end if;
  v_it.camiones_recibidos := 3;                      if not plantas_item_flota_completo(v_it) then raise exception 'A3'; end if;
  v_it.camiones_recibidos := null;                   if plantas_item_flota_completo(v_it) then raise exception 'A4'; end if;
  v_it.pedido_por := 'cantidad'; v_it.cantidad := 30; v_it.cantidad_real := 29.999; if plantas_item_flota_completo(v_it) then raise exception 'A5'; end if;
  v_it.cantidad_real := 30;                          if not plantas_item_flota_completo(v_it) then raise exception 'A6'; end if;
  v_it.cantidad := null;                             if plantas_item_flota_completo(v_it) then raise exception 'A7'; end if;
  v_ok := v_ok || 'A regla completo: camión 1/2 no, 2/2 y 3/2 sí; cantidad 29,999/30 no, 30/30 sí; sin número nunca'::text;

  -- B. Listado: los 3 están; con su camión cargado a mano en Flota, el de 1 camión sale.
  select count(*) into v_n from plantas_pedidos_flota_pendientes() l where l.item_id in (v_uno.id, v_dos.id, v_cem.id);
  if v_n <> 3 then raise exception 'B1: listado (%)', v_n; end if;
  update flota_pedido_items set camiones_recibidos = 1 where id = v_uno.id;
  if exists (select 1 from plantas_pedidos_flota_pendientes() where item_id = v_uno.id) then raise exception 'B2: completo sigue en la lista'; end if;
  v_ok := v_ok || 'B listado: completo (1/1, sin recibir por Compras) ya no aparece'::text;

  -- C. Uno de más contra el completo: se guarda SIN pedido, con aviso; Flota no cambia.
  v_r := registrar_ingreso_pedido_flota(v_uno.id, 40, 12, 'ASFALTO CA30', 'PROVEEDOR ENSAYO', 'ENSAYO80-C', 28);
  if (v_r->>'vinculado')::boolean or v_r->>'aviso' not like '%SIN pedido%ya tiene su camión)%' then raise exception 'C1: %', v_r; end if;
  select * into v_it from flota_pedido_items where id = v_uno.id;
  if v_it.camiones_recibidos <> 1 or v_it.cantidad_real is not null
     or exists (select 1 from flota_pedido_item_ingresos_planta l join plantas_ingresos g on g.id = l.ingreso_id where g.vale_id = (v_r->>'vale_id')::uuid) then
    raise exception 'C2: se sumó al completo'; end if;
  if not exists (select 1 from plantas_vales where id = (v_r->>'vale_id')::uuid) then raise exception 'C3: no se guardó el vale'; end if;
  v_ok := v_ok || ('C uno de más: vale guardado sin pedido, aviso "' || (v_r->>'aviso') || '"')::text;

  -- D. Pedido de 2 camiones: 1º suma y sigue en la lista (falta 1), 2º suma y sale, 3º sin pedido.
  v_r := registrar_ingreso_pedido_flota(v_dos.id, 40, 12, 'ASFALTO CA30', 'PROVEEDOR ENSAYO', 'ENSAYO80-D1', 28);
  if not (v_r->>'vinculado')::boolean then raise exception 'D1: %', v_r; end if;
  if not exists (select 1 from plantas_pedidos_flota_pendientes() where item_id = v_dos.id and camiones_recibidos = 1) then raise exception 'D2: con 1 de 2 debería seguir'; end if;
  v_r := registrar_ingreso_pedido_flota(v_dos.id, 41, 12, 'ASFALTO CA30', 'PROVEEDOR ENSAYO', 'ENSAYO80-D2', 29);
  if not (v_r->>'vinculado')::boolean then raise exception 'D3: %', v_r; end if;
  if exists (select 1 from plantas_pedidos_flota_pendientes() where item_id = v_dos.id) then raise exception 'D4: con 2 de 2 sigue'; end if;
  v_r := registrar_ingreso_pedido_flota(v_dos.id, 40, 12, 'ASFALTO CA30', 'PROVEEDOR ENSAYO', 'ENSAYO80-D3', 28);
  if (v_r->>'vinculado')::boolean or v_r->>'aviso' not like '%ya tiene sus 2 camiones%' then raise exception 'D5: %', v_r; end if;
  select * into v_it from flota_pedido_items where id = v_dos.id;
  select count(*) into v_n from flota_pedido_item_ingresos_planta where item_id = v_dos.id;
  if v_it.camiones_recibidos <> 2 or v_it.cantidad_real <> 57 or v_n <> 2 or v_it.estado_item <> 'pendiente' then
    raise exception 'D6: % camiones, % tn, % vínculos, %', v_it.camiones_recibidos, v_it.cantidad_real, v_n, v_it.estado_item; end if;
  v_ok := v_ok || 'D 2 camiones: 1/2 sigue, 2/2 sale (57 tn, sigue pendiente para Compras), el 3º sin pedido'::text;

  -- E. Por cantidad (CEMENTO pasado a 50 TN en el ensayo): 28 sigue, 56 sale, el siguiente sin pedido.
  update flota_pedido_items set pedido_por = 'cantidad', cantidad = 50, camiones = null where id = v_cem.id;
  v_r := registrar_ingreso_pedido_flota(v_cem.id, 40, 12, 'CEMENTO', 'PROVEEDOR ENSAYO', 'ENSAYO80-E1', 28);
  if not (v_r->>'vinculado')::boolean or not exists (select 1 from plantas_pedidos_flota_pendientes() where item_id = v_cem.id) then raise exception 'E1: %', v_r; end if;
  v_r := registrar_ingreso_pedido_flota(v_cem.id, 40, 12, 'CEMENTO', 'PROVEEDOR ENSAYO', 'ENSAYO80-E2', 28);
  if not (v_r->>'vinculado')::boolean or exists (select 1 from plantas_pedidos_flota_pendientes() where item_id = v_cem.id) then raise exception 'E2: %', v_r; end if;
  v_r := registrar_ingreso_pedido_flota(v_cem.id, 40, 12, 'CEMENTO', 'PROVEEDOR ENSAYO', 'ENSAYO80-E3', 28);
  if (v_r->>'vinculado')::boolean or v_r->>'aviso' not like '%ya tiene sus 50 TN%' then raise exception 'E3: %', v_r; end if;
  v_ok := v_ok || 'E por cantidad: 28/50 sigue, 56/50 sale, el siguiente sin pedido'::text;

  -- F. Nada más cambió.
  v_otros_d := (select md5(string_agg(i::text, ',' order by i.id)) from flota_pedido_items i where i.id not in (v_uno.id, v_dos.id, v_cem.id));
  v_md5_d := (select string_agg(md5(pg_get_functiondef(oid)), ',' order by proname) from pg_proc
               where proname in ('vincular_pesada_pedido_flota', 'desvincular_pesada_pedido_flota', 'pesadas_sin_pedido_flota',
                                 'registrar_pesada_bascula', 'anular_vale_bascula', 'corregir_vale_bascula'));
  if v_otros_d <> v_otros then raise exception 'F1: se movieron otros ítems de Flota'; end if;
  if v_md5_d <> v_md5 then raise exception 'F2: cambió una función de Flota o Báscula'; end if;
  if has_function_privilege('authenticated', 'plantas_item_flota_completo(flota_pedido_items)', 'execute')
     or has_function_privilege('anon', 'plantas_pedidos_flota_pendientes()', 'execute')
     or not has_function_privilege('authenticated', 'plantas_pedidos_flota_pendientes()', 'execute')
     or not has_function_privilege('authenticated', 'registrar_ingreso_pedido_flota(uuid, numeric, numeric, text, text, text, numeric, text, text, text, timestamptz)', 'execute') then
    raise exception 'F3: permisos'; end if;
  v_ok := v_ok || 'F otros ítems de Flota intactos, vincular/desvincular y Báscula sin cambios, permisos OK'::text;

  -- G. Vuelta atrás (revertir_migracion_80.sql sin begin/commit).
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
  if exists (select 1 from pg_proc where proname = 'plantas_item_flota_completo')
     or exists (select 1 from pg_proc p join pg_temp._md5_79 a on a.proname = p.proname where md5(pg_get_functiondef(p.oid)) <> a.h)
     or (select count(*) from pg_temp._md5_79) <> 2 then
    raise exception 'G1: la vuelta atrás no dejó las funciones de la 79'; end if;
  if not exists (select 1 from plantas_pedidos_flota_pendientes() where item_id = v_dos.id) then raise exception 'G2: con la 79, el completo vuelve a aparecer'; end if;
  v_ok := v_ok || 'G vuelta atrás: funciones idénticas a la 79, helper borrado, el completo vuelve a la lista'::text;

  perform setval('plantas_vales_numero_arido_seq', v_seq_antes, v_seq_llam);
  raise exception 'DRYRUN 80 OK — %', array_to_string(v_ok, ' || ');
exception when others then
  if v_seq_antes is not null then perform setval('plantas_vales_numero_arido_seq', v_seq_antes, v_seq_llam); end if;
  raise;
end;
$dry$;
