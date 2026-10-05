-- ============================================================================
-- Dry-run de la etapa 3 de Auditoría (migraciones 54 a 59) contra producción.
-- Termina SIEMPRE con raise exception: no persiste nada.
-- Las secuencias no se revierten con el rollback, así que se bloquean las
-- tablas que las consumen (nadie más puede pedir números mientras dura) y al
-- final se devuelven al valor que tenían.
-- ============================================================================
do $dry$
declare
  v_admin text; v_plantista text; v_balancero text;
  v_fa uuid; v_fh uuid; v_obra bigint; v_mat uuid; v_matn text; v_prov text; v_kg numeric;
  v_p1 uuid; v_p2 uuid; v_p3 uuid; v_p4 uuid; v_res uuid; v_vale uuid;
  v_n int; v_m int; v_txt text; v_ok text := '';
  s1 bigint; c1 boolean; s2 bigint; c2 boolean; s3 bigint; c3 boolean; s4 bigint; c4 boolean; s5 bigint; c5 boolean;
begin
  lock table plantas_pedidos, plantas_vales, plantas_remitos_manuales, plantas_auditoria in share row exclusive mode;
  select last_value, is_called into s1, c1 from plantas_vales_numero_vale_seq;
  select last_value, is_called into s2, c2 from plantas_vales_numero_arido_seq;
  select last_value, is_called into s3, c3 from plantas_remitos_numero_seq;
  select last_value, is_called into s4, c4 from plantas_pedidos_numero_seq;
  select last_value, is_called into s5, c5 from plantas_auditoria_id_seq;

  select email into v_admin from plantas_usuarios_roles where rol = 'admin' and activo limit 1;
  select email into v_plantista from plantas_usuarios_roles where rol = 'plantista' and activo order by email limit 1;
  select email into v_balancero from plantas_usuarios_roles where rol = 'balancero' and activo order by email limit 1;
  select id into v_fa from plantas_formulas where activo and tipo = 'asfalto' order by nombre limit 1;
  select id into v_fh from plantas_formulas where activo and tipo = 'hormigon' order by nombre limit 1;
  select id into v_obra from flota_obras order by id limit 1;
  select m.id, m.nombre, s.cantidad_kg into v_mat, v_matn, v_kg
    from plantas_materiales m join plantas_stock s on s.material_id = m.id
   where m.controla_stock and m.activo order by s.cantidad_kg desc limit 1;
  select nombre into v_prov from plantas_proveedores order by nombre limit 1;

  execute $m54$
create function plantas_auditoria_label_pedido(p_pedido_id uuid)
returns text
language sql
stable
set search_path to 'public'
as $fn$
  select plantas_etiqueta_pedido(p.numero)
    || ' — ' || case when p.tipo_pedido = 'venta'
                     then coalesce(nullif(btrim(p.cliente_externo), ''), 'Venta externa')
                     else coalesce((select o.nombre from flota_obras o where o.id = p.obra_id), 'Obra sin asignar') end
    || ' — ' || replace(trim_scale(p.cantidad_solicitada)::text, '.', ',')
    || case when p.tipo = 'hormigon' then ' m³' else ' tn' end
    || ' — ' || to_char(p.fecha_programada, 'DD/MM/YYYY')
  from plantas_pedidos p
  where p.id = p_pedido_id
$fn$;

create function plantas_auditar_pedido(
  p_tipo_accion text, p_entidad text, p_pedido_id uuid, p_motivo text default null, p_antes jsonb default null
)
returns void
language plpgsql
set search_path to 'public'
as $fn$
declare
  v_p plantas_pedidos;
begin
  select * into v_p from plantas_pedidos where id = p_pedido_id;
  perform plantas_auditar(
    p_tipo_accion,
    case when p_entidad = 'despacho' then 'despachos' else 'pedidos' end,
    p_entidad,
    plantas_etiqueta_pedido(v_p.numero),
    plantas_auditoria_label_pedido(p_pedido_id),
    p_motivo, p_antes, to_jsonb(v_p)
  );
end;
$fn$;

