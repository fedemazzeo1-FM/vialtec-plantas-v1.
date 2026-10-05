-- ============================================================================
-- Migración 59: módulo de Auditoría, etapa 3 — las funciones de usuarios
-- registran en plantas_auditoria
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Funciones: admin_upsert_usuario_rol.
--
-- Cómo está hecha: NO se reescribe el cuerpo a mano. plantas__auditoria_patch
-- (creada en la 54, borrada en la 59) toma la definición REAL de producción (pg_get_functiondef), verifica por
-- md5 que sea la versión esperada, inserta las llamadas de auditoría en
-- anclas que deben aparecer exactamente una vez, verifica el md5 del
-- resultado y recién ahí la recrea (CREATE OR REPLACE conserva los permisos).
-- Si producción cambió desde el relevamiento, la migración falla sin tocar
-- nada. El cuerpo completo resultante queda en
-- supabase/scripts/referencia_funciones_auditadas.sql (mismo md5).
--
-- La auditoría corre en la misma transacción: si no se puede registrar, la
-- operación falla. Requiere las migraciones 53 y 54.
--
-- Reversión: volver a crear cada función con su cuerpo anterior (última
-- migración que la define; md5 anterior en cada llamada de abajo).
-- ============================================================================

select plantas__auditoria_patch('admin_upsert_usuario_rol', 'bf5f8e3b8672f9a98920498bdbeb0f46', '98b8b67129aacc86c57b3fe87a7d9bdf',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  insert into plantas_usuarios_roles (email, rol, ver_todas_obras, ver_ventas, obra_ids, activo)
$a$,
  $b$  select to_jsonb(u) into v_aud_antes from plantas_usuarios_roles u where u.email = lower(trim(p_email));

  insert into plantas_usuarios_roles (email, rol, ver_todas_obras, ver_ventas, obra_ids, activo)
$b$,
  $a$
  return v_resultado;
end;$a$,
  $b$
  perform plantas_auditar(case when v_aud_antes is null then 'CREAR' else 'EDITAR' end, 'usuarios', 'usuario_rol',
    v_resultado.email, v_resultado.email || ' — ' || v_resultado.rol, null, v_aud_antes, to_jsonb(v_resultado));

  return v_resultado;
end;$b$
);

drop function plantas__auditoria_patch(text, text, text, text[]);

do $chk$
declare
  v_mal text;
begin
  select string_agg(p.proname, ', ') into v_mal
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('admin_upsert_usuario_rol')
     and (has_function_privilege('anon', p.oid, 'execute')
          or not has_function_privilege('authenticated', p.oid, 'execute')
          or not p.prosecdef);
  if v_mal is not null then
    raise exception 'MIG59: permisos alterados en: %', v_mal;
  end if;
end;
$chk$;
