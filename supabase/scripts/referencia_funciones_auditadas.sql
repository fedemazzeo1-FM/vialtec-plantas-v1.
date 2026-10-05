-- ============================================================================
-- REFERENCIA (no es una migración, no ejecutar): cuerpo completo de las 18
-- RPC después de la etapa 3 de Auditoría (migraciones 55 a 59, aplicadas el
-- 2026-10-05). Las migraciones no traen el cuerpo entero: lo arman a partir
-- de la definición de producción. Este archivo deja escrito el resultado.
--
-- Cada bloque es el `prosrc` exacto de producción (md5 verificado contra
-- pg_proc después de aplicar). Firma, SECURITY DEFINER, search_path y
-- permisos no cambiaron: son los de la última migración que define cada
-- función. Para la próxima modificación, partir de acá o de
-- pg_get_functiondef, y comparar el md5.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- actualizar_pedido — md5(prosrc) = 839f708da9194edf5237b726014fe5a4
-- ---------------------------------------------------------------------------
-- create or replace function actualizar_pedido(...) ... as $function$
declare
  v_aud_antes jsonb;
  v_tipo   text;
  v_pedido plantas_pedidos;
begin
  if not plantas_tiene_permiso('pedidos', 'editar') then
    raise exception 'Tu rol (%) no puede editar pedidos.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;

  if plantas_rol_actual() not in ('admin', 'plantista')
     and coalesce(v_pedido.creado_por, '') <> coalesce(auth.email(), '') then
    raise exception 'Solo podés editar los pedidos que vos mismo creaste.';
  end if;

  if v_pedido.estado not in ('solicitado', 'confirmado') then
    raise exception 'Solo se puede editar un pedido solicitado o confirmado (estado actual: %).', v_pedido.estado;
  end if;

  select tipo into v_tipo from plantas_formulas where id = p_formula_id;
  if v_tipo is null then
    raise exception 'La fórmula % no existe.', p_formula_id;
  end if;
  if p_tipo_pedido not in ('obra', 'venta') then
    raise exception 'tipo_pedido inválido: %', p_tipo_pedido;
  end if;
  if p_tipo_pedido = 'venta' and (p_cliente_externo is null or btrim(p_cliente_externo) = '') then
    raise exception 'Las ventas externas necesitan cliente_externo.';
  end if;
  if p_tipo_pedido = 'obra' and p_obra_id is null then
    raise exception 'Completá la obra.';
  end if;
  if not (p_cantidad_solicitada > 0) then
    raise exception 'cantidad_solicitada debe ser mayor a 0.';
  end if;

  update plantas_pedidos
    set obra_id             = p_obra_id,
        formula_id          = p_formula_id,
        tipo                = v_tipo,
        cantidad_solicitada = p_cantidad_solicitada,
        fecha_programada    = p_fecha_programada,
        tipo_pedido         = p_tipo_pedido,
        cliente_externo     = p_cliente_externo,
        encargado           = p_encargado,
        ubicacion           = p_ubicacion,
        observaciones       = p_observaciones
    where id = p_pedido_id
    returning * into v_pedido;

  perform plantas_auditar_pedido('EDITAR', 'pedido', p_pedido_id, null, v_aud_antes);

  return v_pedido;
end;
$function$;

-- ---------------------------------------------------------------------------
-- admin_upsert_usuario_rol — md5(prosrc) = 98b8b67129aacc86c57b3fe87a7d9bdf
-- ---------------------------------------------------------------------------
-- create or replace function admin_upsert_usuario_rol(...) ... as $function$
declare
  v_aud_antes jsonb;
  v_resultado plantas_usuarios_roles;
begin
  if plantas_rol_actual() is distinct from 'admin' then
    raise exception 'Solo un usuario con rol admin puede administrar usuarios y roles.';
  end if;

  if not exists (select 1 from plantas_roles where id = p_rol and activo = true) then
    raise exception 'Rol "%" inválido o inactivo.', p_rol;
  end if;

  select to_jsonb(u) into v_aud_antes from plantas_usuarios_roles u where u.email = lower(trim(p_email));

  insert into plantas_usuarios_roles (email, rol, ver_todas_obras, ver_ventas, obra_ids, activo)
  values (lower(trim(p_email)), p_rol, p_ver_todas_obras, p_ver_ventas, coalesce(p_obra_ids, '{}'), p_activo)
  on conflict (email) do update set
    rol = excluded.rol,
    ver_todas_obras = excluded.ver_todas_obras,
    ver_ventas = excluded.ver_ventas,
    obra_ids = excluded.obra_ids,
    activo = excluded.activo
  returning * into v_resultado;

  perform plantas_auditar(case when v_aud_antes is null then 'CREAR' else 'EDITAR' end, 'usuarios', 'usuario_rol',
    v_resultado.email, v_resultado.email || ' — ' || v_resultado.rol, null, v_aud_antes, to_jsonb(v_resultado));

  return v_resultado;
end;
$function$;