create function plantas_auditoria_snapshot_vale(p_vale_id uuid)
returns jsonb
language sql
stable
set search_path to 'public'
as $fn$
  select to_jsonb(v)
    || jsonb_build_object('pedido', (select plantas_etiqueta_pedido(p.numero) from plantas_pedidos p where p.id = v.pedido_id))
    || coalesce((
         select jsonb_build_object('material', i.material, 'proveedor', i.proveedor,
                                   'numero_remito', i.numero_remito, 'cantidad_remito', i.cantidad)
           from plantas_ingresos i where i.vale_id = v.id limit 1
       ), '{}'::jsonb)
  from plantas_vales v
  where v.id = p_vale_id
$fn$;

create function plantas_auditoria_label_vale(p_vale_id uuid)
returns text
language sql
stable
set search_path to 'public'
as $fn$
  select 'Vale ' || plantas_etiqueta_vale(v)
    || coalesce(' — ' || (select plantas_etiqueta_pedido(p.numero) from plantas_pedidos p where p.id = v.pedido_id), '')
    || coalesce(' — ' || (select o.nombre from flota_obras o where o.id = v.obra_id), '')
    || coalesce(' — ' || (select i.material || ' de ' || i.proveedor from plantas_ingresos i where i.vale_id = v.id limit 1), '')
    || coalesce(' — ' || nullif(btrim(v.material), ''), '')
    || ' — ' || replace(trim_scale(v.peso_neto)::text, '.', ',') || ' ' || coalesce(v.unidad, 'tn')
  from plantas_vales v
  where v.id = p_vale_id
$fn$;

create function plantas_auditar_vale(
  p_tipo_accion text, p_vale_id uuid, p_motivo text default null, p_antes jsonb default null
)
returns void
language plpgsql
set search_path to 'public'
as $fn$
declare
  v_v plantas_vales;
begin
  select * into v_v from plantas_vales where id = p_vale_id;
  perform plantas_auditar(
    p_tipo_accion, 'bascula', 'vale',
    plantas_etiqueta_vale(v_v),
    plantas_auditoria_label_vale(p_vale_id),
    p_motivo, p_antes, plantas_auditoria_snapshot_vale(p_vale_id)
  );
end;
$fn$;

revoke execute on function plantas_auditoria_label_pedido(uuid) from public, anon, authenticated;
revoke execute on function plantas_auditar_pedido(text, text, uuid, text, jsonb) from public, anon, authenticated;
revoke execute on function plantas_auditoria_snapshot_vale(uuid) from public, anon, authenticated;
revoke execute on function plantas_auditoria_label_vale(uuid) from public, anon, authenticated;
revoke execute on function plantas_auditar_vale(text, uuid, text, jsonb) from public, anon, authenticated;

create function plantas__auditoria_patch(p_fn text, p_md5_antes text, p_md5_despues text, variadic p_pares text[])
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
  execute replace(v_def, v_src, v_nuevo);
end;
$pf$;

revoke execute on function plantas__auditoria_patch(text, text, text, text[]) from public, anon, authenticated;
$m54$;
  execute $m55$
select plantas__auditoria_patch('crear_pedido', 'eae64ae761b28b0b0e8823451cb6593f', '2a889ac9e31ff839242613358156b6ac',
  $a$
  return v_pedido;
end;$a$,
  $b$
  perform plantas_auditar_pedido('CREAR', 'pedido', v_pedido.id);

  return v_pedido;
end;$b$
);

select plantas__auditoria_patch('actualizar_pedido', 'a8bf0e730198faea63670a487cfcafb1', '839f708da9194edf5237b726014fe5a4',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
$a$,
  $b$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
$b$,
  $a$
  return v_pedido;
end;$a$,
  $b$
  perform plantas_auditar_pedido('EDITAR', 'pedido', p_pedido_id, null, v_aud_antes);

  return v_pedido;
end;$b$
);

