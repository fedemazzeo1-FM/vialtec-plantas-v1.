-- ============================================================================
-- Migración 56: módulo de Auditoría, etapa 3 — las funciones de báscula
-- registran en plantas_auditoria
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Funciones: registrar_pesada_bascula, corregir_vale_bascula, anular_vale_bascula, reasignar_vale_bascula.
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

select plantas__auditoria_patch('registrar_pesada_bascula', '8142fce6502814738dab39b8b3f3b1ba', 'b389e15cec43b26d4a60cac77db518db',
  $a$
  return v_vale;
end;$a$,
  $b$
  perform plantas_auditar_vale('CREAR', v_vale.id);

  return v_vale;
end;$b$
);

select plantas__auditoria_patch('corregir_vale_bascula', 'c7d6efb3c3396405ac63fbead1763b24', '0ef930081a9f6ef24e1f16ddc6a97bb2',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  select * into v_vale from plantas_vales where id = p_vale_id;
$a$,
  $b$  select * into v_vale from plantas_vales where id = p_vale_id;
  v_aud_antes := plantas_auditoria_snapshot_vale(p_vale_id);
$b$,
  $a$
  return v_vale;
end;$a$,
  $b$
  perform plantas_auditar_vale('EDITAR', p_vale_id, null, v_aud_antes);

  return v_vale;
end;$b$
);

select plantas__auditoria_patch('anular_vale_bascula', '0154b71ce87ff116a2e01f1743e73cab', 'fd2e6a092faa58f1f460e83b4a330bae',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  select * into v_vale from plantas_vales where id = p_vale_id;
$a$,
  $b$  select * into v_vale from plantas_vales where id = p_vale_id;
  v_aud_antes := plantas_auditoria_snapshot_vale(p_vale_id);
$b$,
  $a$
  return v_vale;
end;$a$,
  $b$
  perform plantas_auditar_vale('ANULAR', p_vale_id, btrim(p_motivo), v_aud_antes);

  return v_vale;
end;$b$
);

select plantas__auditoria_patch('reasignar_vale_bascula', 'e0750089596b4db63d1ded1f2c1df837', '4ae971553fe7959392ed9430b9b320b3',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  select * into v_vale from plantas_vales where id = p_vale_id for update;
$a$,
  $b$  select * into v_vale from plantas_vales where id = p_vale_id for update;
  v_aud_antes := plantas_auditoria_snapshot_vale(p_vale_id);
$b$,
  $a$
  return v_vale;
end;$a$,
  $b$
  perform plantas_auditar_vale('REASIGNAR', p_vale_id, btrim(p_motivo), v_aud_antes);

  return v_vale;
end;$b$
);

do $chk$
declare
  v_mal text;
begin
  select string_agg(p.proname, ', ') into v_mal
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('registrar_pesada_bascula', 'corregir_vale_bascula', 'anular_vale_bascula', 'reasignar_vale_bascula')
     and (has_function_privilege('anon', p.oid, 'execute')
          or not has_function_privilege('authenticated', p.oid, 'execute')
          or not p.prosecdef);
  if v_mal is not null then
    raise exception 'MIG56: permisos alterados en: %', v_mal;
  end if;
end;
$chk$;