-- ---------------------------------------------------------------------------
-- anular_vale_bascula — md5(prosrc) = fd2e6a092faa58f1f460e83b4a330bae
-- ---------------------------------------------------------------------------
-- create or replace function anular_vale_bascula(...) ... as $function$
declare
  v_aud_antes jsonb;
  v_vale        plantas_vales;
  v_material_id uuid;
begin
  if not plantas_tiene_permiso('bascula', 'eliminar') then
    raise exception 'Tu rol (%) no puede anular vales de báscula.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'El motivo de anulación es obligatorio.';
  end if;

  select * into v_vale from plantas_vales where id = p_vale_id;
  v_aud_antes := plantas_auditoria_snapshot_vale(p_vale_id);
  if not found then
    raise exception 'El vale % no existe.', p_vale_id;
  end if;
  if v_vale.anulado then
    raise exception 'Este vale ya está anulado.';
  end if;

  update plantas_vales set
    anulado          = true,
    anulado_en       = now(),
    anulado_por      = auth.email(),
    motivo_anulacion = btrim(p_motivo)
  where id = p_vale_id
  returning * into v_vale;

  if v_vale.tipo_vale in ('ingreso_arido', 'egreso_arido') then
    v_material_id := plantas_buscar_material_id(v_vale.material);
    perform plantas_recalcular_stock_vale(
      p_vale_id, v_material_id, 0, null, null, 'Anulación de vale #' || plantas_etiqueta_vale(v_vale) || ': ' || btrim(p_motivo)
    );
  end if;

  insert into plantas_vales_historial (vale_id, accion, pedido_anterior_id, pedido_nuevo_id, motivo, usuario_email)
  values (p_vale_id, 'anulacion', v_vale.pedido_id, v_vale.pedido_id, btrim(p_motivo), auth.email());

  perform plantas_auditar_vale('ANULAR', p_vale_id, btrim(p_motivo), v_aud_antes);

  return v_vale;
end;
$function$;

-- ---------------------------------------------------------------------------
-- archivar_pedido — md5(prosrc) = 1be71fa1d9cdcebf5bdc97d1a2fd3dd4
-- ---------------------------------------------------------------------------
-- create or replace function archivar_pedido(...) ... as $function$
declare
  v_aud_antes jsonb;
  v_rol    text;
  v_pedido plantas_pedidos;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista') then
    raise exception 'Tu rol (%) no puede archivar pedidos.', coalesce(v_rol, 'sin rol asignado');
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.estado not in ('despachado', 'cancelado') then
    raise exception 'Solo se pueden archivar pedidos despachados o cancelados (estado actual: %).', v_pedido.estado;
  end if;

  update plantas_pedidos set archivado = true where id = p_pedido_id returning * into v_pedido;
  perform plantas_auditar_pedido('CAMBIAR_ESTADO', 'pedido', p_pedido_id, null, v_aud_antes);

  return v_pedido;
end;
$function$;

-- ---------------------------------------------------------------------------
-- cancelar_pedido — md5(prosrc) = 14876c763a228e876db74a13c7e6ecbe
-- ---------------------------------------------------------------------------
-- create or replace function cancelar_pedido(...) ... as $function$
declare
  v_aud_antes jsonb;
  v_pedido plantas_pedidos;
begin
  if not plantas_tiene_permiso('pedidos', 'eliminar') then
    raise exception 'Tu rol (%) no puede cancelar pedidos.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'El motivo es obligatorio para cancelar un pedido.';
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.estado not in ('solicitado', 'confirmado', 'postergado') then
    raise exception 'No se puede cancelar un pedido en estado %.', v_pedido.estado;
  end if;

  update plantas_pedidos
    set estado = 'cancelado',
        observaciones = 'MOTIVO CANCELACIÓN: ' || p_motivo ||
          case when v_pedido.observaciones is not null and btrim(v_pedido.observaciones) <> ''
               then ' | OBS: ' || v_pedido.observaciones
               else '' end
    where id = p_pedido_id
    returning * into v_pedido;

  insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id, motivo, usuario_legado)
  values (p_pedido_id, 'cancelado', now(), auth.uid(), p_motivo, coalesce(p_usuario_legado, auth.email()));

  perform plantas_auditar_pedido('ANULAR', 'pedido', p_pedido_id, p_motivo, v_aud_antes);

  return v_pedido;
end;
$function$;

-- ---------------------------------------------------------------------------
-- confirmar_pedido — md5(prosrc) = b540acb86b43464f2ece54848b347a2b
-- ---------------------------------------------------------------------------
-- create or replace function confirmar_pedido(...) ... as $function$
declare
  v_aud_antes jsonb;
  v_pedido plantas_pedidos;
begin
  if not plantas_tiene_permiso('pedidos', 'aprobar') then
    raise exception 'Tu rol (%) no puede confirmar pedidos.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.estado not in ('solicitado', 'postergado') then
    raise exception 'Solo se puede confirmar un pedido solicitado o postergado (estado actual: %).', v_pedido.estado;
  end if;

  update plantas_pedidos
    set estado        = 'confirmado',
        observaciones = coalesce(p_observaciones, observaciones)
    where id = p_pedido_id
    returning * into v_pedido;

  insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id, usuario_legado)
  values (p_pedido_id, 'confirmado', now(), auth.uid(), coalesce(p_usuario_legado, auth.email()));

  perform plantas_auditar_pedido('CAMBIAR_ESTADO', 'pedido', p_pedido_id, null, v_aud_antes);

  return v_pedido;