select plantas__auditoria_patch('confirmar_pedido', '12275ebd05d0690e55146ab5adc9f122', 'b540acb86b43464f2ece54848b347a2b',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
$a$,
  $b$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
$b$,
  $a$
  return v_pedido;
end;$a$,
  $b$
  perform plantas_auditar_pedido('CAMBIAR_ESTADO', 'pedido', p_pedido_id, null, v_aud_antes);

  return v_pedido;
end;$b$
);

select plantas__auditoria_patch('cancelar_pedido', 'e56ec2b71046cd109a9b2b7dfeb61106', '14876c763a228e876db74a13c7e6ecbe',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
$a$,
  $b$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
$b$,
  $a$
  return v_pedido;
end;$a$,
  $b$
  perform plantas_auditar_pedido('ANULAR', 'pedido', p_pedido_id, p_motivo, v_aud_antes);

  return v_pedido;
end;$b$
);

select plantas__auditoria_patch('postergar_pedido', '2ad6b0fac6146b765694fcc0e79ac57e', 'd6cdb4cb9d42e2bfd22b9fb2677fa2b0',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
$a$,
  $b$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
$b$,
  $a$
  return v_pedido;
end;$a$,
  $b$
  perform plantas_auditar_pedido('CAMBIAR_ESTADO', 'pedido', p_pedido_id, p_motivo, v_aud_antes);

  return v_pedido;
end;$b$
);

select plantas__auditoria_patch('archivar_pedido', 'a5a4e7a0dc4f38e0638a01d082ea7290', '1be71fa1d9cdcebf5bdc97d1a2fd3dd4',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
$a$,
  $b$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
$b$,
  $a$
  return v_pedido;
end;$a$,
  $b$
  perform plantas_auditar_pedido('CAMBIAR_ESTADO', 'pedido', p_pedido_id, null, v_aud_antes);

  return v_pedido;
end;$b$
);

select plantas__auditoria_patch('finalizar_despacho', 'cf059c246454edbcd20f741d43179490', '1ad19320c736f42b3eba6139518d0531',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
$a$,
  $b$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
$b$,
  $a$      values (v_nuevo_id, 'confirmado', now(), auth.uid(), 'Residual del ' || v_ref);
$a$,
  $b$      values (v_nuevo_id, 'confirmado', now(), auth.uid(), 'Residual del ' || v_ref);

      perform plantas_auditar_pedido('CREAR', 'pedido', v_nuevo_id);
$b$,
  $a$
  return v_pedido;
end;$a$,
  $b$
  perform plantas_auditar_pedido('CAMBIAR_ESTADO', 'despacho', p_pedido_id, null, v_aud_antes);

  return v_pedido;
end;$b$
);

select plantas__auditoria_patch('corregir_despacho', '30b57f36ff6389df2e292a8683f22fde', '97902d48adcf29fb287572e652cd5465',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
$a$,
  $b$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
$b$,
  $a$
  return v_pedido;
end;$a$,
  $b$
  perform plantas_auditar_pedido(case when nullif(btrim(p_notas), '') is null then 'EDITAR' else 'CORREGIR' end, 'despacho', p_pedido_id, p_notas, v_aud_antes);

  return v_pedido;
end;$b$
);

select plantas__auditoria_patch('registrar_carga_asfalto', 'f2bd756f1b67a3be0ddccea18fc39c35', '77bd9e931d40805cf17d24eb7b4b2bb5',
  $a$
  return v_carga;
end;$a$,
  $b$
  perform plantas_auditar('CREAR', 'despachos', 'carga_asfalto', v_carga.numero_vale,
    'Carga vale ' || v_carga.numero_vale || ' — ' || plantas_auditoria_label_pedido(p_pedido_id), null, null, to_jsonb(v_carga));

  return v_carga;
end;$b$
);

select plantas__auditoria_patch('registrar_carga_hormigon', '527a8ec5e0b36ac3064277010a5b4ada', '6df4fe172fc7482ca1d2146253c98fd4',
  $a$
  return v_carga;
end;$a$,
  $b$
  perform plantas_auditar('CREAR', 'despachos', 'carga_hormigon', v_carga.numero_remito,
    'Carga remito ' || v_carga.numero_remito || ' — ' || plantas_auditoria_label_pedido(p_pedido_id), null, null, to_jsonb(v_carga));

  return v_carga;
end;$b$
);

