-- ============================================================================
-- Dry-run de la migración 62 (eliminar en Maestros con motivo) contra
-- producción. Termina SIEMPRE con raise exception: no persiste nada. Bloquea
-- plantas_auditoria mientras corre y devuelve su numeración al final.
-- ============================================================================
do $dry$
declare
  v_admin text; v_encargado text; v_id uuid; v_id2 uuid; v_n int; v_m int; v_txt text; v_estado text; v_ok text := '';
  s5 bigint; c5 boolean;
begin
  lock table plantas_auditoria in share row exclusive mode;
  select last_value, is_called into s5, c5 from plantas_auditoria_id_seq;
  select email into v_admin from plantas_usuarios_roles where rol = 'admin' and activo limit 1;
  select email into v_encargado from plantas_usuarios_roles where rol = 'encargado' and activo order by email limit 1;

  execute $m62$

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

$m62$;

  perform set_config('request.jwt.claims', json_build_object('email', v_admin, 'sub', (select id from auth.users where lower(email) = lower(v_admin)), 'role', 'authenticated')::text, true);
  insert into plantas_proveedores (nombre, activo) values ('DRY PROVEEDOR A', true) returning id into v_id;
  insert into plantas_proveedores (nombre, activo) values ('DRY PROVEEDOR B', true) returning id into v_id2;

  -- 1) borrado directo sin motivo (lo que hace la pantalla vieja)
  v_estado := 'sin error';
  begin
    execute 'set local role authenticated';
    delete from plantas_proveedores where id = v_id;
  exception when others then v_estado := sqlerrm;
  end;
  execute 'reset role';
  if v_estado <> 'Para eliminar hay que indicar el motivo (queda en la auditoría).' then raise exception 'FALLA 1: %', v_estado; end if;
  v_ok := v_ok || '1 borrado directo sin motivo (pantalla vieja) rechazado ("' || v_estado || '"); ';

  -- 2) RPC sin motivo
  v_estado := 'sin error';
  begin perform plantas_eliminar_maestro('plantas_proveedores', v_id, '  '); exception when others then v_estado := sqlerrm; end;
  if v_estado <> 'Indicá el motivo de la eliminación.' then raise exception 'FALLA 2: %', v_estado; end if;
  v_ok := v_ok || '2 sin motivo rechazado ("' || v_estado || '"); ';

  -- 3) tabla fuera de la lista
  v_estado := 'sin error';
  begin perform plantas_eliminar_maestro('plantas_pedidos', v_id, 'x'); exception when others then v_estado := sqlerrm; end;
  if v_estado not like 'Tabla no permitida%' then raise exception 'FALLA 3: %', v_estado; end if;
  v_ok := v_ok || '3 tabla fuera de Maestros rechazada; ';

  -- 4) un rol sin permiso de eliminar no borra ni deja fila
  select count(*) into v_n from plantas_auditoria;
  perform set_config('request.jwt.claims', json_build_object('email', v_encargado, 'role', 'authenticated')::text, true);
  v_estado := 'sin error';
  begin
    execute 'set local role authenticated';
    perform plantas_eliminar_maestro('plantas_proveedores', v_id, 'no deberia poder');
  exception when others then v_estado := sqlerrm;
  end;
  execute 'reset role';
  select count(*) into v_m from plantas_auditoria;
  if v_estado not like 'No se eliminó nada%' or v_m <> v_n or not exists (select 1 from plantas_proveedores where id = v_id) then
    raise exception 'FALLA 4: % (filas % -> %)', v_estado, v_n, v_m;
  end if;
  v_ok := v_ok || '4 encargado (' || v_encargado || ') no puede eliminar: "' || v_estado || '", sin fila; ';

  -- 5) admin logueado con motivo
  perform set_config('request.jwt.claims', json_build_object('email', v_admin, 'sub', (select id from auth.users where lower(email) = lower(v_admin)), 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  perform plantas_eliminar_maestro('plantas_proveedores', v_id, 'cargado por error');
  execute 'reset role';
  select tipo_accion || ' ' || entidad || ' [' || entidad_label || '] motivo: ' || motivo || ' / ' || usuario_nombre into v_txt from plantas_auditoria order by id desc limit 1;
  if v_txt not like 'ELIMINAR proveedor%motivo: cargado por error%' or exists (select 1 from plantas_proveedores where id = v_id) then
    raise exception 'FALLA 5: %', v_txt;
  end if;
  v_ok := v_ok || '5 con motivo: ' || v_txt || '; ';

  -- 6) el motivo no queda "pegado" para el borrado siguiente
  v_estado := 'sin error';
  begin delete from plantas_proveedores where id = v_id2; exception when others then v_estado := sqlerrm; end;
  if v_estado not like 'Para eliminar hay que indicar el motivo%' then raise exception 'FALLA 6: %', v_estado; end if;
  v_ok := v_ok || '6 el motivo no se reutiliza en el borrado siguiente; ';

  -- 7) permisos
  if has_function_privilege('anon', 'public.plantas_eliminar_maestro(text, uuid, text)', 'execute')
     or not has_function_privilege('authenticated', 'public.plantas_eliminar_maestro(text, uuid, text)', 'execute') then
    raise exception 'FALLA 7: permisos';
  end if;
  v_ok := v_ok || '7 la funcion es para usuarios logueados, no para anon';

  raise exception 'DRYRUN 62 OK — %', v_ok;
exception when others then
  perform setval('plantas_auditoria_id_seq', s5, c5);
  raise;
end;
$dry$;