end;
$function$;

-- ---------------------------------------------------------------------------
-- corregir_despacho — md5(prosrc) = 64c25609bdc164a1f8bc38806a0a3fa2 (desde la migración 60: motivo obligatorio)
-- ---------------------------------------------------------------------------
-- create or replace function corregir_despacho(...) ... as $function$
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
  if nullif(btrim(p_notas), '') is null then
    raise exception 'Indicá el motivo de la corrección.';
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
  if v_aud_antes is distinct from to_jsonb(v_pedido) then
    perform plantas_auditar_pedido('CORREGIR', 'despacho', p_pedido_id, btrim(p_notas), v_aud_antes);
  end if;

  return v_pedido;
end;
$function$;

-- ---------------------------------------------------------------------------
-- corregir_vale_bascula — md5(prosrc) = f1c5e2d4f2e5d7137fd06a7aa6fe7657 (desde la migración 60: motivo obligatorio; 12 parámetros, se agregó p_motivo)
-- ---------------------------------------------------------------------------
-- create or replace function corregir_vale_bascula(...) ... as $function$
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

  if nullif(btrim(p_motivo), '') is null then
    raise exception 'Indicá el motivo de la corrección del vale.';
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

  insert into plantas_vales_historial (vale_id, accion, pedido_anterior_id, pedido_nuevo_id, antes, despues, usuario_email, motivo)
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
    auth.email(), btrim(p_motivo)
  );

  if v_aud_antes is distinct from plantas_auditoria_snapshot_vale(p_vale_id) then
    perform plantas_auditar_vale('CORREGIR', p_vale_id, btrim(p_motivo), v_aud_antes);
  end if;

  return v_vale;
end;
$function$;

-- ---------------------------------------------------------------------------
-- crear_pedido — md5(prosrc) = 2a889ac9e31ff839242613358156b6ac
-- ---------------------------------------------------------------------------
-- create or replace function crear_pedido(...) ... as $function$
declare
  v_tipo   text;
  v_pedido plantas_pedidos;
begin
  if not plantas_tiene_permiso('pedidos', 'crear') then
    raise exception 'Tu rol (%) no puede crear pedidos.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  select tipo into v_tipo from plantas_formulas where id = p_formula_id;
  if v_tipo is null then
    raise exception 'La fórmula % no existe.', p_formula_id;
  end if;

  if p_tipo_pedido not in ('obra', 'venta') then
    raise exception 'tipo_pedido inválido: %', p_tipo_pedido;
  end if;
  if p_tipo_pedido = 'venta' and (p_cliente_externo is null or btrim(p_cliente_externo) = '') then
    raise exception 'Las ventas externas necesitan cliente_externo.';
  end if;
  if p_tipo_pedido = 'obra' and p_obra_id is null then
    raise exception 'Completá la obra.';
  end if;
  if not (p_cantidad_solicitada > 0) then
    raise exception 'cantidad_solicitada debe ser mayor a 0.';
  end if;

  insert into plantas_pedidos (
    obra_id, formula_id, tipo, cantidad_solicitada, fecha_programada,
    tipo_pedido, cliente_externo, encargado, ubicacion, observaciones, estado, creado_por
  ) values (
    p_obra_id, p_formula_id, v_tipo, p_cantidad_solicitada, p_fecha_programada,
    p_tipo_pedido, p_cliente_externo, p_encargado, p_ubicacion, p_observaciones, 'solicitado', auth.email()
  )
  returning * into v_pedido;

  insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id, usuario_legado)
  values (v_pedido.id, 'solicitado', now(), auth.uid(), coalesce(p_usuario_legado, auth.email()));

  perform plantas_auditar_pedido('CREAR', 'pedido', v_pedido.id);

  return v_pedido;
end;
$function$;

-- ---------------------------------------------------------------------------
-- finalizar_despacho — md5(prosrc) = 1ad19320c736f42b3eba6139518d0531
-- ---------------------------------------------------------------------------
-- create or replace function finalizar_despacho(...) ... as $function$
declare
  v_aud_antes jsonb;
  v_pedido   plantas_pedidos;
  v_residual numeric;
  v_ref      text;
