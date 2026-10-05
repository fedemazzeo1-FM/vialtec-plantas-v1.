-- ============================================================================
-- Migración 54: módulo de Auditoría, etapa 3 — helpers de etiqueta y registro
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Funciones internas que usan las RPC auditadas (migraciones 55 a 59). No
-- cambian ningún comportamiento por sí solas. Ninguna tiene EXECUTE para
-- anon/authenticated: solo corren dentro de las RPC SECURITY DEFINER.
--   - plantas_auditoria_label_pedido(id): "P-0230 — Obra — 160 tn — 05/10/2026"
--   - plantas_auditar_pedido(accion, entidad, id, motivo, antes): registra
--     sobre la entidad 'pedido' o 'despacho' con el estado actual del pedido.
--   - plantas_auditoria_snapshot_vale(id): el vale + N° de pedido + datos del
--     ingreso de áridos (material, proveedor, remito, cantidad s/remito).
--   - plantas_auditoria_label_vale(id): "Vale 10188 — P-0229 — Obra — 31,5 tn"
--   - plantas_auditar_vale(accion, id, motivo, antes).
-- Solo lectura sobre flota_obras (nombre de la obra).
--
-- También crea plantas__auditoria_patch, la herramienta temporal que usan las
-- migraciones 55 a 59 para recrear cada RPC desde su definición real; la
-- borra la 59.
--
-- Reversión: drop de las 5 funciones (después de revertir 55 a 59).
-- ============================================================================

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
