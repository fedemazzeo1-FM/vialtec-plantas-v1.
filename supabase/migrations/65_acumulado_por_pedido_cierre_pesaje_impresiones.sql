-- ============================================================================
-- Migración 65: acumulado de asfalto por pedido, cierre del pesaje e
-- impresiones auditadas
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Pedido de Federico (2026-10-20). En los trabajos nocturnos (P-0230 del
-- 05/10, P-0233 del 06/10) el acumulado del día se reiniciaba a las 00:00 y
-- el vale/remito impreso después de medianoche salía con una cantidad
-- parcial. Además había tres cortes distintos: la impresión y la vista a las
-- 00:00 de Argentina, y el valor guardado al pesar a las 00:00 UTC (21:00 de
-- Argentina).
--
--   1. Acumulado de asfalto POR PEDIDO, sin corte de fecha y sin vales
--      anulados (helper plantas_acumulado_asfalto, el mismo en la pesada, la
--      vista y la impresión). Vale sin pedido: por obra y día de Argentina.
--      El residual de un despacho dividido es otro pedido: acumula lo suyo
--      (mantiene el mismo N° de remito, como hoy — decisión de Federico).
--   2. Cierre del pesaje: plantas_pedidos.pesaje_cerrado_en/_por +
--      cerrar_pesaje_pedido (balancero, plantista, admin) y
--      reabrir_pesaje_pedido (plantista, admin, motivo obligatorio). Con el
--      pesaje cerrado el pedido no admite más pesadas. El despacho se sigue
--      finalizando en Pedidos (finalizar_despacho no cambia).
--   3. registrar_pesada_bascula y reasignar_vale_bascula rechazan un pedido
--      que no esté confirmado o que tenga el pesaje cerrado (hasta ahora la
--      pesada no miraba el estado: solo la pantalla filtraba).
--   4. Impresiones auditadas: acción IMPRIMIR, entidad bascula/impresion,
--      registrar_impresion (la base calcula lo que se imprime: cantidad,
--      vales, N° de remito, y si es reimpresión qué cambió) e
--      impresiones_del_vale (para avisar al editar/anular un vale que ya
--      salió impreso).
--
-- No cambia ningún dato existente: los vales viejos conservan su
-- acumulado_obra_tn guardado (foto al pesar, solo informativa) y la vista lo
-- recalcula en vivo.
--
-- Reversión: supabase/scripts/revertir_migracion_65.sql (vuelve a los
-- cuerpos previos de registrar_pesada_bascula, reasignar_vale_bascula y la
-- vista, y borra lo nuevo).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) Guarda: las funciones y la vista que se reemplazan tienen que ser las
--    versiones relevadas en producción el 2026-10-20.
-- ----------------------------------------------------------------------------
do $guarda$
begin
  if md5(pg_get_functiondef('public.registrar_pesada_bascula(text,numeric,numeric,uuid,bigint,text,text,text,text,timestamptz,text,text,text,numeric,numeric)'::regprocedure))
     <> 'ea415bd5c11647c49e14ecfdfdc375e7' then
    raise exception 'MIG65: registrar_pesada_bascula no es la versión esperada';
  end if;
  if md5(pg_get_functiondef('public.reasignar_vale_bascula(uuid,uuid,text)'::regprocedure))
     <> '4ccf10c413035b29ba6a5e45156481b4' then
    raise exception 'MIG65: reasignar_vale_bascula no es la versión esperada';
  end if;
  if md5(pg_get_viewdef('public.plantas_v_bascula_viva'::regclass)) <> 'c667297176f14623006913ce4b242334' then
    raise exception 'MIG65: plantas_v_bascula_viva no es la versión esperada';
  end if;
end;
$guarda$;

-- ----------------------------------------------------------------------------
-- 1) Columnas del cierre del pesaje
-- ----------------------------------------------------------------------------
alter table public.plantas_pedidos
  add column pesaje_cerrado_en timestamptz,
  add column pesaje_cerrado_por text,
  add constraint plantas_pedidos_pesaje_cerrado_chk
    check ((pesaje_cerrado_en is null) = (pesaje_cerrado_por is null));

comment on column public.plantas_pedidos.pesaje_cerrado_en is
  'Cuándo se contestó "Sí, se terminó" en Báscula (cerrar_pesaje_pedido). Con valor, el pedido no admite más pesadas. Null = abierto.';
comment on column public.plantas_pedidos.pesaje_cerrado_por is
  'Email de quien cerró el pesaje.';

