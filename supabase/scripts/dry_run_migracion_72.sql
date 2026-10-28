-- ============================================================================
-- Dry-run de la migración 72 (extendida a las 25 tablas y vistas plantas_*).
-- Pegar DESPUÉS del contenido de
-- supabase/migrations/72_sin_permisos_anon_formulas_usuarios_roles.sql, en la
-- misma ejecución. Termina SIEMPRE con ERROR "DRYRUN 72 OK — …" (revertido).
-- ============================================================================
do $dry$
declare
  v_felix uuid := (select id from auth.users where email = 'felix.pereyra@vialtec.com.ar');
  v_ok    text[] := '{}';
  v_tabla text;
  v_n     int := 0;
  v_cnt   int;
begin
  -- A. anon sin ningún permiso de tabla en plantas_*
  if exists (select 1 from information_schema.role_table_grants
              where grantee = 'anon' and table_schema = 'public' and table_name like 'plantas\_%') then
    raise exception 'A: anon conserva permisos en %', (select string_agg(distinct table_name, ', ')
      from information_schema.role_table_grants where grantee = 'anon' and table_schema = 'public' and table_name like 'plantas\_%');
  end if;
  v_ok := v_ok || 'A anon sin permisos en plantas_*'::text;

  -- B. anon rechazado al leer cada una
  set local role anon;
  for v_tabla in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'public' and c.relname like 'plantas\_%' and c.relkind in ('r', 'v') order by 1
  loop
    begin
      execute format('select 1 from public.%I limit 1', v_tabla);
      reset role;
      raise exception 'B: anon todavía lee %', v_tabla;
    exception when insufficient_privilege then v_n := v_n + 1;
    end;
  end loop;
  reset role;
  v_ok := v_ok || ('B anon rechazado en ' || v_n || ' tablas y vistas')::text;

  -- C. Felix (plantista) sigue leyendo lo de todos los días
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_felix, 'email', 'felix.pereyra@vialtec.com.ar', 'role', 'authenticated')::text, true);
  set local role authenticated;
  foreach v_tabla in array array['plantas_pedidos', 'plantas_formulas', 'plantas_vales', 'plantas_stock',
                                 'plantas_materiales', 'plantas_v_bascula_viva', 'plantas_v_obras_visibles']
  loop
    execute format('select count(*) from public.%I', v_tabla) into v_cnt;
    if v_cnt = 0 then reset role; raise exception 'C: Felix no ve filas en %', v_tabla; end if;
  end loop;
  if plantas_rol_actual() is distinct from 'plantista' then reset role; raise exception 'C: no resuelve el rol de Felix'; end if;
  reset role;
  v_ok := v_ok || 'C Felix lee pedidos, fórmulas, vales, stock, materiales y vistas'::text;

  raise exception 'DRYRUN 72 OK — %', array_to_string(v_ok, ' || ');
end;
$dry$;
