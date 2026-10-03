-- ============================================================================
-- Dry-run de la migración 51 (funciones de escritura sin anon) contra
-- producción. Termina SIEMPRE con raise exception: no persiste nada.
-- ============================================================================
do $dry$
declare
  v_admin text; v_estado text; v_n int; v_ok text := '';
begin
  select email into v_admin from plantas_usuarios_roles where rol = 'admin' and activo limit 1;

  execute $mig51$
-- ============================================================================
-- Migración 51: funciones de escritura de plantas sin EXECUTE para `anon`
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Etapa 1 del módulo de Auditoría (plan aprobado por Federico, 2026-10-03;
-- spec de auditoría de flota §6.2 punto 14). Estas 13 funciones escriben
-- datos y se podían ejecutar con la clave pública sin iniciar sesión. Ya
-- validaban el rol por dentro (plantas_rol_actual() da null sin sesión), así
-- que el riesgo era bajo, pero no hay razón para exponerlas.
--
-- Verificado antes de escribirla (proacl en producción): `authenticated`
-- tiene su propio grant en las 13 (no lo hereda de PUBLIC), así que la app no
-- se ve afectada. Ninguna tiene sobrecargas.
--
-- Fuera de alcance a propósito:
--   - plantas_rol_actual, plantas_tiene_permiso, plantas_puede_ver_*: las
--     usan las policies de RLS; sin EXECUTE, una consulta como anon daría
--     error en vez de 0 filas.
--   - rls_auto_enable(): función de event trigger de todo el proyecto
--     (también afecta a flota), no es de plantas.
--   - No se cambian los default privileges del schema public (compartido con
--     flota): cada función nueva de plantas debe revocar anon explícitamente
--     (memory/pending.md §7, lección de la migración 43).
--
-- Reversible: grant execute on function ... to anon;
-- ============================================================================

revoke execute on function public.crear_pedido(uuid, numeric, date, bigint, text, text, text, text, text, text) from public, anon;
revoke execute on function public.actualizar_pedido(uuid, uuid, numeric, date, bigint, text, text, text, text, text) from public, anon;
revoke execute on function public.confirmar_pedido(uuid, text, text) from public, anon;
revoke execute on function public.cancelar_pedido(uuid, text, text) from public, anon;
revoke execute on function public.postergar_pedido(uuid, date, text) from public, anon;
revoke execute on function public.archivar_pedido(uuid) from public, anon;
revoke execute on function public.corregir_despacho(uuid, numeric, text, text, text) from public, anon;
revoke execute on function public.registrar_carga_asfalto(uuid, text, numeric, text, timestamp with time zone, text) from public, anon;
revoke execute on function public.registrar_pesada_bascula(text, numeric, numeric, uuid, bigint, text, text, text, text, timestamp with time zone, text, text, text, numeric, numeric) from public, anon;
revoke execute on function public.registrar_movimiento_manual(uuid, text, numeric, text, text, text) from public, anon;
revoke execute on function public.registrar_relevamiento_stock(jsonb, text) from public, anon;
revoke execute on function public.generar_remito_manual(jsonb, text, text, text, date) from public, anon;
revoke execute on function public.admin_upsert_usuario_rol(text, text, boolean, boolean, integer[], boolean) from public, anon;

-- Control final: ninguna queda para anon y todas siguen para authenticated.
do $chk$
declare
  v_mal text;
begin
  select string_agg(p.proname, ', ') into v_mal
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('crear_pedido','actualizar_pedido','confirmar_pedido','cancelar_pedido',
                       'postergar_pedido','archivar_pedido','corregir_despacho','registrar_carga_asfalto',
                       'registrar_pesada_bascula','registrar_movimiento_manual','registrar_relevamiento_stock',
                       'generar_remito_manual','admin_upsert_usuario_rol')
     and (has_function_privilege('anon', p.oid, 'execute')
          or not has_function_privilege('authenticated', p.oid, 'execute'));
  if v_mal is not null then
    raise exception 'MIG51: permisos incorrectos en: %', v_mal;
  end if;
end;
$chk$;

$mig51$;
  v_ok := v_ok || '1 permisos OK (13 sin anon, con authenticated); ';

  -- 2) anon: la llamada se rechaza por permiso
  v_estado := 'sin error';
  begin
    execute 'set local role anon';
    perform archivar_pedido(gen_random_uuid());
  exception when others then v_estado := sqlstate;
  end;
  execute 'reset role';
  if v_estado <> '42501' then raise exception 'FALLA 2: anon dio % (esperado 42501)', v_estado; end if;
  v_ok := v_ok || '2 anon rechazado (42501); ';

  -- 3) admin logueado: la función se ejecuta (no hay error de permiso)
  perform set_config('request.jwt.claims', json_build_object('email', v_admin, 'role', 'authenticated')::text, true);
  v_estado := 'sin error';
  begin
    execute 'set local role authenticated';
    perform archivar_pedido(gen_random_uuid());
  exception when others then v_estado := sqlstate || ' ' || sqlerrm;
  end;
  execute 'reset role';
  if v_estado like '42501%' then raise exception 'FALLA 3: authenticated sin permiso (%)', v_estado; end if;
  v_ok := v_ok || '3 admin ejecuta (' || v_estado || '); ';

  -- 4) las policies de RLS siguen andando para anon (0 filas, sin error)
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);
  select count(*) into v_n from plantas_pedidos;
  execute 'reset role';
  v_ok := v_ok || '4 anon lee plantas_pedidos sin error (' || v_n || ' filas)';

  raise exception 'DRYRUN 51 OK — %', v_ok;
end;
$dry$;
