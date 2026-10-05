-- ============================================================================
-- Migración 61: módulo de Auditoría, etapa 4 — triggers sobre lo que la app
-- escribe directo (sin RPC)
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Tablas: plantas_formulas, plantas_materiales, plantas_proveedores,
-- plantas_clientes, plantas_encargados, plantas_choferes, plantas_patentes,
-- plantas_roles, plantas_permisos, plantas_obras_locales.
--
-- Un solo trigger genérico (plantas_trg_auditar, SECURITY DEFINER) AFTER
-- INSERT/UPDATE/DELETE por fila, que llama a plantas_auditar en la misma
-- transacción (si no puede registrar, la operación falla).
--
-- Reglas:
--   - Sin doble registro (decisión 2 de Federico): si el cambio lo hizo otro
--     trigger, no se registra acá (pg_trigger_depth() > 1). Caso real: al
--     renombrar un material, plantas_trg_material_renombrado reescribe las
--     fórmulas; queda UNA fila (el renombre del material), no una por
--     fórmula. Los permisos que se borran en cascada con su rol tampoco
--     generan fila propia (se detecta porque el rol ya no existe: el borrado
--     en cascada no cuenta como trigger anidado). Ninguna de las 18 RPC auditadas escribe en estas tablas
--     (relevado en producción), así que no hay cruce con la etapa 3.
--   - Alta = CREAR (registro completo); edición = EDITAR (solo lo cambiado;
--     sin cambios no registra); si lo único que cambió es activo / habilitado
--     = CAMBIAR_ESTADO; borrado = ELIMINAR con el registro completo.
--   - ELIMINAR exige motivo y la pantalla no lo pide: queda el texto fijo
--     "Eliminado desde la pantalla (no se pide motivo)".
--   - Fórmulas: el cambio de `tipo` va en una fila aparte, marcada "CAMBIO DE
--     TIPO" (define unidad y circuito; los pedidos existentes conservan el
--     tipo que copiaron al crearse).
--   - Permisos: la pantalla guarda la matriz completa de un rol; solo se
--     registran las celdas que cambian, y al crear un rol solo las
--     habilitadas.
--   - Obras archivadas (plantas_obras_locales): siempre CAMBIAR_ESTADO
--     (archivar / desarchivar), aunque la primera vez sea un alta de fila.
--
-- No toca tablas flota_* (solo lee flota_obras para el nombre).
--
-- Reversión: drop de los 10 triggers y de plantas_trg_auditar().
-- ============================================================================

create function plantas_trg_auditar()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_modulo  text := tg_argv[0];
  v_entidad text := tg_argv[1];
  v_col_ref text := tg_argv[2];
  v_antes   jsonb;
  v_despues jsonb;
  v_fila    jsonb;
  v_ref     text;
  v_label   text;
  v_estado  text;
