-- ============================================================================
-- REVERSIÓN de las migraciones 60 y 62 (motivo obligatorio). Solo para el caso
-- en que se apliquen y el deploy del frontend falle: con las migraciones
-- aplicadas y la pantalla vieja no se pueden editar vales, corregir despachos
-- sin notas ni eliminar en Maestros. Regla de Federico (2026-10-05): nunca
-- dejar la migración sin el deploy.
-- Deja corregir_despacho y corregir_vale_bascula (11 parámetros) con el cuerpo
-- de la etapa 3 (md5 verificado), plantas_trg_auditar como en la 61 y borra
-- plantas_eliminar_maestro. Cada bloque se puede correr solo.
-- ============================================================================

-- ---- 62 ----
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

drop function if exists plantas_eliminar_maestro(text, uuid, text);

-- ---- 60 ----
do $rev$
declare
  v_oid oid; v_src text; v_def text;
  v_viejo_d text := $viejo$
declare
  v_aud_antes jsonb;
  v_pedido         plantas_pedidos;
  v_diff           jsonb;
  v_cantidad_nueva numeric;
begin
  if not plantas_tiene_permiso('despachos', 'editar') then
    raise exception 'Tu rol (%) no puede corregir un despacho.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.estado <> 'despachado' then
    raise exception 'Solo se puede corregir un despacho ya cerrado (estado actual: %).', v_pedido.estado;
  end if;
  if p_cantidad_despachada is not null and not (p_cantidad_despachada > 0) then
    raise exception 'La cantidad corregida debe ser mayor a 0.';
  end if;

  v_cantidad_nueva := coalesce(p_cantidad_despachada, v_pedido.cantidad_despachada);

  v_diff := jsonb_build_object(
    'cantidad_despachada', jsonb_build_object('anterior', v_pedido.cantidad_despachada, 'nueva', v_cantidad_nueva),
    'nro_remito_global', jsonb_build_object('anterior', v_pedido.nro_remito_global, 'nuevo', coalesce(p_nro_remito_global, v_pedido.nro_remito_global)),
    'nro_vale_global', jsonb_build_object('anterior', v_pedido.nro_vale_global, 'nuevo', coalesce(p_nro_vale_global, v_pedido.nro_vale_global))
  );

  update plantas_pedidos
    set cantidad_despachada = v_cantidad_nueva,
        nro_remito_global   = coalesce(p_nro_remito_global, nro_remito_global),
        nro_vale_global     = coalesce(p_nro_vale_global, nro_vale_global)
    where id = p_pedido_id;

  perform plantas_descontar_stock_despacho(p_pedido_id, v_pedido.cantidad_despachada, v_cantidad_nueva);

  insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id, motivo, datos_legados)
  values (p_pedido_id, 'corregido', now(), auth.uid(), p_notas, v_diff);

  select * into v_pedido from plantas_pedidos where id = p_pedido_id;
  perform plantas_auditar_pedido(case when nullif(btrim(p_notas), '') is null then 'EDITAR' else 'CORREGIR' end, 'despacho', p_pedido_id, p_notas, v_aud_antes);

  return v_pedido;
end;
$viejo$;
  v_viejo_v text := $viejo$
declare
  v_aud_antes jsonb;
  v_vale        plantas_vales;
  v_antes       jsonb;
  v_peso_neto   numeric;
  v_neto_tn     numeric;
  v_material_id uuid;
