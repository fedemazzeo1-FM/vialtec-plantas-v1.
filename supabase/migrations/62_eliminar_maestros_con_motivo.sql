-- ============================================================================
-- Migración 62: eliminar en Maestros exige motivo (queda en la auditoría)
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Decisión de Federico (2026-10-05): al eliminar un registro de Maestros la
-- pantalla pide el motivo, en vez del texto fijo de la migración 61.
--
--   1) plantas_eliminar_maestro(tabla, id, motivo): única vía de borrado desde
--      la app. SECURITY INVOKER a propósito: el DELETE lo hace el usuario, así
--      que siguen valiendo las policies de RLS de cada tabla (no cambia quién
--      puede borrar). Deja el motivo en una variable de la transacción y
--      borra; si no se borró nada (sin permiso o ya no existe), avisa.
--   2) plantas_trg_auditar (misma función de la 61): un DELETE sin motivo se
--      rechaza. Vale para las 10 tablas con trigger; la app solo borra en los
--      6 maestros. Por SQL directo: en la misma transacción,
--      select set_config('plantas.motivo_eliminacion', 'motivo', true);
--
-- IMPORTANTE: aplicar JUNTO con el deploy del frontend que pide el motivo.
-- Con el frontend viejo, eliminar en Maestros da "Para eliminar hay que
-- indicar el motivo".
--
-- Reversión: volver a crear plantas_trg_auditar con el cuerpo de la 61 y
-- drop function plantas_eliminar_maestro(text, uuid, text).
-- ============================================================================

create or replace function plantas_trg_auditar()
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
  v_motivo  text;
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
    -- El motivo lo deja plantas_eliminar_maestro() (o, por SQL directo, un
    -- set_config('plantas.motivo_eliminacion', '...', true) en la misma transacción).
    v_motivo := nullif(btrim(current_setting('plantas.motivo_eliminacion', true)), '');
    if v_motivo is null then
      raise exception 'Para eliminar hay que indicar el motivo (queda en la auditoría).';
    end if;
    perform plantas_auditar('ELIMINAR', v_modulo, v_entidad, v_ref, v_label, v_motivo, v_antes, null);
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

create function plantas_eliminar_maestro(p_tabla text, p_id uuid, p_motivo text)
returns void
language plpgsql
set search_path to 'public'
as $fn$
declare
  v_n int;
begin
  if p_tabla not in ('plantas_materiales', 'plantas_proveedores', 'plantas_clientes',
                     'plantas_encargados', 'plantas_choferes', 'plantas_patentes') then
    raise exception 'Tabla no permitida: %', p_tabla;
  end if;
  if nullif(btrim(p_motivo), '') is null then
    raise exception 'Indicá el motivo de la eliminación.';
  end if;

  perform set_config('plantas.motivo_eliminacion', btrim(p_motivo), true);
  execute format('delete from %I where id = $1', p_tabla) using p_id;
  get diagnostics v_n = row_count;
  perform set_config('plantas.motivo_eliminacion', '', true);

  if v_n = 0 then
    raise exception 'No se eliminó nada: el registro ya no existe o tu rol no puede eliminarlo.';
  end if;
end;
$fn$;

revoke execute on function plantas_eliminar_maestro(text, uuid, text) from public, anon;
grant execute on function plantas_eliminar_maestro(text, uuid, text) to authenticated;