begin
  if not plantas_tiene_permiso('despachos', 'aprobar') then
    raise exception 'Tu rol (%) no puede finalizar un despacho.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.estado <> 'confirmado' then
    raise exception 'El pedido tiene que estar confirmado para finalizar el despacho (estado actual: %).', v_pedido.estado;
  end if;
  if coalesce(v_pedido.cantidad_despachada, 0) <= 0 then
    raise exception 'Todavía no se cargó ninguna carga para este pedido.';
  end if;

  v_residual := v_pedido.cantidad_solicitada - v_pedido.cantidad_despachada;

  update plantas_pedidos set estado = 'despachado' where id = p_pedido_id;

  perform plantas_descontar_stock_despacho(p_pedido_id, 0, v_pedido.cantidad_despachada);

  insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id)
  values (p_pedido_id, 'despachado', now(), auth.uid());

  if p_dividir and v_residual > 0 then
    if p_fecha_residual is null then
      raise exception 'Elegí una fecha para el pedido residual.';
    end if;

    -- "pedido del 24/09/2026 (550 tn, Remito N° 00030)"
    v_ref := 'pedido del ' || to_char(v_pedido.fecha_programada, 'DD/MM/YYYY')
      || ' (' || replace(trim_scale(v_pedido.cantidad_solicitada)::text, '.', ',')
      || case when v_pedido.tipo = 'hormigon' then ' m³' else ' tn' end
      || coalesce(', Remito N° ' || lpad(nullif(v_pedido.nro_remito_global, ''), 5, '0'), '')
      || ')';

    declare
      v_nuevo_id uuid;
    begin
      insert into plantas_pedidos (
        obra_id, formula_id, tipo, cantidad_solicitada, fecha_programada, estado,
        tipo_pedido, cliente_externo, encargado, ubicacion, observaciones, nro_remito_global
      ) values (
        v_pedido.obra_id, v_pedido.formula_id, v_pedido.tipo, v_residual, p_fecha_residual, 'confirmado',
        v_pedido.tipo_pedido, v_pedido.cliente_externo, v_pedido.encargado, v_pedido.ubicacion,
        'Pedido residual generado automáticamente al dividir el despacho del ' || v_ref,
        v_pedido.nro_remito_global
      )
      returning id into v_nuevo_id;

      insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id, motivo)
      values (v_nuevo_id, 'confirmado', now(), auth.uid(), 'Residual del ' || v_ref);

      perform plantas_auditar_pedido('CREAR', 'pedido', v_nuevo_id);
    end;
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id;
  perform plantas_auditar_pedido('CAMBIAR_ESTADO', 'despacho', p_pedido_id, null, v_aud_antes);

  return v_pedido;
end;
$function$;

-- ---------------------------------------------------------------------------
-- generar_remito_manual — md5(prosrc) = abf850288471d9e2c08a18f1cd50f8ca
-- ---------------------------------------------------------------------------
-- create or replace function generar_remito_manual(...) ... as $function$
declare
  v_remito    plantas_remitos_manuales;
  v_item      jsonb;
  v_orden     integer := 0;
  v_items_out jsonb := '[]'::jsonb;
  v_descripcion text;
  v_cantidad    numeric;
  v_unidad      text;
begin
  if not plantas_tiene_permiso('despachos', 'aprobar') then
    raise exception 'Tu rol (%) no puede generar un remito manual.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Agregá al menos un item (cantidad/descripción).';
  end if;

  insert into plantas_remitos_manuales (destino, patente, transportista, fecha, creado_por)
  values (
    nullif(btrim(coalesce(p_destino, '')), ''),
    nullif(btrim(coalesce(p_patente, '')), ''),
    nullif(btrim(coalesce(p_transportista, '')), ''),
    coalesce(p_fecha, current_date),
    auth.email()
  )
  returning * into v_remito;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_descripcion := btrim(coalesce(v_item ->> 'descripcion', ''));
    if v_descripcion = '' then
      raise exception 'Cada item necesita una descripción.';
    end if;
    v_cantidad := nullif(v_item ->> 'cantidad', '')::numeric;
    v_unidad   := nullif(btrim(coalesce(v_item ->> 'unidad', '')), '');
    if v_cantidad is not null and v_unidad is null then
      raise exception 'Elegí la unidad de medida del item "%".', v_descripcion;
    end if;

    insert into plantas_remitos_manuales_items (remito_id, cantidad, unidad, descripcion, orden)
    values (v_remito.id, v_cantidad, v_unidad, v_descripcion, v_orden);

    v_items_out := v_items_out || jsonb_build_object('cantidad', v_cantidad, 'unidad', v_unidad, 'descripcion', v_descripcion);
    v_orden := v_orden + 1;
  end loop;

  perform plantas_auditar('CREAR', 'remitos', 'remito_manual', lpad(v_remito.numero_remito::text, 5, '0'),
    'Remito manual ' || lpad(v_remito.numero_remito::text, 5, '0') || coalesce(' — ' || v_remito.destino, ''),
    null, null, to_jsonb(v_remito) || jsonb_build_object('items', v_items_out));

  return jsonb_build_object('remito', to_jsonb(v_remito), 'items', v_items_out);
end;
$function$;

-- ---------------------------------------------------------------------------
-- postergar_pedido — md5(prosrc) = d6cdb4cb9d42e2bfd22b9fb2677fa2b0
-- ---------------------------------------------------------------------------
-- create or replace function postergar_pedido(...) ... as $function$
declare
  v_aud_antes jsonb;
  v_pedido         plantas_pedidos;
  v_fecha_anterior date;