-- ----------------------------------------------------------------------------
-- 2) Helper: acumulado de asfalto hasta un momento dado
--    Con pedido: todos sus vales no anulados, sin corte de fecha.
--    Sin pedido: los vales sin pedido de la misma obra, del mismo día de
--    Argentina. Interno (sin EXECUTE para anon/authenticated).
-- ----------------------------------------------------------------------------
create function public.plantas_acumulado_asfalto(p_pedido_id uuid, p_obra_id bigint, p_hasta timestamptz)
returns jsonb
language sql
stable
set search_path to 'public'
as $fn$
  select jsonb_build_object(
    'tn', coalesce(sum(case when v.unidad = 'kg' then v.peso_neto / 1000 else v.peso_neto end), 0),
    'vales', coalesce(jsonb_agg(v.numero_vale order by v.numero_vale) filter (where v.numero_vale is not null), '[]'::jsonb)
  )
  from plantas_vales v
  where v.tipo_vale = 'asfalto'
    and not v.anulado
    and v.fecha_pesada <= p_hasta
    and case
      when p_pedido_id is not null then v.pedido_id = p_pedido_id
      else v.pedido_id is null
        and v.obra_id is not distinct from p_obra_id
        and v.fecha_pesada >= (((p_hasta at time zone 'America/Argentina/Buenos_Aires')::date)::timestamp
                               at time zone 'America/Argentina/Buenos_Aires')
    end
$fn$;

comment on function public.plantas_acumulado_asfalto(uuid, bigint, timestamptz) is
  'Acumulado de asfalto (tn + N° de vales) hasta p_hasta: por pedido sin corte de fecha; sin pedido, por obra y día de Argentina. Sin anulados. Única regla para pesada, vista e impresión (migración 65).';

revoke all on function public.plantas_acumulado_asfalto(uuid, bigint, timestamptz) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 3) registrar_pesada_bascula: estado del pedido + acumulado nuevo
--    Resto del cuerpo sin cambios respecto de producción.
-- ----------------------------------------------------------------------------
create or replace function public.registrar_pesada_bascula(p_tipo_vale text, p_peso_bruto numeric, p_tara numeric, p_pedido_id uuid DEFAULT NULL::uuid, p_obra_id bigint DEFAULT NULL::bigint, p_patente text DEFAULT NULL::text, p_chofer text DEFAULT NULL::text, p_unidad text DEFAULT 'tn'::text, p_observaciones text DEFAULT NULL::text, p_fecha_pesada timestamp with time zone DEFAULT now(), p_material text DEFAULT NULL::text, p_proveedor text DEFAULT NULL::text, p_numero_remito text DEFAULT NULL::text, p_cantidad_remito numeric DEFAULT NULL::numeric, p_temperatura numeric DEFAULT NULL::numeric)
 RETURNS plantas_vales
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    -- Migración 65: solo se pesa contra un pedido confirmado y con el pesaje abierto.
    if v_pedido.estado <> 'confirmado' then
      raise exception 'El pedido % está % — no admite más pesadas.', plantas_etiqueta_pedido(v_pedido.numero), v_pedido.estado;
    end if;
    if v_pedido.pesaje_cerrado_en is not null then
      raise exception 'El pedido % tiene el pesaje cerrado (%, %). Para seguir pesando, un plantista o admin tiene que reabrirlo desde Pedidos.',
        plantas_etiqueta_pedido(v_pedido.numero), v_pedido.pesaje_cerrado_por,
        to_char(v_pedido.pesaje_cerrado_en at time zone 'America/Argentina/Buenos_Aires', 'DD/MM HH24:MI');
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
    -- Migración 65: por pedido sin corte de fecha; sin pedido, por obra y día
    -- de Argentina (antes: día UTC, que cortaba a las 21:00).
    v_acumulado_tn := (plantas_acumulado_asfalto(p_pedido_id, v_obra_id, p_fecha_pesada) ->> 'tn')::numeric + v_neto_tn;

    if p_pedido_id is not null then
      update plantas_pedidos
        set nro_remito_global = coalesce(nro_remito_global, nextval('plantas_remitos_numero_seq')::text)
        where id = p_pedido_id;
    end if;
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

-- ----------------------------------------------------------------------------
-- 4) reasignar_vale_bascula: el destino tampoco puede tener el pesaje cerrado
--    (se parchea el cuerpo de producción en un solo punto).
-- ----------------------------------------------------------------------------
do $reasignar$
declare
  v_src   text := pg_get_functiondef('public.reasignar_vale_bascula(uuid,uuid,text)'::regprocedure);
  v_ancla text := $a$  if v_destino.estado <> 'confirmado' then
    raise exception 'El pedido elegido tiene que estar confirmado (estado actual: %).', v_destino.estado;
  end if;
