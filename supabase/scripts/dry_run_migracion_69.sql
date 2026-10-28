-- ============================================================================
-- Dry-run de la migración 69. Pegar DESPUÉS del contenido completo de
-- supabase/migrations/69_imprimir_vale_ingreso_aridos.sql, en la misma
-- ejecución (la reversión se prueba acá adentro). Termina SIEMPRE con ERROR
-- "DRYRUN 69 OK — …" (todo revertido).
-- Prueba con la sesión de balanza@ (balancero) sobre el vale I-00856.
-- ============================================================================
do $dry$
declare
  v_vale   uuid := (select id from plantas_vales where tipo_vale = 'ingreso_arido' and numero_vale_arido = 856);
  v_uid    uuid := (select id from auth.users where email = 'balanza@vialtec.com.ar');
  v_res    jsonb;
  v_err    boolean;
  v_ok     text[] := '{}';
  v_aud    plantas_auditoria;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'email', 'balanza@vialtec.com.ar', 'role', 'authenticated')::text, true);
  set local role authenticated;

  -- A. Vale de ingreso en modo vale → se registra
  v_res := registrar_impresion(v_vale, 'vale', 'bascula', 'impresora');
  if v_res ->> 'tipo_vale' <> 'ingreso_arido' or (v_res ->> 'vez')::int < 1 then
    raise exception 'A: respuesta inesperada %', v_res;
  end if;
  reset role;
  select * into v_aud from plantas_auditoria where entidad = 'impresion' order by id desc limit 1;
  if v_aud.usuario_email <> 'balanza@vialtec.com.ar' or v_aud.tipo_accion <> 'IMPRIMIR' then
    raise exception 'A: fila de auditoría inesperada (% / %)', v_aud.usuario_email, v_aud.tipo_accion;
  end if;
  v_ok := v_ok || ('A vale I-00856 → IMPRIMIR ' || v_aud.entidad_label)::text;

  -- B. Remito sobre un ingreso → sigue rechazado
  set local role authenticated;
  v_err := false;
  begin
    perform registrar_impresion(v_vale, 'remito', 'bascula', 'impresora');
  exception when others then v_err := sqlerrm like 'El remito solo se imprime%';
  end;
  reset role;
  if not v_err then raise exception 'B: aceptó un remito de un ingreso'; end if;
  v_ok := v_ok || 'B remito de ingreso rechazado'::text;

  -- C. anon no puede llamarla
  if has_function_privilege('anon', 'registrar_impresion(uuid,text,text,text)', 'execute') then
    raise exception 'C: anon tiene EXECUTE';
  end if;
  v_ok := v_ok || 'C sin EXECUTE para anon'::text;

  -- D. La reversión deja el cuerpo original
  execute replace(pg_get_functiondef('public.registrar_impresion(uuid, text, text, text)'::regprocedure),
    $v$if v_vale.tipo_vale not in ('asfalto', 'egreso_arido', 'ingreso_arido') then$v$,
    $v$if v_vale.tipo_vale not in ('asfalto', 'egreso_arido') then$v$);
  if md5(pg_get_functiondef('public.registrar_impresion(uuid, text, text, text)'::regprocedure)) <> 'd0a41bd80b470b0ddab76e5bf92564da' then
    raise exception 'D: la reversión no deja el md5 original';
  end if;
  v_ok := v_ok || 'D reversión vuelve al md5 original'::text;

  raise exception 'DRYRUN 69 OK — %', array_to_string(v_ok, ' || ');
end;
$dry$;
