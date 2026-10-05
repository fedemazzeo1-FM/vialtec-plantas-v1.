-- ============================================================================
-- Dry-run de la migración 60 (motivo obligatorio en corregir_despacho y
-- corregir_vale_bascula) contra producción. Termina SIEMPRE con raise
-- exception: no persiste nada. Bloquea pedidos/vales/remitos manuales/
-- auditoría mientras corre y devuelve las secuencias a su valor (también si
-- falla a mitad de camino).
-- Corrido el 2026-10-05 (7 chequeos OK) antes de guardarlo acá; esta versión
-- solo agrega el bloque final que restaura las secuencias ante un error.
-- ============================================================================
do $dry$
declare
  v_admin text; v_fa uuid; v_obra bigint;
  v_p1 uuid; v_p2 uuid; v_p3 uuid; v_vale uuid;
  v_n int; v_m int; v_txt text; v_estado text; v_ok text := '';
  s1 bigint; c1 boolean; s3 bigint; c3 boolean; s4 bigint; c4 boolean; s5 bigint; c5 boolean;
begin
  lock table plantas_pedidos, plantas_vales, plantas_remitos_manuales, plantas_auditoria in share row exclusive mode;
  select last_value, is_called into s1, c1 from plantas_vales_numero_vale_seq;
  select last_value, is_called into s3, c3 from plantas_remitos_numero_seq;
  select last_value, is_called into s4, c4 from plantas_pedidos_numero_seq;
  select last_value, is_called into s5, c5 from plantas_auditoria_id_seq;
  select email into v_admin from plantas_usuarios_roles where rol = 'admin' and activo limit 1;
  select id into v_fa from plantas_formulas where activo and tipo = 'asfalto' order by nombre limit 1;
  select id into v_obra from flota_obras order by id limit 1;

  execute $m60$
create function plantas__auditoria_patch2(
  p_fn text, p_md5_antes text, p_md5_despues text, p_firma_vieja text, p_firma_nueva text, variadic p_pares text[]
)
returns void
language plpgsql
set search_path to 'public'
as $pf$
declare
  v_oid oid; v_src text; v_nuevo text; v_def text; v_n int;
begin
  select p.oid, p.prosrc into strict v_oid, v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = p_fn;
  if md5(v_src) <> p_md5_antes then
    raise exception 'PATCH %: la función en producción no es la versión esperada (md5 %)', p_fn, md5(v_src);
  end if;
  v_nuevo := v_src;
  for i in 1 .. array_length(p_pares, 1) / 2 loop
    v_n := (length(v_nuevo) - length(replace(v_nuevo, p_pares[2 * i - 1], ''))) / length(p_pares[2 * i - 1]);
    if v_n <> 1 then
      raise exception 'PATCH %: el ancla % aparece % veces (esperado 1)', p_fn, i, v_n;
    end if;
    v_nuevo := replace(v_nuevo, p_pares[2 * i - 1], p_pares[2 * i]);
  end loop;
  if md5(v_nuevo) <> p_md5_despues then
    raise exception 'PATCH %: el resultado no es el esperado (md5 %)', p_fn, md5(v_nuevo);
  end if;
  v_def := pg_get_functiondef(v_oid);
  if (length(v_def) - length(replace(v_def, v_src, ''))) / length(v_src) <> 1 then
    raise exception 'PATCH %: no se pudo ubicar el cuerpo dentro de la definición', p_fn;
  end if;
  v_def := replace(v_def, v_src, v_nuevo);
  if p_firma_vieja is not null then
    if (length(v_def) - length(replace(v_def, p_firma_vieja, ''))) / length(p_firma_vieja) <> 1 then
      raise exception 'PATCH %: no se pudo ubicar la firma', p_fn;
    end if;
    v_def := replace(v_def, p_firma_vieja, p_firma_nueva);
    execute 'drop function ' || v_oid::regprocedure;
  end if;
  execute v_def;
end;
$pf$;