$a$;
  v_nuevo text;
begin
  if (length(v_src) - length(replace(v_src, v_ancla, ''))) / length(v_ancla) <> 1 then
    raise exception 'MIG65: el ancla de reasignar_vale_bascula no aparece una sola vez';
  end if;
  v_nuevo := replace(v_src, v_ancla, v_ancla || $b$  if v_destino.pesaje_cerrado_en is not null then
    raise exception 'El pedido elegido tiene el pesaje cerrado — un plantista o admin tiene que reabrirlo desde Pedidos.';
  end if;
$b$);
  execute v_nuevo;
end;
$reasignar$;

-- ----------------------------------------------------------------------------
-- 5) Vista del historial de Báscula: mismo criterio de acumulado
--    (columna acumulado_dia_tn: se conserva el nombre, la usa el frontend).
-- ----------------------------------------------------------------------------
do $vista$
declare
  v_src   text := pg_get_viewdef('public.plantas_v_bascula_viva'::regclass);
  v_ancla text := $a$OVER (PARTITION BY COALESCE((pedido_id)::text, (obra_id)::text, 'sin-obra'::text), (date_trunc('day'::text, (fecha_pesada AT TIME ZONE 'America/Argentina/Buenos_Aires'::text))) ORDER BY fecha_pesada)$a$;
  v_nueva text := $b$OVER (PARTITION BY COALESCE(('p:'::text || (pedido_id)::text), ((('o:'::text || COALESCE((obra_id)::text, 'sin-obra'::text)) || ':'::text) || to_char((fecha_pesada AT TIME ZONE 'America/Argentina/Buenos_Aires'::text), 'YYYY-MM-DD'::text))) ORDER BY fecha_pesada)$b$;
begin
  if (length(v_src) - length(replace(v_src, v_ancla, ''))) / length(v_ancla) <> 1 then
    raise exception 'MIG65: el ancla de plantas_v_bascula_viva no aparece una sola vez';
  end if;
  execute 'create or replace view public.plantas_v_bascula_viva with (security_invoker = true) as '
    || replace(v_src, v_ancla, v_nueva);
end;
$vista$;

-- ----------------------------------------------------------------------------
-- 6) Cerrar / reabrir el pesaje de un pedido
-- ----------------------------------------------------------------------------
create function public.cerrar_pesaje_pedido(p_pedido_id uuid)
returns plantas_pedidos
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_rol    text := plantas_rol_actual();
  v_pedido plantas_pedidos;
  v_antes  jsonb;
  v_acum   jsonb;
begin
  if v_rol is null or v_rol not in ('admin', 'plantista', 'balancero') then
    raise exception 'Tu rol (%) no puede cerrar el pesaje de un pedido.', coalesce(v_rol, 'sin rol asignado');
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.tipo <> 'asfalto' then
    raise exception 'Solo los pedidos de asfalto se pesan en Báscula.';
  end if;
  if v_pedido.estado <> 'confirmado' then
    raise exception 'El pedido % está % — no hay pesaje abierto para cerrar.', plantas_etiqueta_pedido(v_pedido.numero), v_pedido.estado;
  end if;
  if v_pedido.pesaje_cerrado_en is not null then
    raise exception 'El pedido % ya tiene el pesaje cerrado.', plantas_etiqueta_pedido(v_pedido.numero);
  end if;

  v_acum := plantas_acumulado_asfalto(p_pedido_id, v_pedido.obra_id, 'infinity'::timestamptz);
  if jsonb_array_length(v_acum -> 'vales') = 0 then
    raise exception 'El pedido % no tiene pesadas — no hay nada que cerrar.', plantas_etiqueta_pedido(v_pedido.numero);
  end if;

  v_antes := to_jsonb(v_pedido);
  update plantas_pedidos
     set pesaje_cerrado_en = now(), pesaje_cerrado_por = auth.email()
   where id = p_pedido_id
  returning * into v_pedido;

  -- pesado_tn / vales_pesados solo en "después": la auditoría los muestra
  -- como datos nuevos del cierre (no estaban antes).
  perform plantas_auditar(
    'CAMBIAR_ESTADO', 'pedidos', 'pedido',
    plantas_etiqueta_pedido(v_pedido.numero),
    plantas_auditoria_label_pedido(p_pedido_id),
    null, v_antes,
    to_jsonb(v_pedido) || jsonb_build_object('pesado_tn', (v_acum ->> 'tn')::numeric, 'vales_pesados', jsonb_array_length(v_acum -> 'vales'))
  );

  return v_pedido;
