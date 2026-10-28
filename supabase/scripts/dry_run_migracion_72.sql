-- ============================================================================
-- Dry-run de la migración 72. Pegar DESPUÉS del contenido de
-- supabase/migrations/72_sin_permisos_anon_formulas_usuarios_roles.sql, en la
-- misma ejecución. Termina SIEMPRE con ERROR "DRYRUN 72 OK — …" (revertido).
-- ============================================================================
do $dry$
declare
  v_felix uuid := (select id from auth.users where email = 'felix.pereyra@vialtec.com.ar');
  v_ok    text[] := '{}';
  v_err   boolean;
  v_n     int;
begin
  -- A. anon sin ningún permiso en las dos tablas
  if exists (select 1 from information_schema.role_table_grants
              where grantee = 'anon' and table_name in ('plantas_formulas', 'plantas_usuarios_roles')) then
    raise exception 'A: anon conserva permisos';
  end if;
  v_ok := v_ok || 'A anon sin permisos'::text;

  -- B. anon que intenta leer → permission denied
  set local role anon;
  v_err := false;
  begin
    perform 1 from plantas_formulas limit 1;
  exception when insufficient_privilege then v_err := true;
  end;
  if not v_err then raise exception 'B: anon todavía lee plantas_formulas'; end if;
  v_err := false;
  begin
    perform 1 from plantas_usuarios_roles limit 1;
  exception when insufficient_privilege then v_err := true;
  end;
  reset role;
  if not v_err then raise exception 'B: anon todavía lee plantas_usuarios_roles'; end if;
  v_ok := v_ok || 'B anon rechazado en las dos'::text;

  -- C. Un usuario con sesión (Felix, plantista) sigue leyendo fórmulas y su rol
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_felix, 'email', 'felix.pereyra@vialtec.com.ar', 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from plantas_formulas;
  if v_n = 0 then reset role; raise exception 'C: authenticated no ve fórmulas'; end if;
  if plantas_rol_actual() is distinct from 'plantista' then reset role; raise exception 'C: no resuelve el rol de Felix'; end if;
  reset role;
  v_ok := v_ok || ('C Felix ve ' || v_n || ' fórmulas y su rol plantista')::text;

  raise exception 'DRYRUN 72 OK — %', array_to_string(v_ok, ' || ');
end;
$dry$;