do $chk$
declare
  v_mal text;
begin
  select string_agg(p.proname, ', ') into v_mal
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('crear_pedido', 'actualizar_pedido', 'confirmar_pedido', 'cancelar_pedido', 'postergar_pedido', 'archivar_pedido', 'finalizar_despacho', 'corregir_despacho', 'registrar_carga_asfalto', 'registrar_carga_hormigon')
     and (has_function_privilege('anon', p.oid, 'execute')
          or not has_function_privilege('authenticated', p.oid, 'execute')
          or not p.prosecdef);
  if v_mal is not null then
    raise exception 'MIG55: permisos alterados en: %', v_mal;
  end if;
end;
$chk$;
$m55$;
  execute $m56$
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
$m56$;
  execute $m57$
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
$m57$;
  execute $m58$
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
$m58$;
  execute $m59$
select plantas__auditoria_patch('admin_upsert_usuario_rol', 'bf5f8e3b8672f9a98920498bdbeb0f46', '98b8b67129aacc86c57b3fe87a7d9bdf',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  insert into plantas_usuarios_roles (email, rol, ver_todas_obras, ver_ventas, obra_ids, activo)
$a$,
  $b$  select to_jsonb(u) into v_aud_antes from plantas_usuarios_roles u where u.email = lower(trim(p_email));

  insert into plantas_usuarios_roles (email, rol, ver_todas_obras, ver_ventas, obra_ids, activo)
$b$,
  $a$
  return v_resultado;
end;$a$,
  $b$
  perform plantas_auditar(case when v_aud_antes is null then 'CREAR' else 'EDITAR' end, 'usuarios', 'usuario_rol',
    v_resultado.email, v_resultado.email || ' — ' || v_resultado.rol, null, v_aud_antes, to_jsonb(v_resultado));

  return v_resultado;
end;$b$
);

drop function plantas__auditoria_patch(text, text, text, text[]);

do $chk$
declare
  v_mal text;
begin
  select string_agg(p.proname, ', ') into v_mal
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('admin_upsert_usuario_rol')
     and (has_function_privilege('anon', p.oid, 'execute')
          or not has_function_privilege('authenticated', p.oid, 'execute')
          or not p.prosecdef);
  if v_mal is not null then
    raise exception 'MIG59: permisos alterados en: %', v_mal;
  end if;