end;
$fn$;

comment on function public.cerrar_pesaje_pedido(uuid) is
  'Báscula: "¿Se terminó el pedido? Sí". Cierra el pesaje (no admite más pesadas). No finaliza el despacho: eso sigue en Pedidos (finalizar_despacho). Migración 65.';

create function public.reabrir_pesaje_pedido(p_pedido_id uuid, p_motivo text)
returns plantas_pedidos
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_rol    text := plantas_rol_actual();
  v_pedido plantas_pedidos;
  v_antes  jsonb;
begin
  if v_rol is null or v_rol not in ('admin', 'plantista') then
    raise exception 'Tu rol (%) no puede reabrir el pesaje de un pedido.', coalesce(v_rol, 'sin rol asignado');
  end if;
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'El motivo para reabrir el pesaje es obligatorio.';
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.estado <> 'confirmado' then
    raise exception 'El pedido % está % — solo se reabre el pesaje de un pedido confirmado.', plantas_etiqueta_pedido(v_pedido.numero), v_pedido.estado;
  end if;
  if v_pedido.pesaje_cerrado_en is null then
    raise exception 'El pedido % tiene el pesaje abierto.', plantas_etiqueta_pedido(v_pedido.numero);
  end if;

  v_antes := to_jsonb(v_pedido);
  update plantas_pedidos
     set pesaje_cerrado_en = null, pesaje_cerrado_por = null
   where id = p_pedido_id
  returning * into v_pedido;

  perform plantas_auditar_pedido('CAMBIAR_ESTADO', 'pedido', p_pedido_id, btrim(p_motivo), v_antes);

  return v_pedido;
end;
$fn$;

comment on function public.reabrir_pesaje_pedido(uuid, text) is
  'Reabre el pesaje de un pedido confirmado (plantista/admin, motivo obligatorio, queda en la auditoría). Migración 65.';

revoke all on function public.cerrar_pesaje_pedido(uuid) from public, anon;
revoke all on function public.reabrir_pesaje_pedido(uuid, text) from public, anon;
grant execute on function public.cerrar_pesaje_pedido(uuid) to authenticated;
grant execute on function public.reabrir_pesaje_pedido(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 7) Impresiones auditadas
-- ----------------------------------------------------------------------------
alter table public.plantas_auditoria drop constraint plantas_auditoria_tipo_accion_check;
alter table public.plantas_auditoria add constraint plantas_auditoria_tipo_accion_check
  check (tipo_accion = any (array['CREAR', 'EDITAR', 'CAMBIAR_ESTADO', 'ANULAR', 'CORREGIR', 'REASIGNAR', 'ELIMINAR', 'IMPRIMIR']));

insert into public.plantas_auditoria_entidades (modulo, entidad, modulo_etiqueta, entidad_etiqueta, orden)
values ('bascula', 'impresion', 'Báscula', 'Impresión', 32);

/**
 * Registra una impresión (o PDF) de un vale o de un remito y devuelve lo que
 * hay que imprimir, calculado acá: así lo auditado y el papel coinciden.
 * p_modo: 'vale' | 'remito'. p_origen: 'bascula' | 'despachos'.
 * p_salida: 'impresora' | 'pdf'.
 */
create function public.registrar_impresion(p_vale_id uuid, p_modo text, p_origen text, p_salida text default 'impresora')
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_vale     plantas_vales;
  v_pedido   plantas_pedidos;
  v_acum     jsonb;
  v_ref      text;
  v_label    text;
  v_previa   plantas_auditoria;
  v_vez      int;
  v_snap     jsonb;
