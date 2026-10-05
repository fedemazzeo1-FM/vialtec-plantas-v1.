-- ============================================================================
-- Migración 57: módulo de Auditoría, etapa 3 — las funciones de stock
-- registran en plantas_auditoria
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Funciones: registrar_movimiento_manual, registrar_relevamiento_stock.
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

select plantas__auditoria_patch('registrar_movimiento_manual', '15bd831cfb2b84c7564a59a98d7097a6', '04bd70e093d957fe414041ff9c8fd82d',
  $a$
  return v_mov;
end;$a$,
  $b$
  perform plantas_auditar('CREAR', 'stock', 'movimiento_manual', v_mov.id::text,
    case when p_tipo = 'ingreso_manual' then 'Ingreso manual' else 'Salida manual' end
      || ' — ' || (select nombre from plantas_materiales where id = p_material_id)
      || ' — ' || replace(trim_scale(abs(v_mov.cantidad_kg))::text, '.', ',') || ' kg',
    null, null,
    to_jsonb(v_mov) || jsonb_build_object('material', (select nombre from plantas_materiales where id = p_material_id)));

  return v_mov;
end;$b$
);

select plantas__auditoria_patch('registrar_relevamiento_stock', '73a565628aa60cea09e001a8a0369ff4', 'a832a4464a153b77e49c34a5713d2919',
  $a$
declare
$a$,
  $b$
declare
  v_aud_items jsonb := '[]'::jsonb;
$b$,
  $a$      return next v_mov;
$a$,
  $b$      return next v_mov;
      v_aud_items := v_aud_items || jsonb_build_object(
        'material', (select nombre from plantas_materiales where id = v_material_id),
        'antes_kg', round(v_actual, 2), 'despues_kg', round(v_nueva, 2), 'ajuste_kg', round(v_mov.cantidad_kg, 2));
$b$,
  $a$
  return;
end;$a$,
  $b$
  if jsonb_array_length(v_aud_items) > 0 then
    perform plantas_auditar('CREAR', 'stock', 'relevamiento',
      to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD HH24:MI:SS'),
      'Relevamiento de stock — ' || jsonb_array_length(v_aud_items) || ' material(es) ajustado(s)',
      nullif(btrim(p_motivo), ''), null, jsonb_build_object('ajustes', v_aud_items));
  end if;

  return;
end;$b$
);

do $chk$
declare
  v_mal text;
begin
  select string_agg(p.proname, ', ') into v_mal
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('registrar_movimiento_manual', 'registrar_relevamiento_stock')
     and (has_function_privilege('anon', p.oid, 'execute')
          or not has_function_privilege('authenticated', p.oid, 'execute')
          or not p.prosecdef);
  if v_mal is not null then
    raise exception 'MIG57: permisos alterados en: %', v_mal;
  end if;
end;
$chk$;