select plantas__auditoria_patch2('corregir_despacho', '97902d48adcf29fb287572e652cd5465', '64c25609bdc164a1f8bc38806a0a3fa2', null, null,
  $a$  if p_cantidad_despachada is not null and not (p_cantidad_despachada > 0) then
$a$,
  $b$  if nullif(btrim(p_notas), '') is null then
    raise exception 'Indicá el motivo de la corrección.';
  end if;
  if p_cantidad_despachada is not null and not (p_cantidad_despachada > 0) then
$b$,
  $a$  perform plantas_auditar_pedido(case when nullif(btrim(p_notas), '') is null then 'EDITAR' else 'CORREGIR' end, 'despacho', p_pedido_id, p_notas, v_aud_antes);
$a$,
  $b$  if v_aud_antes is distinct from to_jsonb(v_pedido) then
    perform plantas_auditar_pedido('CORREGIR', 'despacho', p_pedido_id, btrim(p_notas), v_aud_antes);
  end if;
$b$
);

select plantas__auditoria_patch2('corregir_vale_bascula', '0ef930081a9f6ef24e1f16ddc6a97bb2', 'f1c5e2d4f2e5d7137fd06a7aa6fe7657',
  $a$p_obra_id bigint DEFAULT NULL::bigint)$a$,
  $b$p_obra_id bigint DEFAULT NULL::bigint, p_motivo text DEFAULT NULL::text)$b$,
  $a$  if not (p_peso_bruto > 0) then
$a$,
  $b$  if nullif(btrim(p_motivo), '') is null then
    raise exception 'Indicá el motivo de la corrección del vale.';
  end if;

  if not (p_peso_bruto > 0) then
$b$,
  $a$antes, despues, usuario_email)
$a$,
  $b$antes, despues, usuario_email, motivo)
$b$,
  $a$else '{}'::jsonb end,
    auth.email()
  );$a$,
  $b$else '{}'::jsonb end,
    auth.email(), btrim(p_motivo)
  );$b$,
  $a$  perform plantas_auditar_vale('EDITAR', p_vale_id, null, v_aud_antes);
$a$,
  $b$  if v_aud_antes is distinct from plantas_auditoria_snapshot_vale(p_vale_id) then
    perform plantas_auditar_vale('CORREGIR', p_vale_id, btrim(p_motivo), v_aud_antes);
  end if;
$b$
);

drop function plantas__auditoria_patch2(text, text, text, text, text, text[]);

revoke execute on function corregir_vale_bascula(uuid, numeric, numeric, text, text, text, numeric, text, text, numeric, bigint, text) from public, anon;
grant execute on function corregir_vale_bascula(uuid, numeric, numeric, text, text, text, numeric, text, text, numeric, bigint, text) to authenticated, service_role;

do $chk$
declare
  v_mal text;
begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'corregir_vale_bascula') <> 1 then
    raise exception 'MIG60: corregir_vale_bascula quedó duplicada';
  end if;
  select string_agg(p.proname, ', ') into v_mal
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('corregir_despacho', 'corregir_vale_bascula')
     and (has_function_privilege('anon', p.oid, 'execute')
          or not has_function_privilege('authenticated', p.oid, 'execute')
          or not p.prosecdef);
  if v_mal is not null then
    raise exception 'MIG60: permisos alterados en: %', v_mal;
  end if;
