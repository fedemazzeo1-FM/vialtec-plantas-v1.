-- ============================================================================
-- Migración 60: motivo obligatorio en las correcciones (despacho y vale)
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Decisión de Federico (2026-10-05): corregir un despacho o un vale de
-- báscula exige siempre el motivo y se registra siempre como CORREGIR.
--   - corregir_despacho: rechaza si p_notas viene vacío (misma firma).
--   - corregir_vale_bascula: parámetro nuevo p_motivo (al final, obligatorio
--     aunque tenga DEFAULT null para no romper la firma por nombre); el motivo
--     también queda en plantas_vales_historial. Cambia la firma: se hace
--     drop + create y se vuelven a dar los permisos (sin anon).
--   - Si la corrección no cambió nada, no se registra fila de auditoría (la
--     pantalla de Báscula llama a corregir_vale_bascula también cuando solo
--     se reasigna el pedido).
--
-- IMPORTANTE: aplicar JUNTO con el deploy del frontend que pide el motivo
-- (commit de la misma fecha). Con el frontend viejo, editar un vale o
-- corregir un despacho sin notas da "Indicá el motivo…". Federico pidió
-- hacerlo fuera del horario de báscula (después de las 19 h).
--
-- Mismo método que 55-59: parche sobre la definición real de producción con
-- md5 antes/después. Reversión: volver a los cuerpos de
-- supabase/scripts/referencia_funciones_auditadas.sql (y la firma de 11
-- parámetros de corregir_vale_bascula).
-- ============================================================================

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