begin
  if not (plantas_tiene_permiso('bascula', 'ver') or plantas_tiene_permiso('despachos', 'ver')) then
    raise exception 'Tu rol (%) no puede imprimir vales ni remitos.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;
  if p_modo not in ('vale', 'remito') then
    raise exception 'Modo de impresión inválido: %', p_modo;
  end if;
  if p_origen not in ('bascula', 'despachos') then
    raise exception 'Origen de impresión inválido: %', p_origen;
  end if;
  if p_salida not in ('impresora', 'pdf') then
    raise exception 'Salida de impresión inválida: %', p_salida;
  end if;

  select * into v_vale from plantas_vales where id = p_vale_id;
  if not found then
    raise exception 'El vale % no existe.', p_vale_id;
  end if;
  if v_vale.anulado then
    raise exception 'El vale % está anulado — no se imprime.', plantas_etiqueta_vale(v_vale);
  end if;
  if p_modo = 'remito' and v_vale.tipo_vale <> 'asfalto' then
    raise exception 'El remito solo se imprime para vales de asfalto.';
  end if;
  if v_vale.tipo_vale not in ('asfalto', 'egreso_arido') then
    raise exception 'Este tipo de vale no se imprime.';
  end if;

  if v_vale.pedido_id is not null then
    select * into v_pedido from plantas_pedidos where id = v_vale.pedido_id;
  end if;

  if v_vale.tipo_vale = 'asfalto' then
    v_acum := plantas_acumulado_asfalto(v_vale.pedido_id, v_vale.obra_id, v_vale.fecha_pesada);
  end if;

  v_ref := plantas_etiqueta_vale(v_vale);
  v_label := case when p_modo = 'remito'
                  then 'Remito ' || coalesce(lpad(nullif(v_pedido.nro_remito_global, ''), 5, '0'), 'sin número') || ' — '
                  else '' end
             || plantas_auditoria_label_vale(p_vale_id);

  select * into v_previa
    from plantas_auditoria
   where entidad = 'impresion' and entidad_ref = v_ref and valores_despues ->> 'modo' = p_modo
   order by id desc
   limit 1;
  select count(*) + 1 into v_vez
    from plantas_auditoria
   where entidad = 'impresion' and entidad_ref = v_ref and valores_despues ->> 'modo' = p_modo;

  v_snap := jsonb_build_object(
    'modo', p_modo,
    'origen', p_origen,
    'salida', p_salida,
    'vale', v_ref,
    'tipo_vale', v_vale.tipo_vale,
    'pedido', plantas_etiqueta_pedido(v_pedido.numero),
    'remito', nullif(v_pedido.nro_remito_global, ''),
    'peso_neto', v_vale.peso_neto,
    'acumulado_tn', (v_acum ->> 'tn')::numeric,
    'vales', coalesce(v_acum -> 'vales', '[]'::jsonb),
    'vez', v_vez
  );

  if v_previa.id is not null
     and ((v_previa.valores_despues -> 'acumulado_tn') is distinct from (v_snap -> 'acumulado_tn')
          or (v_previa.valores_despues -> 'vales') is distinct from (v_snap -> 'vales')
          or (v_previa.valores_despues -> 'remito') is distinct from (v_snap -> 'remito')) then
    v_snap := v_snap || jsonb_build_object('anterior', jsonb_build_object(
      'fecha_hora', v_previa.fecha_hora,
      'acumulado_tn', v_previa.valores_despues -> 'acumulado_tn',
      'vales', v_previa.valores_despues -> 'vales',
      'remito', v_previa.valores_despues -> 'remito'
    ));
  end if;

  perform plantas_auditar('IMPRIMIR', 'bascula', 'impresion', v_ref, v_label, null, null, v_snap);

  return v_snap;
end;
$fn$;

comment on function public.registrar_impresion(uuid, text, text, text) is
  'Audita una impresión/PDF de vale o remito (acción IMPRIMIR) y devuelve lo que se imprime: acumulado, vales, N° de remito, vez y, si cambió, la impresión anterior. Migración 65.';

-- Impresiones (vale o remito) en las que figura un vale: para avisar al
-- editarlo o anularlo que hay que reimprimir. La auditoría solo la lee el
-- admin, así que esto devuelve lo mínimo para el aviso.
create function public.impresiones_del_vale(p_vale_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $fn$
declare
  v_vale plantas_vales;
begin
  if not (plantas_tiene_permiso('bascula', 'editar') or plantas_tiene_permiso('bascula', 'eliminar')) then
    raise exception 'Tu rol (%) no puede consultar las impresiones de un vale.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;
  select * into v_vale from plantas_vales where id = p_vale_id;
  if not found or v_vale.numero_vale is null then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'modo', a.valores_despues ->> 'modo',
             'vale', a.entidad_ref,
             'remito', a.valores_despues ->> 'remito',
             'acumulado_tn', a.valores_despues -> 'acumulado_tn',
             'fecha_hora', a.fecha_hora,
             'usuario', a.usuario_nombre
           ) order by a.id desc)
      from (
        select * from plantas_auditoria
         where entidad = 'impresion'
           and valores_despues -> 'vales' @> to_jsonb(v_vale.numero_vale)
         order by id desc
         limit 10
      ) a
  ), '[]'::jsonb);
end;
$fn$;

revoke all on function public.registrar_impresion(uuid, text, text, text) from public, anon;
revoke all on function public.impresiones_del_vale(uuid) from public, anon;
grant execute on function public.registrar_impresion(uuid, text, text, text) to authenticated;
grant execute on function public.impresiones_del_vale(uuid) to authenticated;