begin
  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;

  if not (
    plantas_tiene_permiso('pedidos', 'aprobar')
    or (plantas_tiene_permiso('pedidos', 'crear') and coalesce(v_pedido.creado_por, '') = coalesce(auth.email(), ''))
  ) then
    raise exception 'Tu rol (%) no puede postergar este pedido.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  if v_pedido.estado not in ('solicitado', 'confirmado', 'postergado') then
    raise exception 'Solo se puede postergar un pedido solicitado, confirmado o ya postergado (estado actual: %).', v_pedido.estado;
  end if;

  v_fecha_anterior := v_pedido.fecha_programada;

  update plantas_pedidos
    set estado = 'postergado',
        fecha_programada = coalesce(p_fecha_nueva, fecha_programada),
        motivo = p_motivo,
        motivo_en = case when p_motivo is not null then now() else motivo_en end
    where id = p_pedido_id
    returning * into v_pedido;

  insert into plantas_pedidos_historial (
    pedido_id, estado, fecha_evento, fecha_programada_anterior, fecha_programada_nueva, usuario_id, motivo
  ) values (
    p_pedido_id, 'postergado', now(), v_fecha_anterior, p_fecha_nueva, auth.uid(), p_motivo
  );

  perform plantas_auditar_pedido('CAMBIAR_ESTADO', 'pedido', p_pedido_id, p_motivo, v_aud_antes);

  return v_pedido;
end;
$function$;

-- ---------------------------------------------------------------------------
-- reasignar_vale_bascula — md5(prosrc) = 4ae971553fe7959392ed9430b9b320b3
-- ---------------------------------------------------------------------------
-- create or replace function reasignar_vale_bascula(...) ... as $function$
declare
  v_aud_antes jsonb;
  v_vale    plantas_vales;
  v_origen  plantas_pedidos;
  v_destino plantas_pedidos;
begin
  if not plantas_tiene_permiso('bascula', 'editar') then
    raise exception 'Tu rol (%) no puede reasignar vales de báscula.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'El motivo de la reasignación es obligatorio.';
  end if;
  if p_pedido_id is null then
    raise exception 'Elegí el pedido correcto.';
  end if;

  select * into v_vale from plantas_vales where id = p_vale_id for update;
  v_aud_antes := plantas_auditoria_snapshot_vale(p_vale_id);
  if not found then
    raise exception 'El vale % no existe.', p_vale_id;
  end if;
  if v_vale.tipo_vale <> 'asfalto' then
    raise exception 'Solo los vales de asfalto se pueden reasignar a otro pedido.';
  end if;
  if v_vale.anulado then
    raise exception 'Este vale está anulado — no se puede reasignar.';
  end if;
  if v_vale.pedido_id is not distinct from p_pedido_id then
    raise exception 'El vale ya está asignado a ese pedido.';
  end if;

  -- Lock de los dos pedidos en orden de id (evita deadlock entre dos
  -- reasignaciones cruzadas simultáneas).
  perform 1 from plantas_pedidos
    where id in (p_pedido_id, v_vale.pedido_id)
    order by id
    for update;

  select * into v_destino from plantas_pedidos where id = p_pedido_id;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_destino.tipo <> 'asfalto' then
    raise exception 'El pedido elegido no es de asfalto.';
  end if;
  if v_destino.estado <> 'confirmado' then
    raise exception 'El pedido elegido tiene que estar confirmado (estado actual: %).', v_destino.estado;
  end if;

  if v_vale.pedido_id is not null then
    select * into v_origen from plantas_pedidos where id = v_vale.pedido_id;
    if v_origen.estado <> 'confirmado' then
      raise exception 'El pedido actual del vale ya está % — no se puede reasignar. Anulá el vale y corregí el despacho desde Pedidos.', v_origen.estado;
    end if;
    if exists (
      select 1 from plantas_cargas_asfalto
      where pedido_id = v_origen.id and btrim(numero_vale) = v_vale.numero_vale::text
    ) then
      raise exception 'El vale N° % ya figura como carga en el despacho del pedido actual (Pedidos). Corregí esa carga primero.', v_vale.numero_vale;
    end if;
  end if;

  update plantas_vales set
    pedido_id = v_destino.id,
    obra_id   = v_destino.obra_id
  where id = p_vale_id
  returning * into v_vale;

  update plantas_pedidos
    set nro_remito_global = coalesce(nro_remito_global, nextval('plantas_remitos_numero_seq')::text)
    where id = v_destino.id;

  insert into plantas_vales_historial (vale_id, accion, pedido_anterior_id, pedido_nuevo_id, antes, despues, motivo, usuario_email)
  values (
    p_vale_id, 'reasignacion', v_origen.id, v_destino.id,
    jsonb_build_object('pedido_id', v_origen.id, 'obra_id', v_origen.obra_id, 'cliente_externo', v_origen.cliente_externo),
    jsonb_build_object('pedido_id', v_destino.id, 'obra_id', v_destino.obra_id, 'cliente_externo', v_destino.cliente_externo),
    btrim(p_motivo), auth.email()
  );

  perform plantas_auditar_vale('REASIGNAR', p_vale_id, btrim(p_motivo), v_aud_antes);

  return v_vale;
end;
$function$;