begin
  if not plantas_tiene_permiso('bascula', 'editar') then
    raise exception 'Tu rol (%) no puede editar vales de báscula.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  select * into v_vale from plantas_vales where id = p_vale_id;
  v_aud_antes := plantas_auditoria_snapshot_vale(p_vale_id);
  if not found then
    raise exception 'El vale % no existe.', p_vale_id;
  end if;
  if v_vale.anulado then
    raise exception 'Este vale está anulado — no se puede editar. Cargá un vale nuevo si corresponde.';
  end if;

  if not (p_peso_bruto > 0) then
    raise exception 'peso_bruto debe ser mayor a 0';
  end if;
  if not (p_tara >= 0) then
    raise exception 'tara no puede ser negativa';
  end if;
  if not (p_peso_bruto > p_tara) then
    raise exception 'el peso bruto debe ser mayor que la tara';
  end if;

  v_peso_neto := p_peso_bruto - p_tara;
  v_neto_tn := case when v_vale.unidad = 'kg' then v_peso_neto / 1000 else v_peso_neto end;

  if v_vale.tipo_vale = 'ingreso_arido' and p_numero_remito is not null and btrim(p_numero_remito) <> '' then
    if exists (
      select 1 from plantas_ingresos
      where numero_remito = btrim(p_numero_remito) and vale_id <> p_vale_id
    ) then
      raise exception 'Ya existe otro ingreso registrado con el remito %.', p_numero_remito;
    end if;
  end if;

  v_antes := jsonb_build_object(
    'peso_bruto', v_vale.peso_bruto, 'tara', v_vale.tara, 'peso_neto', v_vale.peso_neto,
    'patente', v_vale.patente, 'chofer', v_vale.chofer, 'temperatura', v_vale.temperatura,
    'obra_id', v_vale.obra_id, 'observaciones', v_vale.observaciones
  );
  if v_vale.tipo_vale = 'ingreso_arido' then
    v_antes := v_antes || coalesce((
      select jsonb_build_object('proveedor', proveedor, 'numero_remito', numero_remito, 'cantidad_remito', cantidad)
      from plantas_ingresos where vale_id = p_vale_id limit 1
    ), '{}'::jsonb);
  end if;

  update plantas_vales set
    peso_bruto    = p_peso_bruto,
    tara          = p_tara,
    peso_neto     = v_peso_neto,
    patente       = coalesce(p_patente, patente),
    chofer        = case when tipo_vale = 'asfalto' then coalesce(p_chofer, chofer) else chofer end,
    temperatura   = case when tipo_vale = 'asfalto' then p_temperatura else temperatura end,
    obra_id       = case when tipo_vale = 'egreso_arido' then coalesce(p_obra_id, obra_id) else obra_id end,
    observaciones = coalesce(p_observaciones, observaciones)
  where id = p_vale_id
  returning * into v_vale;

  if v_vale.tipo_vale = 'ingreso_arido' then
    update plantas_ingresos set
      proveedor     = coalesce(p_proveedor, proveedor),
      numero_remito = coalesce(nullif(btrim(p_numero_remito), ''), numero_remito),
      cantidad      = coalesce(p_cantidad_remito, cantidad)
    where vale_id = p_vale_id;

    v_material_id := plantas_buscar_material_id(v_vale.material);
    perform plantas_recalcular_stock_vale(
      p_vale_id, v_material_id, coalesce(p_cantidad_remito, v_neto_tn) * 1000,
      p_proveedor, p_numero_remito, 'Corrección de vale #' || plantas_etiqueta_vale(v_vale)
    );
  end if;

  if v_vale.tipo_vale = 'egreso_arido' then
    v_material_id := plantas_buscar_material_id(v_vale.material);
    perform plantas_recalcular_stock_vale(
      p_vale_id, v_material_id, -(v_neto_tn * 1000),
      null, null, 'Corrección de vale #' || plantas_etiqueta_vale(v_vale)
    );
  end if;

  insert into plantas_vales_historial (vale_id, accion, pedido_anterior_id, pedido_nuevo_id, antes, despues, usuario_email)
  values (
    p_vale_id, 'edicion', v_vale.pedido_id, v_vale.pedido_id, v_antes,
    jsonb_build_object(
      'peso_bruto', v_vale.peso_bruto, 'tara', v_vale.tara, 'peso_neto', v_vale.peso_neto,
      'patente', v_vale.patente, 'chofer', v_vale.chofer, 'temperatura', v_vale.temperatura,
      'obra_id', v_vale.obra_id, 'observaciones', v_vale.observaciones
    ) || case when v_vale.tipo_vale = 'ingreso_arido' then coalesce((
      select jsonb_build_object('proveedor', proveedor, 'numero_remito', numero_remito, 'cantidad_remito', cantidad)
      from plantas_ingresos where vale_id = p_vale_id limit 1
    ), '{}'::jsonb) else '{}'::jsonb end,
    auth.email()
  );

  perform plantas_auditar_vale('EDITAR', p_vale_id, null, v_aud_antes);

  return v_vale;
end;
$viejo$;
begin
  select p.oid, p.prosrc into strict v_oid, v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'corregir_despacho';
  if md5(v_src) <> '97902d48adcf29fb287572e652cd5465' then
    execute replace(pg_get_functiondef(v_oid), v_src, v_viejo_d);
  end if;

  select p.oid, p.prosrc into strict v_oid, v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'corregir_vale_bascula';
  if md5(v_src) <> '0ef930081a9f6ef24e1f16ddc6a97bb2' then
    v_def := replace(pg_get_functiondef(v_oid), v_src, v_viejo_v);
    v_def := replace(v_def, 'p_obra_id bigint DEFAULT NULL::bigint, p_motivo text DEFAULT NULL::text)', 'p_obra_id bigint DEFAULT NULL::bigint)');
    execute 'drop function ' || v_oid::regprocedure;
    execute v_def;
    revoke execute on function corregir_vale_bascula(uuid, numeric, numeric, text, text, text, numeric, text, text, numeric, bigint) from public, anon;
    grant execute on function corregir_vale_bascula(uuid, numeric, numeric, text, text, text, numeric, text, text, numeric, bigint) to authenticated, service_role;
  end if;

  if (select md5(prosrc) from pg_proc where proname = 'corregir_despacho') <> '97902d48adcf29fb287572e652cd5465'
     or (select md5(prosrc) from pg_proc where proname = 'corregir_vale_bascula') <> '0ef930081a9f6ef24e1f16ddc6a97bb2'
     or (select count(*) from pg_proc where proname = 'corregir_vale_bascula') <> 1 then
    raise exception 'REVERSION 60: las funciones no quedaron como antes';
  end if;
end;
$rev$;