begin
  -- El cambio lo hizo otro trigger: ya queda registrado en su origen.
  if pg_trigger_depth() > 1 then
    return null;
  end if;

  if tg_op <> 'INSERT' then v_antes := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then v_despues := to_jsonb(new); end if;
  v_fila := coalesce(v_despues, v_antes);

  v_ref := case v_entidad
    when 'permiso' then (v_fila->>'rol_id') || ' · ' || (v_fila->>'modulo') || ' · ' || (v_fila->>'accion')
    else v_fila->>v_col_ref
  end;
  v_label := case v_entidad
    when 'formula'    then 'Fórmula ' || (v_fila->>'nombre') || ' (' || (v_fila->>'tipo') || ')'
    when 'patente'    then 'Patente ' || (v_fila->>'patente')
    when 'rol'        then 'Rol ' || (v_fila->>'nombre')
    when 'permiso'    then 'Permiso de ' || (v_fila->>'rol_id') || ': ' || (v_fila->>'modulo') || ' / ' || (v_fila->>'accion')
    when 'obra_local' then 'Obra ' || coalesce((select o.nombre from flota_obras o where o.id = (v_fila->>'obra_id')::bigint), v_fila->>'obra_id')
    else (select e.entidad_etiqueta from plantas_auditoria_entidades e where e.entidad = v_entidad) || ' ' || (v_fila->>'nombre')
  end;

  if tg_op = 'INSERT' then
    if v_entidad = 'permiso' and not coalesce((v_despues->>'habilitado')::boolean, false) then
      return null;
    end if;
    if v_entidad = 'obra_local' then
      perform plantas_auditar('CAMBIAR_ESTADO', v_modulo, v_entidad, v_ref, v_label, null,
        jsonb_build_object('archivada', false), v_despues - 'created_at');
    else
      perform plantas_auditar('CREAR', v_modulo, v_entidad, v_ref, v_label, null, null, v_despues);
    end if;
    return null;
  end if;

  if tg_op = 'DELETE' then
    -- Permisos borrados en cascada junto con su rol: alcanza con la fila del rol.
    if v_entidad = 'permiso' and not exists (select 1 from plantas_roles r where r.id = v_antes->>'rol_id') then
      return null;
    end if;
    perform plantas_auditar('ELIMINAR', v_modulo, v_entidad, v_ref, v_label,
      'Eliminado desde la pantalla (no se pide motivo)', v_antes, null);
    return null;
  end if;

  -- UPDATE
  if v_antes = v_despues then
    return null;
  end if;

  if v_entidad = 'formula' and (v_antes->>'tipo') is distinct from (v_despues->>'tipo') then
    perform plantas_auditar('EDITAR', v_modulo, v_entidad, v_ref,
      'CAMBIO DE TIPO — Fórmula ' || (v_despues->>'nombre') || ': ' || (v_antes->>'tipo') || ' → ' || (v_despues->>'tipo')
        || ' (cambia unidad y circuito; los pedidos ya creados conservan el tipo anterior)',
      null,
      jsonb_build_object('tipo', v_antes->'tipo', 'unidad', v_antes->'unidad'),
      jsonb_build_object('tipo', v_despues->'tipo', 'unidad', v_despues->'unidad'));
    v_antes := v_antes - 'tipo' - 'unidad';
    v_despues := v_despues - 'tipo' - 'unidad';
    if v_antes = v_despues then
      return null;
    end if;
  end if;

  v_estado := case v_entidad when 'permiso' then 'habilitado' when 'obra_local' then 'archivada' else 'activo' end;
  perform plantas_auditar(
    case when v_entidad = 'obra_local' or (v_antes - v_estado) = (v_despues - v_estado) then 'CAMBIAR_ESTADO' else 'EDITAR' end,
    v_modulo, v_entidad, v_ref, v_label, null, v_antes, v_despues);
  return null;
end;
$fn$;

revoke execute on function plantas_trg_auditar() from public, anon, authenticated;

create trigger plantas_auditoria_formulas after insert or update or delete on plantas_formulas
  for each row execute function plantas_trg_auditar('formulas', 'formula', 'nombre');
create trigger plantas_auditoria_materiales after insert or update or delete on plantas_materiales
  for each row execute function plantas_trg_auditar('maestros', 'material', 'nombre');
create trigger plantas_auditoria_proveedores after insert or update or delete on plantas_proveedores
  for each row execute function plantas_trg_auditar('maestros', 'proveedor', 'nombre');
create trigger plantas_auditoria_clientes after insert or update or delete on plantas_clientes
  for each row execute function plantas_trg_auditar('maestros', 'cliente', 'nombre');
create trigger plantas_auditoria_encargados after insert or update or delete on plantas_encargados
  for each row execute function plantas_trg_auditar('maestros', 'encargado', 'nombre');
create trigger plantas_auditoria_choferes after insert or update or delete on plantas_choferes
  for each row execute function plantas_trg_auditar('maestros', 'chofer', 'nombre');
create trigger plantas_auditoria_patentes after insert or update or delete on plantas_patentes
  for each row execute function plantas_trg_auditar('maestros', 'patente', 'patente');
create trigger plantas_auditoria_roles after insert or update or delete on plantas_roles
  for each row execute function plantas_trg_auditar('usuarios', 'rol', 'id');
create trigger plantas_auditoria_permisos after insert or update or delete on plantas_permisos
  for each row execute function plantas_trg_auditar('usuarios', 'permiso', 'rol_id');
create trigger plantas_auditoria_obras_locales after insert or update or delete on plantas_obras_locales
  for each row execute function plantas_trg_auditar('maestros', 'obra_local', 'obra_id');