end;
$chk$;
$m60$;

  perform set_config('request.jwt.claims', json_build_object('email', v_admin, 'sub', (select id from auth.users where lower(email) = lower(v_admin)), 'role', 'authenticated')::text, true);
  select id into v_p1 from crear_pedido(v_fa, 10, current_date, v_obra);
  perform confirmar_pedido(v_p1, null, null);
  perform registrar_carga_asfalto(v_p1, '99998', 6, 'AAA111', now(), null);
  perform finalizar_despacho(v_p1, false, null);
  select id into v_p2 from crear_pedido(v_fa, 30, current_date, v_obra);
  perform confirmar_pedido(v_p2, null, null);
  select id into v_p3 from crear_pedido(v_fa, 30, current_date, v_obra);
  perform confirmar_pedido(v_p3, null, null);
  select id into v_vale from registrar_pesada_bascula('asfalto', 40, 15, v_p2, null, 'AAA111', 'Chofer', 'tn', null, now(), null, null, null, null, 150);

  -- 1) despacho sin motivo
  v_estado := 'sin error';
  begin perform corregir_despacho(v_p1, 7, null, null, null); exception when others then v_estado := sqlerrm; end;
  if v_estado <> 'Indicá el motivo de la corrección.' then raise exception 'FALLA 1: %', v_estado; end if;
  v_ok := v_ok || '1 despacho sin motivo rechazado ("' || v_estado || '"); ';

  -- 2) despacho con motivo
  perform corregir_despacho(v_p1, 7, null, null, 'error de tipeo');
  select tipo_accion || ' ' || entidad || ' / motivo: ' || motivo || ' / ' || valores_antes::text || ' -> ' || valores_despues::text into v_txt from plantas_auditoria order by id desc limit 1;
  if v_txt not like 'CORREGIR despacho / motivo: error de tipeo%' then raise exception 'FALLA 2: %', v_txt; end if;
  v_ok := v_ok || '2 despacho con motivo: ' || v_txt || '; ';

  -- 3) despacho sin cambios
  select count(*) into v_n from plantas_auditoria;
  perform corregir_despacho(v_p1, 7, null, null, 'sin cambios');
  select count(*) into v_m from plantas_auditoria;
  if v_m <> v_n then raise exception 'FALLA 3'; end if;
  v_ok := v_ok || '3 despacho sin cambios no registra; ';

  -- 4) vale sin motivo: la llamada de 11 parámetros de la pantalla vieja
  v_estado := 'sin error';
  begin perform corregir_vale_bascula(v_vale, 41, 15, null, null, null, 150, null, null, null, null); exception when others then v_estado := sqlerrm; end;
  if v_estado <> 'Indicá el motivo de la corrección del vale.' then raise exception 'FALLA 4: %', v_estado; end if;
  v_ok := v_ok || '4 vale sin motivo (llamada de la pantalla vieja) rechazado ("' || v_estado || '"); ';

  -- 5) vale con motivo
  perform corregir_vale_bascula(v_vale, 41, 15, null, null, null, 150, null, null, null, null, 'error de tara');
  select tipo_accion || ' ' || entidad || ' / motivo: ' || motivo || ' / ' || valores_antes::text || ' -> ' || valores_despues::text into v_txt from plantas_auditoria order by id desc limit 1;
  if v_txt not like 'CORREGIR vale / motivo: error de tara%' then raise exception 'FALLA 5: %', v_txt; end if;
  select motivo into v_estado from plantas_vales_historial where vale_id = v_vale and accion = 'edicion' order by created_at desc limit 1;
  if v_estado is distinct from 'error de tara' then raise exception 'FALLA 5b: historial motivo %', v_estado; end if;
  v_ok := v_ok || '5 vale con motivo: ' || v_txt || ' (motivo tambien en el historial del vale); ';

  -- 6) cambiar solo el pedido (la pantalla llama a reasignar y después a corregir)
  select count(*) into v_n from plantas_auditoria;
  perform reasignar_vale_bascula(v_vale, v_p3, 'mal pedido');
  perform corregir_vale_bascula(v_vale, 41, 15, null, null, null, 150, null, null, null, null, 'mal pedido');
  select count(*) into v_m from plantas_auditoria;
  select tipo_accion into v_txt from plantas_auditoria order by id desc limit 1;
  if v_m <> v_n + 1 or v_txt <> 'REASIGNAR' then raise exception 'FALLA 6: % filas nuevas, ultima %', v_m - v_n, v_txt; end if;
  v_ok := v_ok || '6 cambiar solo el pedido deja una sola fila (REASIGNAR); ';

  -- 7) permisos
  select count(*) into v_n from pg_proc p where p.proname = 'corregir_vale_bascula'
     and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute');
  if v_n <> 1 then raise exception 'FALLA 7: permisos'; end if;
  v_ok := v_ok || '7 una sola corregir_vale_bascula, con authenticated y sin anon';

  raise exception 'DRYRUN 60 OK — %', v_ok;
exception when others then
  perform setval('plantas_vales_numero_vale_seq', s1, c1);
  perform setval('plantas_remitos_numero_seq', s3, c3);
  perform setval('plantas_pedidos_numero_seq', s4, c4);
  perform setval('plantas_auditoria_id_seq', s5, c5);
  raise;
end;
$dry$;