-- ---------------------------------------------------------------------------
-- registrar_carga_asfalto — md5(prosrc) = 77bd9e931d40805cf17d24eb7b4b2bb5
-- ---------------------------------------------------------------------------
-- create or replace function registrar_carga_asfalto(...) ... as $function$
declare
  v_rol    text;
  v_pedido plantas_pedidos;
  v_carga  plantas_cargas_asfalto;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista') then
    raise exception 'Tu rol (%) no puede registrar cargas de asfalto.', coalesce(v_rol, 'sin rol asignado');
  end if;

  if not (p_cantidad_tn > 0) then
    raise exception 'cantidad_tn debe ser mayor a 0';
  end if;
  if p_numero_vale is null or btrim(p_numero_vale) = '' then
    raise exception 'numero_vale es obligatorio por carga';
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.tipo <> 'asfalto' then
    raise exception 'El pedido no es de asfalto.';
  end if;
  if v_pedido.estado <> 'confirmado' then
    raise exception 'El pedido tiene que estar confirmado.';
  end if;

  insert into plantas_cargas_asfalto (
    pedido_id, obra_id, numero_vale, cantidad_tn, patente, fecha_carga, observaciones
  ) values (
    v_pedido.id, v_pedido.obra_id, btrim(p_numero_vale), p_cantidad_tn, p_patente, p_fecha_carga, p_observaciones
  )
  returning * into v_carga;

  update plantas_pedidos
    set cantidad_despachada = coalesce(v_pedido.cantidad_despachada, 0) + p_cantidad_tn
    where id = p_pedido_id;

  perform plantas_auditar('CREAR', 'despachos', 'carga_asfalto', v_carga.numero_vale,
    'Carga vale ' || v_carga.numero_vale || ' — ' || plantas_auditoria_label_pedido(p_pedido_id), null, null, to_jsonb(v_carga));

  return v_carga;
end;
$function$;

-- ---------------------------------------------------------------------------
-- registrar_carga_hormigon — md5(prosrc) = 6df4fe172fc7482ca1d2146253c98fd4
-- ---------------------------------------------------------------------------
-- create or replace function registrar_carga_hormigon(...) ... as $function$
declare
  v_rol    text;
  v_pedido plantas_pedidos;
  v_carga  plantas_cargas_hormigon;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista', 'plantista_hormigon') then
    raise exception 'Tu rol (%) no puede registrar cargas de hormigón.', coalesce(v_rol, 'sin rol asignado');
  end if;

  if not (p_volumen_m3 > 0) then
    raise exception 'volumen_m3 debe ser mayor a 0';
  end if;
  if p_numero_remito is null or btrim(p_numero_remito) = '' then
    raise exception 'numero_remito es obligatorio';
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  -- Circuito "mixer" (remito por carga, sin báscula): hormigón y mezcla
  -- cemento. Gemela de src/config/tipos-producto.js.
  if v_pedido.tipo not in ('hormigon', 'mezcla_cemento') then
    raise exception 'El pedido no es de hormigón ni de mezcla cemento.';
  end if;
  if v_pedido.estado <> 'confirmado' then
    raise exception 'El pedido tiene que estar confirmado.';
  end if;

  insert into plantas_cargas_hormigon (
    pedido_id, obra_id, numero_remito, volumen_m3, patente_mixer, chofer, fecha_carga, observaciones
  ) values (
    v_pedido.id, v_pedido.obra_id, btrim(p_numero_remito), p_volumen_m3, p_patente_mixer, p_chofer, p_fecha_carga, p_observaciones
  )
  returning * into v_carga;

  update plantas_pedidos
    set cantidad_despachada = coalesce(v_pedido.cantidad_despachada, 0) + p_volumen_m3
    where id = p_pedido_id;

  perform plantas_auditar('CREAR', 'despachos', 'carga_hormigon', v_carga.numero_remito,
    'Carga remito ' || v_carga.numero_remito || ' — ' || plantas_auditoria_label_pedido(p_pedido_id), null, null, to_jsonb(v_carga));

  return v_carga;
end;
$function$;

-- ---------------------------------------------------------------------------
-- registrar_movimiento_manual — md5(prosrc) = 04bd70e093d957fe414041ff9c8fd82d
-- ---------------------------------------------------------------------------
-- create or replace function registrar_movimiento_manual(...) ... as $function$
declare
  v_mov plantas_stock_movimientos;
begin
  if not plantas_tiene_permiso('stock', 'crear') then
    raise exception 'Tu rol (%) no puede registrar movimientos manuales de stock.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;
  if p_tipo not in ('ingreso_manual', 'egreso_manual') then
    raise exception 'tipo inválido: % (esperado ingreso_manual o egreso_manual)', p_tipo;
  end if;
  if not (p_cantidad_kg > 0) then
    raise exception 'cantidad_kg debe ser mayor a 0';
  end if;
  if not exists (select 1 from plantas_materiales where id = p_material_id and controla_stock) then
    raise exception 'El material no existe o no controla stock.';
  end if;

  v_mov := plantas_aplicar_movimiento_stock(
    p_material_id,
    p_tipo,
    case when p_tipo = 'ingreso_manual' then p_cantidad_kg else -p_cantidad_kg end,
    p_origen, p_numero_remito, null, null, null, p_observaciones
  );
  perform plantas_auditar('CREAR', 'stock', 'movimiento_manual', v_mov.id::text,
    case when p_tipo = 'ingreso_manual' then 'Ingreso manual' else 'Salida manual' end
      || ' — ' || (select nombre from plantas_materiales where id = p_material_id)
      || ' — ' || replace(trim_scale(abs(v_mov.cantidad_kg))::text, '.', ',') || ' kg',
    null, null,
    to_jsonb(v_mov) || jsonb_build_object('material', (select nombre from plantas_materiales where id = p_material_id)));

  return v_mov;
