-- ============================================================================
-- Dry-run de la migración 61 (triggers de auditoría, etapa 4) contra
-- producción. Termina SIEMPRE con raise exception: no persiste nada. Bloquea
-- plantas_auditoria mientras corre y devuelve su numeración al final.
-- ============================================================================
do $dry$
declare
  v_admin text; v_obra bigint; v_n int; v_m int; v_txt text; v_ok text := '';
  s5 bigint; c5 boolean;
begin
  lock table plantas_auditoria in share row exclusive mode;
  select last_value, is_called into s5, c5 from plantas_auditoria_id_seq;
  select email into v_admin from plantas_usuarios_roles where rol = 'admin' and activo limit 1;
  select o.id into v_obra from flota_obras o where not exists (select 1 from plantas_obras_locales l where l.obra_id = o.id) order by o.id limit 1;
  perform set_config('request.jwt.claims', json_build_object('email', v_admin, 'sub', (select id from auth.users where lower(email) = lower(v_admin)), 'role', 'authenticated')::text, true);

  execute $m61$

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

$m61$;

  execute $h$
    create function public.dry4_paso(p_sql text, p_esperado int, p_accion text, p_desc text)
    returns text language plpgsql set search_path to 'public' as $f$
    declare v_n int; v_m int; v_acc text; v_txt text;
    begin
      select count(*) into v_n from plantas_auditoria;
      execute p_sql;
      select count(*) into v_m from plantas_auditoria;
      select tipo_accion, entidad_label into v_acc, v_txt from plantas_auditoria order by id desc limit 1;
      if v_m - v_n <> p_esperado or (p_accion is not null and v_acc <> p_accion) then
        raise exception 'DRY FALLA (%): % filas nuevas (esperado %), ultima % [%]', p_desc, v_m - v_n, p_esperado, v_acc, v_txt;
      end if;
      return p_desc || ': ' || case when p_esperado = 0 then 'no registra'
        else p_esperado || ' fila(s) ' || p_accion || ' [' || v_txt || ']' end || '; ';
    end $f$;
  $h$;

  v_ok := v_ok || dry4_paso($s$insert into plantas_proveedores (nombre, activo) values ('DRY PROVEEDOR', true)$s$, 1, 'CREAR', 'alta de proveedor');
  v_ok := v_ok || dry4_paso($s$update plantas_proveedores set nombre = 'DRY PROVEEDOR 2', material_principal = 'ARENA' where nombre = 'DRY PROVEEDOR'$s$, 1, 'EDITAR', 'edicion de proveedor');
  v_ok := v_ok || dry4_paso($s$update plantas_proveedores set nombre = 'DRY PROVEEDOR 2' where nombre = 'DRY PROVEEDOR 2'$s$, 0, null, 'guardar proveedor sin cambios');
  v_ok := v_ok || dry4_paso($s$update plantas_proveedores set activo = false where nombre = 'DRY PROVEEDOR 2'$s$, 1, 'CAMBIAR_ESTADO', 'desactivar proveedor');
  v_ok := v_ok || dry4_paso($s$delete from plantas_proveedores where nombre = 'DRY PROVEEDOR 2'$s$, 1, 'ELIMINAR', 'eliminar proveedor');
  v_ok := v_ok || dry4_paso($s$insert into plantas_materiales (nombre, unidad, categoria, controla_stock, activo) select 'DRYMAT A', unidad, categoria, false, true from plantas_materiales limit 1$s$, 1, 'CREAR', 'alta de material');
  v_ok := v_ok || dry4_paso($s$insert into plantas_formulas (nombre, tipo, unidad, activo, insumos) values ('DRY FORMULA', 'asfalto', 'tn', true, '[{"id": "dry-1", "unidad": "%", "cantidad": 100, "material": "DRYMAT A"}]'::jsonb)$s$, 1, 'CREAR', 'alta de formula');
  v_ok := v_ok || dry4_paso($s$update plantas_materiales set nombre = 'DRYMAT B' where nombre = 'DRYMAT A'$s$, 1, 'EDITAR', 'renombrar material usado en una formula');
  v_ok := v_ok || dry4_paso($s$update plantas_formulas set insumos = jsonb_set(insumos, '{0,cantidad}', '95') where nombre = 'DRY FORMULA'$s$, 1, 'EDITAR', 'cambiar un dosaje');
  v_ok := v_ok || dry4_paso($s$update plantas_formulas set tipo = 'hormigon', unidad = 'm3', nombre = 'DRY FORMULA 2' where nombre = 'DRY FORMULA'$s$, 2, 'EDITAR', 'cambiar tipo y nombre de la formula');
  v_ok := v_ok || dry4_paso($s$update plantas_formulas set activo = false where nombre = 'DRY FORMULA 2'$s$, 1, 'CAMBIAR_ESTADO', 'desactivar formula');
  v_ok := v_ok || dry4_paso($s$insert into plantas_patentes (patente, es_externa, activo) values ('DRY999', false, true)$s$, 1, 'CREAR', 'alta de patente');
  v_ok := v_ok || dry4_paso($s$insert into plantas_roles (id, nombre, descripcion, es_sistema, activo) values ('dry_rol', 'Rol de prueba', '', false, true)$s$, 1, 'CREAR', 'alta de rol');
  v_ok := v_ok || dry4_paso($s$insert into plantas_permisos (rol_id, modulo, accion, habilitado) values ('dry_rol', 'pedidos', 'ver', true), ('dry_rol', 'pedidos', 'crear', false), ('dry_rol', 'stock', 'ver', false)$s$, 1, 'CREAR', 'matriz de un rol nuevo (3 celdas, 1 habilitada)');
  v_ok := v_ok || dry4_paso($s$insert into plantas_permisos (rol_id, modulo, accion, habilitado) values ('dry_rol', 'pedidos', 'ver', true), ('dry_rol', 'pedidos', 'crear', false), ('dry_rol', 'stock', 'ver', false) on conflict (rol_id, modulo, accion) do update set habilitado = excluded.habilitado$s$, 0, null, 'guardar la matriz sin cambios');
  v_ok := v_ok || dry4_paso($s$insert into plantas_permisos (rol_id, modulo, accion, habilitado) values ('dry_rol', 'pedidos', 'ver', true), ('dry_rol', 'pedidos', 'crear', true), ('dry_rol', 'stock', 'ver', false) on conflict (rol_id, modulo, accion) do update set habilitado = excluded.habilitado$s$, 1, 'CAMBIAR_ESTADO', 'habilitar un permiso');
  v_ok := v_ok || dry4_paso($s$delete from plantas_permisos where rol_id = 'dry_rol' and modulo = 'stock'$s$, 1, 'ELIMINAR', 'borrar un permiso suelto');
  v_ok := v_ok || dry4_paso($s$delete from plantas_roles where id = 'dry_rol'$s$, 1, 'ELIMINAR', 'eliminar el rol (sus permisos caen en cascada)');
  v_ok := v_ok || dry4_paso(format('insert into plantas_obras_locales (obra_id, archivada, archivada_en, archivada_por) values (%s, true, now(), %L)', v_obra, v_admin), 1, 'CAMBIAR_ESTADO', 'archivar obra');
  v_ok := v_ok || dry4_paso(format('update plantas_obras_locales set archivada = false, archivada_en = null, archivada_por = null where obra_id = %s', v_obra), 1, 'CAMBIAR_ESTADO', 'desarchivar obra');

  select insumos->0->>'material' into v_txt from plantas_formulas where nombre = 'DRY FORMULA 2';
  if v_txt <> 'DRYMAT B' then raise exception 'DRY FALLA: la formula no tomo el renombre (%)', v_txt; end if;
  select string_agg(entidad_label, ' // ' order by id) into v_txt from plantas_auditoria where entidad = 'formula' and entidad_label like 'CAMBIO DE TIPO%';
  v_ok := v_ok || 'la formula tomo el nombre nuevo del material sin fila propia; fila marcada: [' || coalesce(v_txt, 'NINGUNA') || ']; ';
  select motivo into v_txt from plantas_auditoria where tipo_accion = 'ELIMINAR' order by id desc limit 1;
  v_ok := v_ok || 'motivo de las eliminaciones: "' || v_txt || '"; ';

  select count(*) into v_n from plantas_auditoria;
  execute 'set local role authenticated';
  update plantas_patentes set tipo_camion = 'Batea' where patente = 'DRY999';
  execute 'reset role';
  select count(*) into v_m from plantas_auditoria;
  select usuario_nombre || ' / ' || usuario_rol || ' / ' || valores_despues::text into v_txt from plantas_auditoria order by id desc limit 1;
  if v_m - v_n <> 1 then raise exception 'DRY FALLA: edicion como usuario logueado dejo % filas', v_m - v_n; end if;
  v_ok := v_ok || 'edicion directa como usuario logueado: 1 fila [' || v_txt || ']; ';

  select string_agg(distinct p.proname, ', ') into v_txt
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname not in ('plantas_trg_material_renombrado', 'dry4_paso')
     and p.prosrc ~* '(insert into|update|delete from)\s+(public\.)?plantas_(formulas|materiales|proveedores|clientes|encargados|choferes|patentes|roles|permisos|obras_locales)\M';
  if v_txt is not null then raise exception 'DRY FALLA: funciones que escriben en tablas con trigger: %', v_txt; end if;
  select count(*) into v_n from pg_trigger where tgname like 'plantas_auditoria_%' and not tgisinternal and tgfoid = 'public.plantas_trg_auditar'::regproc;
  select count(*) into v_m from plantas_auditoria;
  v_ok := v_ok || 'ninguna RPC escribe en las tablas con trigger; ' || v_n || ' triggers creados; ' || v_m || ' filas en total durante el ensayo';

  raise exception 'DRYRUN 61 OK — %', v_ok;
exception when others then
  -- pase lo que pase, la numeración de la auditoría vuelve a su lugar
  perform setval('plantas_auditoria_id_seq', s5, c5);
  raise;
end;
$dry$;
