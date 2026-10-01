-- ============================================================================
-- Dry-run de la migración 49 (tipo 'mezcla_cemento') contra producción.
-- Todo corre dentro de un DO que termina SIEMPRE con raise exception: no
-- persiste nada (ni el DDL ni las filas de prueba). El resultado se lee en el
-- mensaje de la excepción: "DRYRUN 49 OK ..." o el chequeo que falló.
-- ============================================================================
do $dry$
declare
  v_admin text; v_ph text; v_enc text;
  v_n_ped int; v_n_for int; v_n_car int; v_n_mov int;
  v_formula uuid; v_pedido uuid; v_asf uuid; v_residual plantas_pedidos; v_p plantas_pedidos;
  v_cem_antes numeric; v_are_antes numeric; v_cem numeric; v_are numeric;
  v_ok text := '';
  v_fallo boolean;
begin
  select count(*) into v_n_ped from plantas_pedidos;
  select count(*) into v_n_for from plantas_formulas;
  select count(*) into v_n_car from plantas_cargas_hormigon;
  select count(*) into v_n_mov from plantas_stock_movimientos;

  execute $mig49$
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

  $mig49$;

  -- 1) El DDL no tocó filas
  if (select count(*) from plantas_pedidos) <> v_n_ped or (select count(*) from plantas_formulas) <> v_n_for
     or (select count(*) from plantas_cargas_hormigon) <> v_n_car or (select count(*) from plantas_stock_movimientos) <> v_n_mov then
    raise exception 'FALLO 1: cambió la cantidad de filas';
  end if;
  if exists (select 1 from plantas_pedidos where tipo = 'mezcla_cemento') or exists (select 1 from plantas_formulas where tipo = 'mezcla_cemento') then
    raise exception 'FALLO 1b: ya hay filas mezcla_cemento';
  end if;
  v_ok := v_ok || '1 filas intactas; ';

  -- 2) Un tipo cualquiera sigue rechazado
  v_fallo := false;
  begin
    insert into plantas_formulas (nombre, tipo, unidad, activo, insumos) values ('DRYRUN X', 'otro', 'tn', false, '[]');
  exception when check_violation then v_fallo := true;
  end;
  if not v_fallo then raise exception 'FALLO 2: aceptó un tipo inválido en fórmulas'; end if;
  v_ok := v_ok || '2 tipo inválido rechazado; ';

  -- 3) Privilegios
  if has_function_privilege('anon', 'registrar_carga_hormigon(uuid,text,numeric,text,text,timestamptz,text)', 'execute') then
    raise exception 'FALLO 3: anon conserva EXECUTE';
  end if;
  if not has_function_privilege('authenticated', 'registrar_carga_hormigon(uuid,text,numeric,text,text,timestamptz,text)', 'execute') then
    raise exception 'FALLO 3: authenticated perdió EXECUTE';
  end if;
  v_ok := v_ok || '3 anon sin EXECUTE, authenticated con; ';

  select email into v_admin from plantas_usuarios_roles where rol = 'admin' and activo limit 1;
  select email into v_ph from plantas_usuarios_roles where rol = 'plantista_hormigon' and activo limit 1;
  select email into v_enc from plantas_usuarios_roles where rol = 'encargado' and activo limit 1;

  -- 4) Fórmula + pedido de mezcla cemento (como admin)
  perform set_config('request.jwt.claims', json_build_object('email', v_admin, 'role', 'authenticated')::text, true);
  insert into plantas_formulas (nombre, tipo, unidad, activo, insumos)
  values ('DRYRUN MEZCLA', 'mezcla_cemento', 'tn', true,
    '[{"material":"Cemento CPC 40","cantidad":800,"unidad":"kg"},{"material":"Arena Silicia","cantidad":200,"unidad":"kg"}]')
  returning id into v_formula;
  insert into plantas_pedidos (formula_id, tipo, cantidad_solicitada, fecha_programada, estado, tipo_pedido, cliente_externo)
  values (v_formula, 'mezcla_cemento', 10, current_date, 'confirmado', 'venta', 'DRYRUN')
  returning id into v_pedido;
  v_ok := v_ok || '4 fórmula y pedido mezcla_cemento creados; ';

  -- 5) Encargado no puede cargar; plantista_hormigon sí
  if v_enc is not null then
    perform set_config('request.jwt.claims', json_build_object('email', v_enc, 'role', 'authenticated')::text, true);
    v_fallo := false;
    begin
      perform registrar_carga_hormigon(v_pedido, 'DRY-0', 1);
    exception when others then v_fallo := true;
    end;
    if not v_fallo then raise exception 'FALLO 5: un encargado pudo registrar la carga'; end if;
  end if;
  if v_ph is null then raise exception 'FALLO 5: no hay usuario plantista_hormigon activo para probar'; end if;
  perform set_config('request.jwt.claims', json_build_object('email', v_ph, 'role', 'authenticated')::text, true);
  perform registrar_carga_hormigon(v_pedido, 'DRY-1', 4);
  perform set_config('request.jwt.claims', json_build_object('email', v_admin, 'role', 'authenticated')::text, true);
  perform registrar_carga_hormigon(v_pedido, 'DRY-2', 3);
  select * into v_p from plantas_pedidos where id = v_pedido;
  if v_p.cantidad_despachada <> 7 then raise exception 'FALLO 5: cantidad_despachada = %', v_p.cantidad_despachada; end if;
  v_ok := v_ok || '5 cargas 4+3 tn (plantista_hormigon y admin), encargado rechazado; ';

  -- 6) Un pedido de asfalto sigue rechazado en este circuito
  insert into plantas_pedidos (formula_id, tipo, cantidad_solicitada, fecha_programada, estado, tipo_pedido, cliente_externo)
  values (v_formula, 'asfalto', 5, current_date, 'confirmado', 'venta', 'DRYRUN')
  returning id into v_asf;
  v_fallo := false;
  begin
    perform registrar_carga_hormigon(v_asf, 'DRY-3', 1);
  exception when others then
    if sqlerrm like '%no es de hormigón ni de mezcla cemento%' then v_fallo := true; else raise; end if;
  end;
  if not v_fallo then raise exception 'FALLO 6: aceptó una carga sobre un pedido de asfalto'; end if;
  v_ok := v_ok || '6 asfalto rechazado; ';

  -- 7) Finalizar con división: descuento de stock y residual
  select s.cantidad_kg into v_cem_antes from plantas_stock s where s.material_id = plantas_buscar_material_id('Cemento CPC 40');
  select s.cantidad_kg into v_are_antes from plantas_stock s where s.material_id = plantas_buscar_material_id('Arena Silicia');
  perform finalizar_despacho(v_pedido, true, current_date + 1);
  select s.cantidad_kg into v_cem from plantas_stock s where s.material_id = plantas_buscar_material_id('Cemento CPC 40');
  select s.cantidad_kg into v_are from plantas_stock s where s.material_id = plantas_buscar_material_id('Arena Silicia');
  select * into v_p from plantas_pedidos where id = v_pedido;
  if v_p.estado <> 'despachado' then raise exception 'FALLO 7: estado = %', v_p.estado; end if;
  if v_cem_antes - v_cem <> 5600 or v_are_antes - v_are <> 1400 then
    raise exception 'FALLO 7: descuento cemento % kg (esperado 5600), arena % kg (esperado 1400)', v_cem_antes - v_cem, v_are_antes - v_are;
  end if;
  select * into v_residual from plantas_pedidos where formula_id = v_formula and estado = 'confirmado' and tipo = 'mezcla_cemento' and id <> v_pedido;
  if not found then raise exception 'FALLO 7: no se creó el residual de mezcla_cemento'; end if;
  if v_residual.cantidad_solicitada <> 3 or v_residual.observaciones not like '%(10 tn)%' then
    raise exception 'FALLO 7: residual % / %', v_residual.cantidad_solicitada, v_residual.observaciones;
  end if;
  v_ok := v_ok || '7 despachado, stock -5600 kg cemento / -1400 kg arena, residual 3 tn: "' || v_residual.observaciones || '"';

  raise exception 'DRYRUN 49 OK (nada persistido) -> %', v_ok;
end;
$dry$;