end;
$chk$;
$m59$;

  execute $h$
    create function public.dry3_como(p_email text) returns void language sql as $f$
      select set_config('request.jwt.claims', json_build_object('email', p_email,
        'sub', (select id from auth.users where lower(email) = lower(p_email)), 'role', 'authenticated')::text, true);
    $f$;
    create function public.dry3_ultimo(p_accion text, p_entidad text, p_rol text, p_ref_like text default '%')
    returns text language plpgsql set search_path to 'public' as $f$
    declare r plantas_auditoria;
    begin
      select * into r from plantas_auditoria order by id desc limit 1;
      if r.id is null or r.tipo_accion <> p_accion or r.entidad <> p_entidad
         or coalesce(r.usuario_rol, '') <> p_rol or r.entidad_ref not like p_ref_like then
        raise exception 'DRY FALLA: esperaba % % (rol %, ref %), ultimo registro: %',
          p_accion, p_entidad, p_rol, p_ref_like, coalesce(row_to_json(r)::text, 'ninguno');
      end if;
      return r.tipo_accion || ' ' || r.entidad || ' ' || r.entidad_ref;
    end $f$;
  $h$;

  -- ===== PEDIDOS =====
  perform dry3_como(v_admin);
  execute 'set local role authenticated';
  select id into v_p1 from crear_pedido(v_fa, 10, current_date, v_obra);
  execute 'reset role';
  perform dry3_ultimo('CREAR', 'pedido', 'admin', 'P-%');
  select entidad_label into v_txt from plantas_auditoria order by id desc limit 1;
  v_ok := v_ok || 'PEDIDOS: crear OK [' || v_txt || ']';

  perform actualizar_pedido(v_p1, v_fa, 12, current_date, v_obra, 'obra', null, 'Encargado prueba', null, 'obs prueba');
  perform dry3_ultimo('EDITAR', 'pedido', 'admin');
  select valores_antes::text || ' -> ' || valores_despues::text into v_txt from plantas_auditoria order by id desc limit 1;
  v_ok := v_ok || '; editar OK ' || v_txt;
  select count(*) into v_n from plantas_auditoria;
  perform actualizar_pedido(v_p1, v_fa, 12, current_date, v_obra, 'obra', null, 'Encargado prueba', null, 'obs prueba');
  select count(*) into v_m from plantas_auditoria;
  if v_m <> v_n then raise exception 'DRY FALLA: editar sin cambios dejo fila'; end if;
  v_ok := v_ok || '; editar sin cambios no registra';

  perform postergar_pedido(v_p1, current_date + 1, 'lluvia');
  perform dry3_ultimo('CAMBIAR_ESTADO', 'pedido', 'admin');
  select motivo into v_txt from plantas_auditoria order by id desc limit 1;
  if v_txt <> 'lluvia' then raise exception 'DRY FALLA: motivo de postergar %', v_txt; end if;
  v_ok := v_ok || '; postergar OK (motivo y fechas)';

  perform dry3_como(v_plantista);
  perform confirmar_pedido(v_p1, null, null);
  perform dry3_ultimo('CAMBIAR_ESTADO', 'pedido', 'plantista');
  select usuario_nombre || ' / ' || usuario_rol into v_txt from plantas_auditoria order by id desc limit 1;
  v_ok := v_ok || '; confirmar como plantista OK [' || v_txt || ']';

  perform dry3_como(v_admin);
  select id into v_p2 from crear_pedido(v_fa, 5, current_date, v_obra);
  perform cancelar_pedido(v_p2, 'duplicado', null);
  perform dry3_ultimo('ANULAR', 'pedido', 'admin');
  perform archivar_pedido(v_p2);
  perform dry3_ultimo('CAMBIAR_ESTADO', 'pedido', 'admin');
  select valores_despues::text into v_txt from plantas_auditoria order by id desc limit 1;
  v_ok := v_ok || '; cancelar (ANULAR con motivo) y archivar OK ' || v_txt;

  -- si la auditoría no puede registrar, la operación no se hace
  select count(*) into v_n from plantas_pedidos;
  v_txt := 'no fallo';
  begin
    alter table plantas_auditoria add constraint dry3_falla check (false) not valid;
    perform crear_pedido(v_fa, 1, current_date, v_obra);
  exception when check_violation then v_txt := 'fallo';
  end;
  select count(*) into v_m from plantas_pedidos;
  if v_txt <> 'fallo' or v_m <> v_n then raise exception 'DRY FALLA: atomicidad (%, % -> %)', v_txt, v_n, v_m; end if;
  v_ok := v_ok || '; si la auditoria falla el pedido no se crea';

  -- ===== DESPACHOS =====
  perform registrar_carga_asfalto(v_p1, '99999', 6, 'AAA111', now(), null);
  perform dry3_ultimo('CREAR', 'carga_asfalto', 'admin', '99999');
  perform finalizar_despacho(v_p1, true, current_date + 2);
  perform dry3_ultimo('CAMBIAR_ESTADO', 'despacho', 'admin');
  select tipo_accion || ' ' || entidad || ' ' || entidad_ref into v_txt from plantas_auditoria order by id desc offset 1 limit 1;
  if v_txt not like 'CREAR pedido P-%' then raise exception 'DRY FALLA: residual sin auditar (%)', v_txt; end if;
  select id into v_res from plantas_pedidos order by numero desc limit 1;
  v_ok := v_ok || ' || DESPACHOS: carga asfalto OK; finalizar OK + residual [' || v_txt || ']';
  perform corregir_despacho(v_p1, 7, null, null, 'error de tipeo');
  perform dry3_ultimo('CORREGIR', 'despacho', 'admin');
  select valores_antes::text || ' -> ' || valores_despues::text into v_txt from plantas_auditoria order by id desc limit 1;
  perform corregir_despacho(v_p1, 6.5, null, null, null);
  perform dry3_ultimo('EDITAR', 'despacho', 'admin');
  v_ok := v_ok || '; corregir con notas = CORREGIR ' || v_txt || ', sin notas = EDITAR';
  select id into v_p3 from crear_pedido(v_fh, 8, current_date, v_obra);
  perform confirmar_pedido(v_p3, null, null);
  perform registrar_carga_hormigon(v_p3, 'R-DRY-1', 5, 'MIX111', 'Chofer', now(), null);
  perform dry3_ultimo('CREAR', 'carga_hormigon', 'admin', 'R-DRY-1');
  select entidad_label into v_txt from plantas_auditoria order by id desc limit 1;
  v_ok := v_ok || '; carga mixer OK [' || v_txt || ']';

  -- ===== BASCULA =====
  perform dry3_como(v_balancero);
  select id into v_vale from registrar_pesada_bascula('asfalto', 40, 15, v_res, null, 'AAA111', 'Chofer prueba', 'tn', null, now(), null, null, null, null, 150);
  perform dry3_ultimo('CREAR', 'vale', 'balancero');
  select entidad_label || ' / ' || usuario_nombre into v_txt from plantas_auditoria order by id desc limit 1;
  v_ok := v_ok || ' || BASCULA: pesada como balancero OK [' || v_txt || ']';
  perform corregir_vale_bascula(v_vale, 41, 15, null, null, null, 150, null, null, null, null);
  perform dry3_ultimo('EDITAR', 'vale', 'balancero');
  select valores_antes::text || ' -> ' || valores_despues::text into v_txt from plantas_auditoria order by id desc limit 1;
  v_ok := v_ok || '; editar vale OK ' || v_txt;
  perform dry3_como(v_admin);
  select id into v_p4 from crear_pedido(v_fa, 20, current_date, v_obra);
  perform confirmar_pedido(v_p4, null, null);
  perform reasignar_vale_bascula(v_vale, v_p4, 'mal pedido');
  perform dry3_ultimo('REASIGNAR', 'vale', 'admin');
  select (valores_antes->>'pedido') || ' -> ' || (valores_despues->>'pedido') into v_txt from plantas_auditoria order by id desc limit 1;
  if v_txt is null then raise exception 'DRY FALLA: reasignar sin pedido antes/despues'; end if;
  v_ok := v_ok || '; reasignar OK (' || v_txt || ')';
  perform anular_vale_bascula(v_vale, 'prueba de anulacion');
  perform dry3_ultimo('ANULAR', 'vale', 'admin');
  perform registrar_pesada_bascula('ingreso_arido', 45, 15, null, null, 'BBB222', null, 'tn', null, now(), v_matn, v_prov, 'DRY-REM-54', 29.5, null);
  perform dry3_ultimo('CREAR', 'vale', 'admin', 'I-%');
  select entidad_label into v_txt from plantas_auditoria order by id desc limit 1;
  select count(*) into v_n from plantas_auditoria
   where id = (select max(id) from plantas_auditoria)
     and valores_despues ? 'proveedor' and (valores_despues->>'cantidad_remito')::numeric = 29.5;
  if v_n <> 1 then raise exception 'DRY FALLA: el vale de ingreso no trae los datos del ingreso'; end if;
  v_ok := v_ok || '; anular OK; ingreso de aridos con datos del ingreso OK [' || v_txt || ']';

  -- ===== STOCK =====
  perform registrar_movimiento_manual(v_mat, 'ingreso_manual', 1000, 'prueba', null, 'obs');
  perform dry3_ultimo('CREAR', 'movimiento_manual', 'admin');
  select entidad_label into v_txt from plantas_auditoria order by id desc limit 1;
  v_ok := v_ok || ' || STOCK: movimiento manual OK [' || v_txt || ']';
  select cantidad_kg into v_kg from plantas_stock where material_id = v_mat;
  perform registrar_relevamiento_stock(jsonb_build_array(jsonb_build_object('material_id', v_mat, 'cantidad_kg', v_kg + 500)), 'conteo mensual');
  perform dry3_ultimo('CREAR', 'relevamiento', 'admin');
  select entidad_label || ' ' || (valores_despues->'ajustes')::text into v_txt from plantas_auditoria order by id desc limit 1;
  select count(*) into v_n from plantas_auditoria;
  perform registrar_relevamiento_stock(jsonb_build_array(jsonb_build_object('material_id', v_mat, 'cantidad_kg', v_kg + 500)), 'conteo mensual');
  select count(*) into v_m from plantas_auditoria;
  if v_m <> v_n then raise exception 'DRY FALLA: relevamiento sin ajustes dejo fila'; end if;
  v_ok := v_ok || '; relevamiento OK [' || v_txt || ']; sin ajustes no registra';

  -- ===== REMITOS =====
  perform generar_remito_manual('[{"cantidad": 2, "unidad": "Unidades", "descripcion": "Palets"}]'::jsonb, 'Destino prueba', 'AAA111', 'Transportista', current_date);
  perform dry3_ultimo('CREAR', 'remito_manual', 'admin');
  select entidad_label into v_txt from plantas_auditoria order by id desc limit 1;
  v_ok := v_ok || ' || REMITOS: remito manual OK [' || v_txt || ']';

  -- ===== USUARIOS =====
  perform admin_upsert_usuario_rol('dryrun-auditoria@vialtec.com.ar', 'encargado', false, false, '{}', true);
  perform dry3_ultimo('CREAR', 'usuario_rol', 'admin', 'dryrun-auditoria@vialtec.com.ar');
  perform admin_upsert_usuario_rol('dryrun-auditoria@vialtec.com.ar', 'supervisor', false, false, '{}', true);
  perform dry3_ultimo('EDITAR', 'usuario_rol', 'admin');
  select valores_antes::text || ' -> ' || valores_despues::text into v_txt from plantas_auditoria order by id desc limit 1;
  select count(*) into v_n from plantas_auditoria;
  perform admin_upsert_usuario_rol('dryrun-auditoria@vialtec.com.ar', 'supervisor', false, false, '{}', true);
  select count(*) into v_m from plantas_auditoria;
  if v_m <> v_n then raise exception 'DRY FALLA: usuario sin cambios dejo fila'; end if;
  v_ok := v_ok || ' || USUARIOS: alta OK; cambio de rol OK ' || v_txt || '; sin cambios no registra';

  -- ===== GENERAL =====
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosrc like '%plantas_auditar%'
     and p.proname in ('crear_pedido','actualizar_pedido','confirmar_pedido','cancelar_pedido','postergar_pedido','archivar_pedido','finalizar_despacho','corregir_despacho','registrar_carga_asfalto','registrar_carga_hormigon','registrar_pesada_bascula','corregir_vale_bascula','anular_vale_bascula','reasignar_vale_bascula','registrar_movimiento_manual','registrar_relevamiento_stock','generar_remito_manual','admin_upsert_usuario_rol')
     and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute');
  if v_n <> 18 then raise exception 'DRY FALLA: % de 18 funciones auditan con permisos correctos', v_n; end if;
  select count(*) into v_m from plantas_auditoria;
  v_ok := v_ok || ' || GENERAL: 18 de 18 funciones auditan y conservan permisos; ' || v_m || ' filas de auditoria en el ensayo';

  perform setval('plantas_vales_numero_vale_seq', s1, c1);
  perform setval('plantas_vales_numero_arido_seq', s2, c2);
  perform setval('plantas_remitos_numero_seq', s3, c3);
  perform setval('plantas_pedidos_numero_seq', s4, c4);
  perform setval('plantas_auditoria_id_seq', s5, c5);

  raise exception 'DRYRUN ETAPA 3 OK — %', v_ok;
end;
$dry$;