end;
$function$;

-- ---------------------------------------------------------------------------
-- registrar_pesada_bascula — md5(prosrc) = b389e15cec43b26d4a60cac77db518db
-- ---------------------------------------------------------------------------
-- create or replace function registrar_pesada_bascula(...) ... as $function$
declare
  v_rol           text;
  v_pedido        plantas_pedidos;
  v_peso_neto     numeric;
  v_obra_id       bigint;
  v_neto_tn       numeric;
  v_acumulado_tn  numeric;
  v_vale          plantas_vales;
  v_ingreso_id    uuid;
  v_material_id   uuid;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista', 'balancero') then
    raise exception 'Tu rol (%) no puede registrar pesadas de báscula.', coalesce(v_rol, 'sin rol asignado');
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

  if p_pedido_id is not null then
    select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
    if not found then
      raise exception 'El pedido % no existe.', p_pedido_id;
    end if;
  end if;

  v_obra_id := coalesce(p_obra_id, v_pedido.obra_id);
  v_neto_tn := case when p_unidad = 'kg' then v_peso_neto / 1000 else v_peso_neto end;

  if p_tipo_vale = 'ingreso_arido' then
    if p_material is null or p_proveedor is null then
      raise exception 'Un ingreso de áridos necesita material y proveedor.';
    end if;
    if p_cantidad_remito is null or not (p_cantidad_remito > 0) then
      raise exception 'Un ingreso de áridos necesita la cantidad según remito (declarada por el proveedor), independiente del peso pesado.';
    end if;
    if p_numero_remito is not null and btrim(p_numero_remito) <> ''
       and exists (select 1 from plantas_ingresos where numero_remito = btrim(p_numero_remito)) then
      raise exception 'Ya existe un ingreso registrado con el remito %.', p_numero_remito;
    end if;
  end if;

  if p_tipo_vale = 'egreso_arido' then
    if p_material is null or btrim(p_material) = '' then
      raise exception 'Un egreso de áridos necesita material.';
    end if;
    if v_obra_id is null then
      raise exception 'Un egreso de áridos necesita la obra de destino.';
    end if;
  end if;

  if p_tipo_vale = 'asfalto' then
    if p_pedido_id is not null then
      select coalesce(sum(case when unidad = 'kg' then peso_neto / 1000 else peso_neto end), 0)
        into v_acumulado_tn
        from plantas_vales
        where pedido_id = p_pedido_id
          and tipo_vale = 'asfalto'
          and fecha_pesada >= date_trunc('day', p_fecha_pesada)
          and fecha_pesada <= p_fecha_pesada;

      update plantas_pedidos
        set nro_remito_global = coalesce(nro_remito_global, nextval('plantas_remitos_numero_seq')::text)
        where id = p_pedido_id;
    elsif v_obra_id is not null then
      select coalesce(sum(case when unidad = 'kg' then peso_neto / 1000 else peso_neto end), 0)
        into v_acumulado_tn
        from plantas_vales
        where obra_id = v_obra_id
          and tipo_vale = 'asfalto'
          and fecha_pesada >= date_trunc('day', p_fecha_pesada)
          and fecha_pesada <= p_fecha_pesada;
    else
      v_acumulado_tn := 0;
    end if;
    v_acumulado_tn := coalesce(v_acumulado_tn, 0) + v_neto_tn;
  end if;

  insert into plantas_vales (
    tipo_vale, numero_vale, numero_vale_arido, pedido_id, obra_id, patente, chofer,
    peso_bruto, tara, peso_neto, unidad, acumulado_obra_tn, fecha_pesada, observaciones,
    temperatura, material, responsable_email
  ) values (
    p_tipo_vale,
    case when p_tipo_vale in ('asfalto', 'hormigon') then nextval('plantas_vales_numero_vale_seq') end,
    case when p_tipo_vale in ('ingreso_arido', 'egreso_arido') then nextval('plantas_vales_numero_arido_seq') end,
    p_pedido_id, v_obra_id, p_patente, p_chofer,
    p_peso_bruto, p_tara, v_peso_neto, p_unidad, v_acumulado_tn, p_fecha_pesada, p_observaciones,
    p_temperatura,
    case when p_tipo_vale = 'egreso_arido' then p_material else null end,
    auth.email()
  )
  returning * into v_vale;

  if p_tipo_vale = 'ingreso_arido' then
    insert into plantas_ingresos (
      material, proveedor, numero_remito, cantidad, unidad, origen, vale_id, fecha_ingreso, observaciones
    ) values (
      p_material, p_proveedor, p_numero_remito, p_cantidad_remito, 'tn',
      'bascula', v_vale.id, p_fecha_pesada, p_observaciones
    )
    returning id into v_ingreso_id;

    v_material_id := plantas_buscar_material_id(p_material);
    if v_material_id is not null then
      perform plantas_aplicar_movimiento_stock(
        v_material_id, 'ingreso_proveedor', p_cantidad_remito * 1000,
        p_proveedor, p_numero_remito, null, v_vale.id, v_ingreso_id, null
      );
    end if;
  end if;

  if p_tipo_vale = 'egreso_arido' then
    v_material_id := plantas_buscar_material_id(p_material);
    if v_material_id is not null then
      perform plantas_aplicar_movimiento_stock(
        v_material_id, 'egreso_arido', -(v_neto_tn * 1000),
        null, null, null, v_vale.id, null, p_observaciones
      );
    end if;
  end if;

  perform plantas_auditar_vale('CREAR', v_vale.id);

  return v_vale;
