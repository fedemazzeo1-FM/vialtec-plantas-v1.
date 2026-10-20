  -- ==========================================================================
  -- Pruebas (se arma en dry_run_migracion_65.sql junto con la migración)
  -- ==========================================================================
  execute $h$
create function dry65_como(p_email text) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object(
    'email', p_email, 'role', 'authenticated',
    'sub', (select id from auth.users where lower(email) = lower(p_email)))::text, true);
end;
$f$;
create function dry65_falla(p_sql text, p_esperado text) returns text language plpgsql as $f$
begin
  execute p_sql;
  raise exception 'DRY FALLA: se esperaba error "%" y no hubo: %', p_esperado, p_sql;
exception when others then
  if sqlerrm like 'DRY FALLA%' then raise; end if;
  if position(p_esperado in sqlerrm) = 0 then
    raise exception 'DRY FALLA: error distinto al esperado (%): %', p_esperado, sqlerrm;
  end if;
  return sqlerrm;
end;
$f$;
  $h$;

  select email into v_admin from plantas_usuarios_roles where rol = 'admin' and activo order by email limit 1;
  select email into v_plantista from plantas_usuarios_roles where rol = 'plantista' and activo order by email limit 1;
  select email into v_balancero from plantas_usuarios_roles where rol = 'balancero' and activo order by email limit 1;
  select id into v_fa from plantas_formulas where activo and tipo = 'asfalto' order by nombre limit 1;
  select id into v_obra from flota_obras order by id limit 1;

  -- ===== GENERAL =====
  select count(*) into v_n from plantas_v_bascula_viva;
  if v_n <> v_filas_vista then raise exception 'DRY FALLA: la vista cambió de % a % filas', v_filas_vista, v_n; end if;
  if has_function_privilege('anon', 'cerrar_pesaje_pedido(uuid)', 'execute')
     or has_function_privilege('anon', 'reabrir_pesaje_pedido(uuid,text)', 'execute')
     or has_function_privilege('anon', 'registrar_impresion(uuid,text,text,text)', 'execute')
     or has_function_privilege('anon', 'impresiones_del_vale(uuid)', 'execute')
     or has_function_privilege('anon', 'plantas_acumulado_asfalto(uuid,bigint,timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'plantas_acumulado_asfalto(uuid,bigint,timestamptz)', 'execute')
     or not has_function_privilege('authenticated', 'cerrar_pesaje_pedido(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'registrar_impresion(uuid,text,text,text)', 'execute')
     or not has_function_privilege('authenticated', 'registrar_pesada_bascula(text,numeric,numeric,uuid,bigint,text,text,text,text,timestamptz,text,text,text,numeric,numeric)', 'execute')
     or has_function_privilege('anon', 'registrar_pesada_bascula(text,numeric,numeric,uuid,bigint,text,text,text,text,timestamptz,text,text,text,numeric,numeric)', 'execute')
     or not has_function_privilege('authenticated', 'reasignar_vale_bascula(uuid,uuid,text)', 'execute')
     or has_function_privilege('anon', 'reasignar_vale_bascula(uuid,uuid,text)', 'execute') then
    raise exception 'DRY FALLA: permisos de las funciones';
  end if;
  select array_to_string(reloptions, ',') into v_txt from pg_class where relname = 'plantas_v_bascula_viva';
  if v_txt is distinct from 'security_invoker=true' then raise exception 'DRY FALLA: la vista perdió security_invoker (%)', v_txt; end if;
  v_ok := 'GENERAL: vista ' || v_n || ' filas (igual), security_invoker ok, permisos ok (anon sin EXECUTE en lo nuevo, helper interno)';

  -- ===== a. P-0230 y P-0233 (datos reales, solo lectura) =====
  select string_agg(numero_vale || '=' || trim_scale(acumulado_dia_tn), ' ' order by fecha_pesada) into v_txt
    from plantas_v_bascula_viva b where b.pedido_id = (select id from plantas_pedidos where numero = 230);
  if v_txt <> '10220=27.38 10221=63.32 10222=90.86 10223=124.86 10224=159.78 10225=196.56 10226=228.76 10227=261.44' then
    raise exception 'DRY FALLA: P-0230 en la vista: %', v_txt;
  end if;
  v_ok := v_ok || ' || a. P-0230 vista: ' || v_txt;
  select string_agg(numero_vale || '=' || trim_scale(acumulado_dia_tn), ' ' order by fecha_pesada) into v_txt
    from plantas_v_bascula_viva b where b.pedido_id = (select id from plantas_pedidos where numero = 233) and b.numero_vale in (10239, 10240, 10241, 10247);
  if v_txt <> '10239=238.26 10240=274.84 10241=302.56 10247=489.34' then
    raise exception 'DRY FALLA: P-0233 en la vista: %', v_txt;
  end if;
  v_ok := v_ok || ' | P-0233 vista (antes 23:54 y 00:04 reiniciaban): ' || v_txt;

  perform dry65_como(v_balancero);
  select id into v_vale from plantas_vales where numero_vale = 10227;
  v_j := registrar_impresion(v_vale, 'remito', 'bascula');
  if (v_j ->> 'acumulado_tn')::numeric <> 261.44 or v_j -> 'vales' <> '[10220,10221,10222,10223,10224,10225,10226,10227]'::jsonb
     or v_j ->> 'remito' <> '47' or (v_j ->> 'vez')::int <> 1 or v_j ? 'anterior' then
    raise exception 'DRY FALLA: remito de P-0230: %', v_j;
  end if;
  select entidad_label || ' / ' || usuario_email || ' / ' || tipo_accion into v_txt from plantas_auditoria order by id desc limit 1;
  v_ok := v_ok || ' | remito P-0230 desde vale 10227: 261,44 tn, 8 vales, N° 47 [' || v_txt || ']';
  select id into v_vale from plantas_vales where numero_vale = 10247;
  v_j := registrar_impresion(v_vale, 'vale', 'despachos');
  if (v_j ->> 'acumulado_tn')::numeric <> 489.34 or jsonb_array_length(v_j -> 'vales') <> 15 then
    raise exception 'DRY FALLA: vale 10247 de P-0233: %', v_j;
  end if;
  v_ok := v_ok || ' | vale 10247 (P-0233, desde Despachos): 489,34 tn, 15 vales';

  -- ===== b. P-0212 (abierto de un día para otro) =====
  select id into v_vale from plantas_vales where numero_vale = 10145;
  v_j := registrar_impresion(v_vale, 'remito', 'bascula');
  v_ok := v_ok || ' || b. P-0212: el vale 10145 (25/09) imprime ' || trim_scale((v_j ->> 'acumulado_tn')::numeric) || ' tn con vales ' || (v_j -> 'vales')::text
    || ' (el error de pesaje ahora se ve; se corrige con reasignar, probado en el caso b2)';
  v_txt := dry65_falla(format('select registrar_pesada_bascula(%L, 40, 10, %L)', 'asfalto', (select id from plantas_pedidos where numero = 212)), 'no admite más pesadas');
  v_ok := v_ok || ' | pesar contra P-0212 (ya despachado) rechazado: "' || v_txt || '"';

  -- Pedidos de prueba (confirmados, hoy)
  insert into plantas_pedidos (formula_id, tipo, cantidad_solicitada, fecha_programada, estado, obra_id)
    values (v_fa, 'asfalto', 60, '2026-10-20', 'confirmado', v_obra) returning id into v_p1;
  insert into plantas_pedidos (formula_id, tipo, cantidad_solicitada, fecha_programada, estado, obra_id)
    values (v_fa, 'asfalto', 40, '2026-10-21', 'confirmado', v_obra) returning id into v_p2;

  -- ===== a2. Nocturno con pesadas nuevas: 20:50, 21:10 (antes cortaba el valor guardado), 00:10 =====
  perform dry65_como(v_balancero);
  perform registrar_pesada_bascula('asfalto', 40, 10, v_p1, null, 'DRY001', 'Chofer', 'tn', null, '2026-10-20 20:50-03');
  v_vale := (registrar_pesada_bascula('asfalto', 35, 10, v_p1, null, 'DRY001', 'Chofer', 'tn', null, '2026-10-20 21:10-03')).id;
  select acumulado_obra_tn into v_num from plantas_vales where id = v_vale;
  if v_num <> 55 then raise exception 'DRY FALLA: acumulado guardado 21:10 = %', v_num; end if;
  v_vale := (registrar_pesada_bascula('asfalto', 30, 10, v_p1, null, 'DRY001', 'Chofer', 'tn', null, '2026-10-21 00:10-03')).id;
  select acumulado_obra_tn into v_num from plantas_vales where id = v_vale;
  if v_num <> 75 then raise exception 'DRY FALLA: acumulado guardado 00:10 = %', v_num; end if;
  select acumulado_dia_tn into v_num from plantas_v_bascula_viva where id = v_vale;
  if v_num <> 75 then raise exception 'DRY FALLA: acumulado de la vista 00:10 = %', v_num; end if;
  v_j := registrar_impresion(v_vale, 'remito', 'bascula');
  if (v_j ->> 'acumulado_tn')::numeric <> 75 or jsonb_array_length(v_j -> 'vales') <> 3 or v_j ->> 'remito' is null then
    raise exception 'DRY FALLA: remito nocturno de prueba: %', v_j;
  end if;
  v_ok := v_ok || ' || a2. pedido de prueba 20:50/21:10/00:10 (30+25+20): guardado 55 y 75, vista 75, remito 75 tn con 3 vales y N° ' || (v_j ->> 'remito');

  -- ===== d. "No terminó" y siguen pesando =====
  v_vale2 := (registrar_pesada_bascula('asfalto', 30, 10, v_p1, null, 'DRY002', 'Chofer', 'tn', null, '2026-10-21 00:40-03')).id;
  v_j := registrar_impresion(v_vale2, 'remito', 'bascula');
  if (v_j ->> 'acumulado_tn')::numeric <> 95 or jsonb_array_length(v_j -> 'vales') <> 4 then
    raise exception 'DRY FALLA: d. remito después de seguir pesando: %', v_j;
  end if;
  v_ok := v_ok || ' || d. sigue abierto, otro camión 00:40: remito 95 tn con 4 vales';

  -- ===== f. Reimpresión =====
  v_j := registrar_impresion(v_vale2, 'remito', 'bascula');
  if (v_j ->> 'vez')::int <> 2 or v_j ? 'anterior' then raise exception 'DRY FALLA: f. reimpresión sin cambios: %', v_j; end if;
  v_ok := v_ok || ' || f. reimpresión sin cambios: vez 2, igual a la anterior (sin diferencia)';

  -- ===== g. Anular un vale ya impreso =====
  select jsonb_array_length(impresiones_del_vale(v_vale)) into v_n;
  if v_n < 3 then raise exception 'DRY FALLA: g. impresiones_del_vale = %', v_n; end if;
  perform dry65_como(v_plantista);  -- el balancero no anula (bascula:eliminar)
  perform anular_vale_bascula(v_vale, 'Prueba dry-run: pesada repetida');
  perform dry65_como(v_balancero);
  v_j := registrar_impresion(v_vale2, 'remito', 'bascula');
  if (v_j ->> 'vez')::int <> 3 or (v_j ->> 'acumulado_tn')::numeric <> 75 or (v_j -> 'anterior' ->> 'acumulado_tn')::numeric <> 95 then
    raise exception 'DRY FALLA: g. reimpresión después de anular: %', v_j;
  end if;
  v_ok := v_ok || ' || g. el vale de 00:10 figuraba en ' || v_n || ' impresiones (aviso al editar/anular); anulado → reimpresión vez 3: 75 tn, guarda la anterior (95 tn)';

  -- ===== e. Cierre del pesaje + camión que llega después =====
  v_txt := dry65_falla(format('select cerrar_pesaje_pedido(%L)', v_p2), 'no tiene pesadas');
  v_p := cerrar_pesaje_pedido(v_p1);
  if v_p.pesaje_cerrado_por <> v_balancero then raise exception 'DRY FALLA: e. cerrado por %', v_p.pesaje_cerrado_por; end if;
  select tipo_accion || ' ' || (valores_despues ->> 'pesado_tn') || ' tn / ' || (valores_despues ->> 'vales_pesados') || ' vales' into v_txt from plantas_auditoria order by id desc limit 1;
  if v_txt <> 'CAMBIAR_ESTADO 75 tn / 3 vales' then raise exception 'DRY FALLA: e. auditoría del cierre: %', v_txt; end if;
  v_ok := v_ok || ' || e. pedido sin pesadas no se cierra; cierre por balancero [' || v_txt || ']';
  v_txt := dry65_falla(format('select registrar_pesada_bascula(%L, 40, 10, %L)', 'asfalto', v_p1), 'tiene el pesaje cerrado');
  v_ok := v_ok || ' | pesar con pesaje cerrado: "' || v_txt || '"';
  v_txt := dry65_falla(format('select cerrar_pesaje_pedido(%L)', v_p1), 'ya tiene el pesaje cerrado');
  v_txt := dry65_falla(format('select reabrir_pesaje_pedido(%L, %L)', v_p1, 'otro camión'), 'no puede reabrir');
  v_ok := v_ok || ' | segundo cierre rechazado | balancero no reabre';
  perform dry65_como(v_plantista);
  v_txt := dry65_falla(format('select reabrir_pesaje_pedido(%L, %L)', v_p1, ' '), 'motivo');
  v_p := reabrir_pesaje_pedido(v_p1, 'Llegó un camión más para la obra');
  select tipo_accion || ' motivo="' || motivo || '"' into v_txt from plantas_auditoria order by id desc limit 1;
  v_ok := v_ok || ' | reabrir sin motivo rechazado; plantista reabre [' || v_txt || ']';
  perform dry65_como(v_balancero);
  v_vale3 := (registrar_pesada_bascula('asfalto', 25, 10, v_p1, null, 'DRY003', 'Chofer', 'tn', null, '2026-10-21 08:00-03')).id;
  select acumulado_obra_tn into v_num from plantas_vales where id = v_vale3;
  if v_num <> 90 then raise exception 'DRY FALLA: e. acumulado después de reabrir = %', v_num; end if;
  v_ok := v_ok || ' | pesada después de reabrir: acumulado 90 tn (sigue el del pedido, sin el anulado)';

  -- ===== b2. Corregir un vale pesado contra el pedido equivocado =====
  v_vale4 := (registrar_pesada_bascula('asfalto', 22, 10, v_p1, null, 'DRY004', 'Chofer', 'tn', null, '2026-10-21 09:00-03')).id;
  perform reasignar_vale_bascula(v_vale4, v_p2, 'Prueba dry-run: era del pedido del día');
  select acumulado_obra_tn into v_num from plantas_vales where id = v_vale4;
  v_j := registrar_impresion(v_vale4, 'remito', 'bascula');
  if (v_j ->> 'acumulado_tn')::numeric <> 12 or jsonb_array_length(v_j -> 'vales') <> 1 then
    raise exception 'DRY FALLA: b2. remito del vale reasignado: %', v_j;
  end if;
  v_ok := v_ok || ' || b2. vale reasignado al pedido correcto: su remito pasa a 12 tn con 1 vale (REASIGNAR con motivo en auditoría)';
  perform cerrar_pesaje_pedido(v_p2);
  v_txt := dry65_falla(format('select reasignar_vale_bascula(%L, %L, %L)', v_vale3, v_p2, 'x'), 'pesaje cerrado');
  v_ok := v_ok || ' | reasignar a un pedido con pesaje cerrado: rechazado';

  -- ===== i. Finalizar desde Pedidos sin pasar por la pregunta + c. residual =====
  perform dry65_como(v_plantista);
  perform registrar_carga_asfalto(v_p1, '1', 50, 'DRY001');
  v_p := finalizar_despacho(v_p1, true, '2026-10-22');
  if v_p.estado <> 'despachado' then raise exception 'DRY FALLA: i. estado %', v_p.estado; end if;
  perform dry65_como(v_balancero);
  v_txt := dry65_falla(format('select registrar_pesada_bascula(%L, 40, 10, %L)', 'asfalto', v_p1), 'no admite más pesadas');
  v_ok := v_ok || ' || i. finalizado en Pedidos con el pesaje abierto → pesar rechazado: "' || v_txt || '"';
  select * into v_p from plantas_pedidos where observaciones like 'Pedido residual%' and created_at = now() order by numero desc limit 1;
  if v_p.id is null or v_p.nro_remito_global is distinct from (select nro_remito_global from plantas_pedidos where id = v_p1) or v_p.pesaje_cerrado_en is not null then
    raise exception 'DRY FALLA: c. residual %', to_jsonb(v_p);
  end if;
  v_vale5 := (registrar_pesada_bascula('asfalto', 30, 10, v_p.id, null, 'DRY005', 'Chofer', 'tn', null, '2026-10-22 08:00-03')).id;
  v_j := registrar_impresion(v_vale5, 'remito', 'bascula');
  if (v_j ->> 'acumulado_tn')::numeric <> 20 or v_j ->> 'remito' <> (select nro_remito_global from plantas_pedidos where id = v_p1) then
    raise exception 'DRY FALLA: c. remito del residual: %', v_j;
  end if;
  v_ok := v_ok || ' || c. residual (otro día): mismo N° de remito ' || (v_j ->> 'remito') || ', pesaje abierto, acumula lo suyo (20 tn)';

  -- ===== h. Vale sin pedido (por obra y día de Argentina) =====
  perform registrar_pesada_bascula('asfalto', 30, 10, null, v_obra, 'DRY006', 'Chofer', 'tn', null, '2026-10-22 23:50-03');
  v_vale6 := (registrar_pesada_bascula('asfalto', 25, 10, null, v_obra, 'DRY006', 'Chofer', 'tn', null, '2026-10-22 23:55-03')).id;
  select acumulado_obra_tn into v_num from plantas_vales where id = v_vale6;
  if v_num <> 35 then raise exception 'DRY FALLA: h. mismo día = %', v_num; end if;
  v_vale6 := (registrar_pesada_bascula('asfalto', 22, 10, null, v_obra, 'DRY006', 'Chofer', 'tn', null, '2026-10-23 00:05-03')).id;
  select acumulado_obra_tn into v_num from plantas_vales where id = v_vale6;
  select acumulado_dia_tn into v_num2 from plantas_v_bascula_viva where id = v_vale6;
  v_j := registrar_impresion(v_vale6, 'vale', 'bascula');
  if v_num <> 12 or v_num2 <> 12 or (v_j ->> 'acumulado_tn')::numeric <> 12 then
    raise exception 'DRY FALLA: h. después de medianoche: guardado %, vista %, impresión %', v_num, v_num2, v_j ->> 'acumulado_tn';
  end if;
  v_ok := v_ok || ' || h. sin pedido, misma obra: 23:50+23:55 = 35 tn; 00:05 reinicia a 12 tn (guardado, vista e impresión iguales; no suma el residual de la misma obra)';

  -- ===== Otros =====
  v_txt := dry65_falla(format('select registrar_impresion(%L, %L, %L)', v_vale, 'vale', 'bascula'), 'anulado');
  perform dry65_como(v_plantista);
  v_txt := dry65_falla(format('select cerrar_pesaje_pedido(%L)', v_p1), 'despachado');
  select count(*) into v_n from plantas_auditoria where id > s5 and tipo_accion = 'IMPRIMIR';
  select count(*) into v_m from plantas_auditoria where id > s5;
  v_ok := v_ok || ' || otros: no imprime vales anulados; no se cierra un pedido despachado; ' || v_n || ' impresiones auditadas, ' || v_m || ' filas de auditoría en el ensayo';
