  -- ==========================================================================
  -- Pruebas (se arma en dry_run_migracion_66.sql junto con la migración)
  -- ==========================================================================
  execute $h$
create function dry66_como(p_email text) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object(
    'email', p_email, 'role', 'authenticated',
    'sub', (select id from auth.users where lower(email) = lower(p_email)))::text, true);
end;
$f$;
create function dry66_acum(p_numeros uuid[]) returns text language sql as $f$
  select string_agg(coalesce(trim_scale(v.acumulado_obra_tn)::text, 'null'), ' ' order by u.ord)
  from unnest(p_numeros) with ordinality u(id, ord) join plantas_vales v on v.id = u.id
$f$;
  $h$;

  select email into v_plantista from plantas_usuarios_roles where rol = 'plantista' and activo order by email limit 1;
  select email into v_balancero from plantas_usuarios_roles where rol = 'balancero' and activo order by email limit 1;
  select id into v_fa from plantas_formulas where activo and tipo = 'asfalto' order by nombre limit 1;
  select id into v_obra from flota_obras order by id limit 1;

  -- ===== GENERAL =====
  select count(*) into v_n from plantas_v_bascula_viva;
  if v_n <> v_filas_vista then raise exception 'DRY FALLA: la vista cambió de % a % filas', v_filas_vista, v_n; end if;
  if has_function_privilege('anon', 'plantas_recalcular_acumulados_asfalto(uuid,bigint,timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'plantas_recalcular_acumulados_asfalto(uuid,bigint,timestamptz)', 'execute')
     or not has_function_privilege('authenticated', 'corregir_vale_bascula(uuid,numeric,numeric,text,text,text,numeric,text,text,numeric,bigint,text,text)', 'execute')
     or not has_function_privilege('authenticated', 'anular_vale_bascula(uuid,text)', 'execute')
     or not has_function_privilege('authenticated', 'reasignar_vale_bascula(uuid,uuid,text)', 'execute')
     or not has_function_privilege('authenticated', 'registrar_pesada_bascula(text,numeric,numeric,uuid,bigint,text,text,text,text,timestamptz,text,text,text,numeric,numeric)', 'execute')
     or has_function_privilege('anon', 'corregir_vale_bascula(uuid,numeric,numeric,text,text,text,numeric,text,text,numeric,bigint,text,text)', 'execute') then
    raise exception 'DRY FALLA: permisos de las funciones';
  end if;
  if to_jsonb((select p from plantas_pedidos p where numero = 263)) is distinct from v_p263 then
    raise exception 'DRY FALLA: P-0263 cambió';
  end if;
  v_ok := 'GENERAL: vista ' || v_n || ' filas (igual); permisos ok (el recálculo es interno, sin EXECUTE para anon/authenticated); P-0263 sin cambios (sigue confirmado y con el pesaje abierto)';

  -- ===== DATOS: los 18 vales corregidos =====
  select string_agg(v.numero_vale || ' ' || trim_scale(a.guardado) || '→' || trim_scale(v.acumulado_obra_tn), ', ' order by v.fecha_pesada)
    into v_txt
    from plantas_vales v join dry66_antes a on a.id = v.id
    where v.acumulado_obra_tn is distinct from a.guardado;
  select count(*) into v_n from plantas_vales v join dry66_antes a on a.id = v.id where v.acumulado_obra_tn is distinct from a.guardado;
  if v_n <> 18 then raise exception 'DRY FALLA: cambiaron % vales (se esperaban 18): %', v_n, v_txt; end if;
  v_ok := v_ok || ' || DATOS: 18 vales corregidos: ' || v_txt;

  -- Lo que queda distinto del helper: solo los 10 de la regla vieja (no se tocan) y los anulados
  select string_agg(numero_vale::text, ' ' order by numero_vale) into v_txt
    from plantas_vales v
    where v.tipo_vale = 'asfalto' and not v.anulado and v.acumulado_obra_tn is not null
      and v.acumulado_obra_tn is distinct from (plantas_acumulado_asfalto(v.pedido_id, v.obra_id, v.fecha_pesada) ->> 'tn')::numeric;
  if v_txt is distinct from '10144 10145 10240 10241 10242 10243 10244 10245 10246 10247' then
    raise exception 'DRY FALLA: quedan distintos: %', v_txt;
  end if;
  select count(*) into v_n from plantas_vales v join dry66_antes a on a.id = v.id
    where v.anulado and v.acumulado_obra_tn is distinct from a.guardado;
  select count(*) into v_m from plantas_vales v join dry66_antes a on a.id = v.id
    where v.datos_legados is not null and v.acumulado_obra_tn is not null;
  if v_n <> 0 or v_m <> 0 then raise exception 'DRY FALLA: se tocaron anulados (%) o legado (%)', v_n, v_m; end if;
  v_ok := v_ok || ' | quedan con la regla vieja, sin tocar: ' || v_txt || '; anulados y legado sin cambios';

  -- Pedidos de prueba (confirmados)
  insert into plantas_pedidos (formula_id, tipo, cantidad_solicitada, fecha_programada, estado, obra_id)
    values (v_fa, 'asfalto', 100, '2026-10-20', 'confirmado', v_obra) returning id into v_p1;
  insert into plantas_pedidos (formula_id, tipo, cantidad_solicitada, fecha_programada, estado, obra_id)
    values (v_fa, 'asfalto', 100, '2026-10-20', 'confirmado', v_obra) returning id into v_p2;

  -- ===== 1. Pesadas normales: 30 + 25 + 20 =====
  perform dry66_como(v_balancero);
  v_a := (registrar_pesada_bascula('asfalto', 40, 10, v_p1, null, 'DRY001', 'Chofer', 'tn', null, '2026-10-20 10:00-03')).id;
  v_b := (registrar_pesada_bascula('asfalto', 35, 10, v_p1, null, 'DRY002', 'Chofer', 'tn', null, '2026-10-20 11:00-03')).id;
  v_c := (registrar_pesada_bascula('asfalto', 30, 10, v_p1, null, 'DRY003', 'Chofer', 'tn', null, '2026-10-20 12:00-03')).id;
  v_txt := dry66_acum(array[v_a, v_b, v_c]);
  if v_txt <> '30 55 75' then raise exception 'DRY FALLA: 1. pesadas %', v_txt; end if;
  v_ok := v_ok || ' || 1. pesadas 30+25+20: guardado ' || v_txt;

  -- ===== 2. Corregir la primera (30 → 25): ella y las siguientes =====
  select max(id) into v_aud from plantas_auditoria;
  v_v := corregir_vale_bascula(v_a, 35, 10, null, null, null, null, null, null, null, null, 'Prueba dry-run: mal tipeo');
  v_txt := dry66_acum(array[v_a, v_b, v_c]);
  if v_txt <> '25 50 70' or v_v.acumulado_obra_tn <> 25 then raise exception 'DRY FALLA: 2. corregir %, devuelve %', v_txt, v_v.acumulado_obra_tn; end if;
  select valores_antes ->> 'acumulado_obra_tn' || '→' || (valores_despues ->> 'acumulado_obra_tn') || ' / neto ' || (valores_antes ->> 'peso_neto') || '→' || (valores_despues ->> 'peso_neto')
    into v_txt2 from plantas_auditoria where id > v_aud and tipo_accion = 'CORREGIR' and entidad_ref = v_v.numero_vale::text;
  if v_txt2 is distinct from '30→25 / neto 30→25' then raise exception 'DRY FALLA: 2. auditoría de la corrección: %', v_txt2; end if;
  select count(*) into v_n from plantas_auditoria where id > v_aud;
  if v_n <> 1 then raise exception 'DRY FALLA: 2. filas de auditoría = % (se esperaba 1, los siguientes no se auditan aparte)', v_n; end if;
  v_ok := v_ok || ' || 2. corregir el 1° (30→25 tn): guardado ' || v_txt || '; auditoría CORREGIR: acumulado ' || v_txt2 || ' (1 sola fila)';

  -- Corregir sin cambiar el peso (solo chofer): no cambia ningún acumulado
  perform corregir_vale_bascula(v_b, 35, 10, null, 'Otro chofer', null, null, null, null, null, null, 'Prueba dry-run: chofer');
  v_txt := dry66_acum(array[v_a, v_b, v_c]);
  if v_txt <> '25 50 70' then raise exception 'DRY FALLA: 2b. corregir chofer %', v_txt; end if;
  v_ok := v_ok || ' | corregir solo el chofer: sin cambios (' || v_txt || ')';

  -- ===== 3. Anular el segundo: el tercero deja de sumarlo, el anulado conserva su foto =====
  perform dry66_como(v_plantista);
  perform anular_vale_bascula(v_b, 'Prueba dry-run: pesada repetida');
  v_txt := dry66_acum(array[v_a, v_b, v_c]);
  if v_txt <> '25 50 45' then raise exception 'DRY FALLA: 3. anular %', v_txt; end if;
  v_ok := v_ok || ' || 3. anular el 2°: guardado ' || v_txt || ' (el anulado conserva 50)';

  -- ===== 4. Reasignar el tercero al pedido 2 (que ya tenía 10 tn antes) =====
  perform dry66_como(v_balancero);
  v_d := (registrar_pesada_bascula('asfalto', 20, 10, v_p2, null, 'DRY004', 'Chofer', 'tn', null, '2026-10-20 09:00-03')).id;
  v_e := (registrar_pesada_bascula('asfalto', 25, 10, v_p2, null, 'DRY005', 'Chofer', 'tn', null, '2026-10-20 13:00-03')).id;
  if dry66_acum(array[v_d, v_e]) <> '10 25' then raise exception 'DRY FALLA: 4. pedido 2 antes %', dry66_acum(array[v_d, v_e]); end if;
  v_v := reasignar_vale_bascula(v_c, v_p2, 'Prueba dry-run: pedido equivocado');
  v_txt := dry66_acum(array[v_a, v_c]);
  v_txt2 := dry66_acum(array[v_d, v_c, v_e]);
  if v_txt <> '25 30' or v_txt2 <> '10 30 45' or v_v.acumulado_obra_tn <> 30 then
    raise exception 'DRY FALLA: 4. reasignar: origen %, destino %', v_txt, v_txt2;
  end if;
  v_ok := v_ok || ' || 4. reasignar el 3° (20 tn) al pedido 2: origen queda 25; destino 10 → 30 (el reasignado) → 45 (el siguiente)';

  -- ===== 5. Pesada con fecha anterior a las otras del pedido 1 =====
  v_f := (registrar_pesada_bascula('asfalto', 18, 10, v_p1, null, 'DRY006', 'Chofer', 'tn', null, '2026-10-20 08:00-03')).id;
  v_txt := dry66_acum(array[v_f, v_a]);
  if v_txt <> '8 33' then raise exception 'DRY FALLA: 5. pesada anterior %', v_txt; end if;
  v_ok := v_ok || ' || 5. pesada de las 08:00 cargada después (8 tn): guardado ' || v_txt || ' (el de las 10:00 pasa de 25 a 33)';

  -- ===== 6. Sin pedido: por obra y día de Argentina =====
  v_g := (registrar_pesada_bascula('asfalto', 30, 10, null, v_obra, 'DRY007', 'Chofer', 'tn', null, '2026-10-24 22:00-03')).id;
  v_h := (registrar_pesada_bascula('asfalto', 25, 10, null, v_obra, 'DRY008', 'Chofer', 'tn', null, '2026-10-24 23:00-03')).id;
  v_i := (registrar_pesada_bascula('asfalto', 22, 10, null, v_obra, 'DRY009', 'Chofer', 'tn', null, '2026-10-25 00:30-03')).id;
  v_v := corregir_vale_bascula(v_g, 26, 10, null, null, null, null, null, null, null, null, 'Prueba dry-run: sin pedido');
  v_txt := dry66_acum(array[v_g, v_h, v_i]);
  if v_txt <> '16 31 12' then raise exception 'DRY FALLA: 6. sin pedido %', v_txt; end if;
  v_ok := v_ok || ' || 6. sin pedido, misma obra: corregir el de las 22:00 (20→16): ' || v_txt || ' (el de las 00:30 es otro día: no cambia)';

  -- ===== 7. La vista y la impresión coinciden con lo guardado =====
  select count(*) into v_n from plantas_v_bascula_viva b join plantas_vales v on v.id = b.id
    where b.pedido_id in (v_p1, v_p2) and not v.anulado and b.acumulado_dia_tn is distinct from v.acumulado_obra_tn;
  v_j := registrar_impresion(v_e, 'remito', 'bascula');
  if v_n <> 0 or (v_j ->> 'acumulado_tn')::numeric <> 45 then
    raise exception 'DRY FALLA: 7. vista distinta en % vales, impresión %', v_n, v_j ->> 'acumulado_tn';
  end if;
  v_ok := v_ok || ' || 7. vista = guardado en los pedidos de prueba; remito del pedido 2: 45 tn';
