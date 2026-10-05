-- ============================================================================
-- Migración 58: módulo de Auditoría, etapa 3 — las funciones de remitos
-- registran en plantas_auditoria
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Funciones: generar_remito_manual.
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

select plantas__auditoria_patch('generar_remito_manual', 'fb7acfb13808a8b253865d237ed733ec', 'abf850288471d9e2c08a18f1cd50f8ca',
  $a$
  return jsonb_build_object('remito', to_jsonb(v_remito), 'items', v_items_out);
end;$a$,
  $b$
  perform plantas_auditar('CREAR', 'remitos', 'remito_manual', lpad(v_remito.numero_remito::text, 5, '0'),
    'Remito manual ' || lpad(v_remito.numero_remito::text, 5, '0') || coalesce(' — ' || v_remito.destino, ''),
    null, null, to_jsonb(v_remito) || jsonb_build_object('items', v_items_out));

  return jsonb_build_object('remito', to_jsonb(v_remito), 'items', v_items_out);
end;$b$
);

do $chk$
declare
  v_mal text;
begin
  select string_agg(p.proname, ', ') into v_mal
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('generar_remito_manual')
     and (has_function_privilege('anon', p.oid, 'execute')
          or not has_function_privilege('authenticated', p.oid, 'execute')
          or not p.prosecdef);
  if v_mal is not null then
    raise exception 'MIG58: permisos alterados en: %', v_mal;
  end if;
end;
$chk$;