end;
$function$;

-- ---------------------------------------------------------------------------
-- registrar_relevamiento_stock — md5(prosrc) = a832a4464a153b77e49c34a5713d2919
-- ---------------------------------------------------------------------------
-- create or replace function registrar_relevamiento_stock(...) ... as $function$
declare
  v_aud_items jsonb := '[]'::jsonb;
  v_item              jsonb;
  v_material_id       uuid;
  v_nueva             numeric;
  v_actual            numeric;
  v_total_antes       numeric := 0;
  v_total_despues     numeric := 0;
  v_con_valor_antes   int := 0;
  v_con_valor_despues int := 0;
  v_mov               plantas_stock_movimientos;
begin
  if not plantas_tiene_permiso('stock', 'editar') then
    raise exception 'Tu rol (%) no puede cargar un relevamiento de stock.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  select coalesce(sum(cantidad_kg), 0), count(*) filter (where cantidad_kg > 0)
    into v_total_antes, v_con_valor_antes
    from plantas_stock;

  v_total_despues := v_total_antes;
  v_con_valor_despues := v_con_valor_antes;

  for v_item in select * from jsonb_array_elements(p_conteos)
  loop
    v_material_id := (v_item->>'material_id')::uuid;
    v_nueva := (v_item->>'cantidad_kg')::numeric;
    if v_nueva is null or v_nueva < 0 then
      raise exception 'cantidad_kg inválida para el material % (no puede ser negativa).', v_material_id;
    end if;

    select cantidad_kg into v_actual from plantas_stock where material_id = v_material_id;
    v_actual := coalesce(v_actual, 0);

    v_total_despues := v_total_despues - v_actual + v_nueva;
    if v_actual > 0 and v_nueva = 0 then v_con_valor_despues := v_con_valor_despues - 1; end if;
    if v_actual = 0 and v_nueva > 0 then v_con_valor_despues := v_con_valor_despues + 1; end if;
  end loop;

  if v_con_valor_antes > 0 and v_con_valor_despues < (v_con_valor_antes * 0.5) then
    raise exception 'saveStockGuard: el relevamiento deja sin stock a más de la mitad de los materiales que hoy tienen valor (% -> %). Guardado cancelado — revisá los conteos.',
      v_con_valor_antes, v_con_valor_despues;
  end if;
  if v_total_antes > 0 and v_total_despues < (v_total_antes * 0.1) then
    raise exception 'saveStockGuard: el relevamiento hace caer el stock total más de un 90%% (% kg -> % kg). Guardado cancelado — revisá los conteos.',
      v_total_antes, v_total_despues;
  end if;

  for v_item in select * from jsonb_array_elements(p_conteos)
  loop
    v_material_id := (v_item->>'material_id')::uuid;
    v_nueva := (v_item->>'cantidad_kg')::numeric;
    select cantidad_kg into v_actual from plantas_stock where material_id = v_material_id;
    v_actual := coalesce(v_actual, 0);

    if v_nueva <> v_actual then
      v_mov := plantas_aplicar_movimiento_stock(v_material_id, 'ajuste', v_nueva - v_actual, p_motivo, null, null, null, null, null);
      return next v_mov;
      v_aud_items := v_aud_items || jsonb_build_object(
        'material', (select nombre from plantas_materiales where id = v_material_id),
        'antes_kg', round(v_actual, 2), 'despues_kg', round(v_nueva, 2), 'ajuste_kg', round(v_mov.cantidad_kg, 2));
    end if;
  end loop;

  if jsonb_array_length(v_aud_items) > 0 then
    perform plantas_auditar('CREAR', 'stock', 'relevamiento',
      to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD HH24:MI:SS'),
      'Relevamiento de stock — ' || jsonb_array_length(v_aud_items) || ' material(es) ajustado(s)',
      nullif(btrim(p_motivo), ''), null, jsonb_build_object('ajustes', v_aud_items));
  end if;

  return;
end;
$function$;
