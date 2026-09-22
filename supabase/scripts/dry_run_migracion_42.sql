-- ============================================================================
-- Dry-run de la Migración 42 (numeración propia ingreso/egreso de áridos)
-- Proyecto Supabase compartido con el sistema de flota (ejitztewkpnmrckwmvny)
--
-- Objetivo: correr la migración 42 completa dentro de una transacción y
-- verificar el resultado ANTES de aplicarla de verdad — al final se hace
-- ROLLBACK, no queda nada escrito. Mismo mecanismo ya usado y documentado
-- para la migración 43 (memory/pending.md, "Dry-run ejecutado contra
-- producción y revertido (2026-09-19): OK").
--
-- Baseline medido en producción antes de este dry-run (2026-09-22):
--   asfalto: 489 (9581–10115, 0 anulados)
--   ingreso_arido: 512 (min 10014 post-corte intercalado, legado en bloque 90000001+)
--   egreso_arido: 6 (3 anulados)
--   plantas_vales_numero_vale_seq: last_value 10115, is_called true
--
-- Advertencia operativa: la migración toma
--   `lock table plantas_vales in exclusive mode;`
-- como primera sentencia — mientras corre este dry-run (incluido el
-- ROLLBACK), Báscula no puede registrar pesadas nuevas en producción. La
-- migración completa corre en milisegundos sobre ~1000 filas, así que el
-- bloqueo es breve, pero es real: no ejecutar en medio de un turno de
-- pesaje activo.
--
-- Uso: ejecutar este archivo completo de una sola vez (una sola conexión/
-- sesión — el ROLLBACK del final solo revierte lo que pasó en el MISMO
-- BEGIN). La última sentencia (un SELECT de verificación) es lo que hay
-- que mirar antes de decidir aplicar la migración real.
-- ============================================================================

begin;

-- Baseline dentro de la misma transacción (no hardcodeado en el script:
-- si algún vale real se cargó entre la última auditoría y este dry-run, la
-- comparación de abajo lo sigue detectando bien).
create temporary table _dry_run_baseline as
select count(*) as total_filas from plantas_vales;

-- ============================================================================
-- Migración 42: numeración propia para ingreso y egreso de áridos (Báscula)
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- BORRADOR — NO APLICADA. Requiere confirmación explícita de Federico antes
-- de correr en producción (memory/procedimientos.md: cambia schema y datos).
--
-- Pedido de Federico (2026-09-19): la numeración de asfalto no se puede
-- mezclar con la de los ingresos de áridos. Decisión: ingreso y egreso de
-- áridos COMPARTEN una numeración propia, separada de la de asfalto, con
-- formato I-00001 (arranca en 1).
--
-- Problema de origen: plantas_vales.numero_vale era `identity` global, así
-- que cada ingreso/egreso consumía un número de la secuencia del asfalto
-- (desde el corte ya hay ingresos/egresos intercalados en 10014-10064) y los
-- 500 ingresos migrados del legado tuvieron que moverse al bloque sintético
-- 90000001+ para no chocar. Además el remito de asfalto arma "S/Vale de
-- báscula N° X al Y (correlativos)" con el rango de numero_vale.
--
-- Qué hace:
--   1) Secuencia nueva plantas_vales_numero_arido_seq + columna
--      plantas_vales.numero_vale_arido (unique).
--   2) numero_vale deja de ser identity: pasa a nullable con una secuencia
--      común del mismo nombre (plantas_vales_numero_vale_seq) que CONSERVA su
--      posición actual (próximo asfalto = 10065). Solo asfalto/hormigón la
--      usan, asignada por registrar_pesada_bascula().
--   3) Renumera los ingresos/egresos existentes en orden cronológico
--      (fecha_pesada, id) a numero_vale_arido 1..N y les anula numero_vale.
--      El número anterior queda guardado en datos_legados->>'numero_vale_previo'
--      (reversible/auditable). Los huecos que deja en la secuencia de asfalto
--      NO se reutilizan.
--   4) CHECK que impide mezclar: asfalto/hormigón => solo numero_vale;
--      ingreso/egreso => solo numero_vale_arido.
--   5) registrar_pesada_bascula() asigna cada número según el tipo;
--      corregir_vale_bascula()/anular_vale_bascula() etiquetan el vale con
--      plantas_etiqueta_vale() (antes '#?' para los que no tienen numero_vale).
--   6) plantas_v_bascula_viva expone numero_vale_arido (columna nueva al final).
--
-- Reversión: el número previo de cada fila está en datos_legados; para
-- volver atrás hay que reponer numero_vale desde ahí, quitar el CHECK y
-- volver a hacer numero_vale identity. No es un rollback de un solo comando.
-- ============================================================================

-- Sin escrituras concurrentes mientras se renumera
lock table plantas_vales in exclusive mode;

-- ----------------------------------------------------------------------------
-- 1) Numeración propia de ingreso/egreso de áridos
-- ----------------------------------------------------------------------------
create sequence plantas_vales_numero_arido_seq minvalue 1;

alter table plantas_vales add column numero_vale_arido bigint;

comment on column plantas_vales.numero_vale_arido is
  'N° de vale propio de ingreso_arido/egreso_arido (compartido entre ambos, se muestra I-00001). Separado de numero_vale, que es solo de asfalto/hormigón. Migración 42.';

-- ----------------------------------------------------------------------------
-- 2) numero_vale: de identity a secuencia común nullable (conserva posición)
-- ----------------------------------------------------------------------------
do $$
declare
  v_last   bigint;
  v_called boolean;
begin
  select last_value, is_called into v_last, v_called from plantas_vales_numero_vale_seq;

  alter table plantas_vales alter column numero_vale drop identity;
  alter table plantas_vales alter column numero_vale drop not null;

  create sequence plantas_vales_numero_vale_seq minvalue 1 owned by plantas_vales.numero_vale;
  perform setval('plantas_vales_numero_vale_seq', v_last, v_called);
end $$;

comment on column plantas_vales.numero_vale is
  'N° de vale de asfalto/hormigón (secuencia global desde 9579, la asigna registrar_pesada_bascula). Null en ingreso_arido/egreso_arido, que usan numero_vale_arido (migración 42).';

-- ----------------------------------------------------------------------------
-- 3) Renumerar ingresos/egresos existentes (cronológico), preservando el previo
-- ----------------------------------------------------------------------------
with orden as (
  select id, row_number() over (order by fecha_pesada, id) as rn
  from plantas_vales
  where tipo_vale in ('ingreso_arido', 'egreso_arido')
)
update plantas_vales v set
  numero_vale_arido = o.rn,
  datos_legados     = coalesce(v.datos_legados, '{}'::jsonb) || jsonb_build_object('numero_vale_previo', v.numero_vale),
  numero_vale       = null
from orden o
where o.id = v.id;

select setval(
  'plantas_vales_numero_arido_seq',
  greatest(coalesce((select max(numero_vale_arido) from plantas_vales), 0), 1),
  coalesce((select max(numero_vale_arido) from plantas_vales), 0) > 0
);

-- ----------------------------------------------------------------------------
-- 4) Unicidad + regla anti-mezcla
-- ----------------------------------------------------------------------------
alter table plantas_vales
  add constraint plantas_vales_numero_vale_arido_key unique (numero_vale_arido);

alter table plantas_vales
  add constraint plantas_vales_numeracion_por_tipo_chk check (
    (tipo_vale in ('asfalto', 'hormigon')
       and numero_vale is not null and numero_vale_arido is null)
    or
    (tipo_vale in ('ingreso_arido', 'egreso_arido')
       and numero_vale is null and numero_vale_arido is not null)
  );

-- ----------------------------------------------------------------------------
-- 5) Etiqueta legible del vale (para notas de auditoría de stock)
-- ----------------------------------------------------------------------------
create or replace function plantas_etiqueta_vale(p_vale plantas_vales)
returns text
language sql
immutable
set search_path = public
as $$
  select coalesce(p_vale.numero_vale::text, 'I-' || lpad(p_vale.numero_vale_arido::text, 5, '0'), '?')
$$;

-- ----------------------------------------------------------------------------
-- 6) registrar_pesada_bascula — asigna cada numeración según el tipo.
--    Firma y resto del cuerpo idénticos a la migración 39.
-- ----------------------------------------------------------------------------
create or replace function registrar_pesada_bascula(
  p_tipo_vale        text,
  p_peso_bruto       numeric,
  p_tara             numeric,
  p_pedido_id        uuid default null,
  p_obra_id          bigint default null,
  p_patente          text default null,
  p_chofer           text default null,
  p_unidad           text default 'tn',
  p_observaciones    text default null,
  p_fecha_pesada     timestamptz default now(),
  p_material         text default null,
  p_proveedor        text default null,
  p_numero_remito    text default null,
  p_cantidad_remito  numeric default null,
  p_temperatura      numeric default null
)
returns plantas_vales
language plpgsql
security definer
set search_path = public
as $$
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
    -- `for update`: nuevo desde esta migración — antes esta función solo
    -- LEÍA el pedido (obra_id/acumulado), ahora también puede escribir
    -- nro_remito_global (ver bloque asfalto más abajo), así que necesita el
    -- mismo lock de fila que ya usa registrar_carga_asfalto() para evitar
    -- que dos pesadas simultáneas del mismo pedido se pisen la asignación.
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

      -- Origen del remito (migración 39): se asigna acá, en la PRIMERA
      -- pesada del pedido en Báscula — no en Pedidos. Coalesce: si una
      -- pesada anterior del mismo pedido ya lo asignó, no lo pisa (mismo
      -- número para todas las pesadas/cargas del pedido, business-rules.md).
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
      p_material, p_proveedor, p_numero_remito, coalesce(p_cantidad_remito, v_neto_tn), 'tn',
      'bascula', v_vale.id, p_fecha_pesada, p_observaciones
    )
    returning id into v_ingreso_id;

    v_material_id := plantas_buscar_material_id(p_material);
    if v_material_id is not null then
      perform plantas_aplicar_movimiento_stock(
        v_material_id, 'ingreso_proveedor', coalesce(p_cantidad_remito, v_neto_tn) * 1000,
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

  return v_vale;
end;
$$;

comment on function registrar_pesada_bascula is
  'Numeración (migración 42): asfalto/hormigón toman numero_vale de plantas_vales_numero_vale_seq; ingreso/egreso de áridos comparten numero_vale_arido de plantas_vales_numero_arido_seq (se muestra I-00001) — nunca se mezclan. Registra un vale de báscula (asfalto/hormigón/ingreso o egreso de árido), mueve stock en ingreso_arido/egreso_arido (migración 13) y captura responsable_email vía auth.email() (migración 20). Para asfalto con pedido_id, asigna nro_remito_global en la PRIMERA pesada del pedido (migración 39, coalesce — no se reasigna en pesadas siguientes del mismo pedido). Fuera de eso, sigue sin tocar plantas_pedidos: cantidad_despachada/estado siguen siendo exclusivos de Pedidos (registrar_carga_asfalto + finalizar_despacho) — Báscula es el origen del remito y la auditoría del pesaje, no la fuente de verdad del total despachado (memory/business-rules.md).';

-- ----------------------------------------------------------------------------
-- 7) corregir_vale_bascula / anular_vale_bascula — mismas funciones de la
--    migración 31, solo cambia la etiqueta del vale en las notas de stock.
-- ----------------------------------------------------------------------------
create or replace function corregir_vale_bascula(
  p_vale_id         uuid,
  p_peso_bruto      numeric,
  p_tara            numeric,
  p_patente         text default null,
  p_chofer          text default null,
  p_observaciones   text default null,
  p_temperatura     numeric default null,
  p_proveedor       text default null,
  p_numero_remito   text default null,
  p_cantidad_remito numeric default null,
  p_obra_id         bigint default null
)
returns plantas_vales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol         text;
  v_vale        plantas_vales;
  v_peso_neto   numeric;
  v_neto_tn     numeric;
  v_material_id uuid;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista') then
    raise exception 'Tu rol (%) no puede editar vales de báscula.', coalesce(v_rol, 'sin rol asignado');
  end if;

  select * into v_vale from plantas_vales where id = p_vale_id;
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

  return v_vale;
end;
$$;

comment on function corregir_vale_bascula is
  'Editar un vale de Báscula ya guardado (admin/plantista). No cambia tipo_vale ni material — ver header de la migración 31. Recalcula stock de forma idempotente vía plantas_recalcular_stock_vale().';

revoke execute on function corregir_vale_bascula(uuid, numeric, numeric, text, text, text, numeric, text, text, numeric, bigint) from public;
grant execute on function corregir_vale_bascula(uuid, numeric, numeric, text, text, text, numeric, text, text, numeric, bigint) to authenticated;

create or replace function anular_vale_bascula(p_vale_id uuid, p_motivo text)
returns plantas_vales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol         text;
  v_vale        plantas_vales;
  v_neto_tn     numeric;
  v_material_id uuid;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista') then
    raise exception 'Tu rol (%) no puede anular vales de báscula.', coalesce(v_rol, 'sin rol asignado');
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'El motivo de anulación es obligatorio.';
  end if;

  select * into v_vale from plantas_vales where id = p_vale_id;
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

  return v_vale;
end;
$$;

comment on function anular_vale_bascula is
  'Baja lógica de un vale de Báscula (admin/plantista, motivo obligatorio) — nunca DELETE real, ver header de la migración 31. Revierte el efecto de stock a 0 si el vale era ingreso_arido/egreso_arido.';

revoke execute on function anular_vale_bascula(uuid, text) from public;
grant execute on function anular_vale_bascula(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 8) plantas_v_bascula_viva — definición de la migración 33 + numero_vale_arido
--    (columna nueva AL FINAL, única posición válida para create or replace).
-- ----------------------------------------------------------------------------
create or replace view plantas_v_bascula_viva
with (security_invoker = true) as
with obras_legado as (
  select
    o ->> 'id' as obra_id_legado,
    trim(o ->> 'nombre') as nombre_legado,
    coalesce(
      fo_cod.id,
      fo_nom.id,
      case o ->> 'id'
        when 'o1' then 10
        when 'yjscoq2' then 26
        when 'f4stkay' then 2
      end
    ) as flota_obra_id
  from kv_store, jsonb_array_elements(value -> 'obras') as o
  left join flota_obras fo_cod
    on fo_cod.codigo is not null and upper(trim(fo_cod.codigo)) = upper(nullif(trim(o ->> 'codigo'), ''))
  left join flota_obras fo_nom
    on upper(trim(fo_nom.nombre)) = upper(trim(o ->> 'nombre'))
  where kv_store.key = 'vt_maestros9'
),
pp_visible as materialized (
  select id, obra_id, cliente_externo, formula_id, datos_legados ->> 'id' as legado_id
  from plantas_pedidos
),
pv_base as materialized (
  select pv.*, pi.material as ing_material, pi.numero_remito as ing_numero_remito, pi.cantidad as ing_cantidad,
         pi.proveedor as ing_proveedor,
         ppv.cliente_externo as pp_cliente_externo
  from plantas_vales pv
  left join plantas_ingresos pi on pi.vale_id = pv.id
  left join pp_visible ppv on ppv.id = pv.pedido_id
),
legado_asfalto as (
  select
    md5('bascula:asfalto:' || (v ->> 'id'))::uuid as id,
    (v ->> 'numero')::bigint as numero_vale,
    'asfalto'::text as tipo_vale,
    pp.id as pedido_id,
    coalesce(pp.obra_id, ol.flota_obra_id) as obra_id,
    nullif(v ->> 'patente', '') as patente,
    nullif(v ->> 'chofer', '') as chofer,
    (v ->> 'pesoBruto')::numeric as peso_bruto,
    (v ->> 'tara')::numeric as tara,
    (v ->> 'pesoNeto')::numeric as peso_neto,
    'tn'::text as unidad,
    ((v ->> 'fecha') || ' ' || coalesce(nullif(v ->> 'hora', ''), '00:00'))::timestamp
      at time zone 'America/Argentina/Buenos_Aires' as fecha_pesada,
    null::text as material,
    nullif(v ->> 'temperatura', '')::numeric as temperatura,
    null::text as responsable_email,
    nullif(v ->> 'operador', '') as responsable_texto_legado,
    null::text as numero_remito_ingreso,
    null::numeric as cantidad_remito_ingreso,
    pp.cliente_externo as cliente_externo,
    null::numeric as acumulado_obra_tn,
    true as pendiente_migracion,
    false as anulado,
    null::text as motivo_anulacion,
    null::text as proveedor,
    null::bigint as numero_vale_arido
  from kv_store, jsonb_array_elements(value) as v
  left join pp_visible pp on pp.legado_id = v ->> 'pedidoId'
  left join obras_legado ol on ol.nombre_legado = trim(v ->> 'obra')
  where kv_store.key = 'vt_vales9'
    and (v ->> 'fecha')::date >= '2026-09-01'
    and not exists (select 1 from pv_base pv where pv.datos_legados ->> 'id' = v ->> 'id')
),
legado_ingreso as (
  select
    md5('bascula:ingreso:' || (v ->> 'id'))::uuid as id,
    null::bigint as numero_vale,
    'ingreso_arido'::text as tipo_vale,
    null::uuid as pedido_id,
    null::bigint as obra_id,
    nullif(v ->> 'patente', '') as patente,
    null::text as chofer,
    (v ->> 'pesoBruto')::numeric as peso_bruto,
    (v ->> 'tara')::numeric as tara,
    (v ->> 'pesoNeto')::numeric as peso_neto,
    'tn'::text as unidad,
    ((v ->> 'fecha') || ' ' || coalesce(nullif(v ->> 'hora', ''), '00:00'))::timestamp
      at time zone 'America/Argentina/Buenos_Aires' as fecha_pesada,
    trim(v ->> 'material') as material,
    null::numeric as temperatura,
    null::text as responsable_email,
    nullif(v ->> 'responsable', '') as responsable_texto_legado,
    nullif(v ->> 'remito', '') as numero_remito_ingreso,
    (v ->> 'cantidadRemito')::numeric as cantidad_remito_ingreso,
    null::text as cliente_externo,
    null::numeric as acumulado_obra_tn,
    true as pendiente_migracion,
    false as anulado,
    null::text as motivo_anulacion,
    nullif(v ->> 'proveedor', '') as proveedor,
    null::bigint as numero_vale_arido
  from kv_store, jsonb_array_elements(value) as v
  where kv_store.key = 'vt_ingaridos9'
    and (v ->> 'fecha')::date >= '2026-09-01'
    and not exists (
      select 1 from plantas_ingresos pi
      where pi.numero_remito = nullif(v ->> 'remito', '') and pi.material = trim(v ->> 'material')
    )
),
legado_egreso as (
  select
    md5('bascula:egreso:' || (v ->> 'id'))::uuid as id,
    (v ->> 'numero')::bigint as numero_vale,
    'egreso_arido'::text as tipo_vale,
    null::uuid as pedido_id,
    ol.flota_obra_id as obra_id,
    nullif(v ->> 'patente', '') as patente,
    nullif(v ->> 'chofer', '') as chofer,
    (v ->> 'pesoBruto')::numeric as peso_bruto,
    (v ->> 'tara')::numeric as tara,
    (v ->> 'pesoNeto')::numeric as peso_neto,
    'tn'::text as unidad,
    ((v ->> 'fecha') || ' ' || coalesce(nullif(v ->> 'hora', ''), '00:00'))::timestamp
      at time zone 'America/Argentina/Buenos_Aires' as fecha_pesada,
    nullif(v ->> 'material', '') as material,
    null::numeric as temperatura,
    null::text as responsable_email,
    nullif(v ->> 'responsable', '') as responsable_texto_legado,
    null::text as numero_remito_ingreso,
    null::numeric as cantidad_remito_ingreso,
    null::text as cliente_externo,
    null::numeric as acumulado_obra_tn,
    true as pendiente_migracion,
    false as anulado,
    null::text as motivo_anulacion,
    null::text as proveedor,
    null::bigint as numero_vale_arido
  from kv_store, jsonb_array_elements(value) as v
  left join obras_legado ol on ol.nombre_legado = trim(v ->> 'destino')
  where kv_store.key = 'vt_egaridos9'
    and (v ->> 'fecha')::date >= '2026-09-01'
    and not exists (select 1 from pv_base pv where pv.datos_legados ->> 'id' = v ->> 'id')
),
migrados as (
  select
    pv.id,
    pv.numero_vale,
    pv.tipo_vale,
    pv.pedido_id,
    pv.obra_id,
    pv.patente,
    pv.chofer,
    pv.peso_bruto,
    pv.tara,
    pv.peso_neto,
    pv.unidad,
    pv.fecha_pesada,
    coalesce(pv.material, pv.ing_material) as material,
    pv.temperatura,
    pv.responsable_email,
    null::text as responsable_texto_legado,
    pv.ing_numero_remito as numero_remito_ingreso,
    pv.ing_cantidad as cantidad_remito_ingreso,
    pv.pp_cliente_externo as cliente_externo,
    pv.acumulado_obra_tn,
    false as pendiente_migracion,
    pv.anulado,
    pv.motivo_anulacion,
    pv.ing_proveedor as proveedor,
    pv.numero_vale_arido
  from pv_base pv
),
combinado as (
  select * from migrados
  union all
  select * from legado_asfalto
  union all
  select * from legado_ingreso
  union all
  select * from legado_egreso
)
select
  id, numero_vale, tipo_vale, pedido_id, obra_id, patente, chofer,
  peso_bruto, tara, peso_neto, unidad, fecha_pesada, material, temperatura,
  responsable_email, responsable_texto_legado, numero_remito_ingreso,
  cantidad_remito_ingreso, cliente_externo, acumulado_obra_tn, pendiente_migracion,
  case
    when tipo_vale = 'asfalto' then
      sum(peso_neto) filter (where tipo_vale = 'asfalto' and not anulado) over (
        partition by coalesce(pedido_id::text, obra_id::text, 'sin-obra'), date_trunc('day', fecha_pesada at time zone 'America/Argentina/Buenos_Aires')
        order by fecha_pesada
      )
    else null::numeric
  end as acumulado_dia_tn,
  anulado,
  motivo_anulacion,
  proveedor,
  numero_vale_arido
from combinado c;

grant select on plantas_v_bascula_viva to authenticated;

-- ----------------------------------------------------------------------------
-- Verificación (una sola tabla de resultados, todo debe dar OK)
-- ----------------------------------------------------------------------------
select 'total_filas_sin_cambios' as check_,
       (select count(*) from plantas_vales) = (select total_filas from _dry_run_baseline) as ok,
       (select count(*) from plantas_vales)::text || ' (baseline ' ||
         (select total_filas from _dry_run_baseline)::text || ')' as detalle
union all
select 'asfalto_hormigon_solo_numero_vale',
       count(*) filter (
         where tipo_vale in ('asfalto', 'hormigon')
           and not (numero_vale is not null and numero_vale_arido is null)
       ) = 0,
       count(*) filter (where tipo_vale in ('asfalto', 'hormigon'))::text
from plantas_vales
union all
select 'aridos_solo_numero_vale_arido',
       count(*) filter (
         where tipo_vale in ('ingreso_arido', 'egreso_arido')
           and not (numero_vale is null and numero_vale_arido is not null)
       ) = 0,
       count(*) filter (where tipo_vale in ('ingreso_arido', 'egreso_arido'))::text
from plantas_vales
union all
select 'numero_vale_arido_sin_duplicados',
       count(numero_vale_arido) = count(distinct numero_vale_arido),
       count(numero_vale_arido)::text || ' asignados / ' || count(distinct numero_vale_arido)::text || ' únicos'
from plantas_vales
union all
select 'numero_vale_arido_denso_desde_1',
       max(numero_vale_arido) = count(*),
       'max=' || max(numero_vale_arido)::text || ' count=' || count(*)::text
from plantas_vales
where tipo_vale in ('ingreso_arido', 'egreso_arido')
union all
select 'numero_previo_guardado_en_datos_legados',
       count(*) filter (where datos_legados ->> 'numero_vale_previo' is null) = 0,
       count(*)::text || ' filas, ' ||
         count(*) filter (where datos_legados ->> 'numero_vale_previo' is null)::text || ' sin numero_vale_previo'
from plantas_vales
where tipo_vale in ('ingreso_arido', 'egreso_arido')
union all
select 'constraint_anti_mezcla_sin_violaciones',
       count(*) = 0,
       count(*)::text || ' filas violan la regla'
from plantas_vales
where not (
  (tipo_vale in ('asfalto', 'hormigon') and numero_vale is not null and numero_vale_arido is null)
  or
  (tipo_vale in ('ingreso_arido', 'egreso_arido') and numero_vale is null and numero_vale_arido is not null)
)
union all
-- Dinámico (no hardcodeado): la secuencia de asfalto/hormigón tiene que
-- quedar exactamente en el max(numero_vale) real post-migración — el
-- `setval` del paso 2 solo preserva lo que ya había, no lo cambia.
select 'secuencia_asfalto_preservada',
       s.last_value = v.max_numero and s.is_called,
       'last_value=' || s.last_value::text || ' max(numero_vale)=' || v.max_numero::text
from plantas_vales_numero_vale_seq s,
     (select max(numero_vale) as max_numero from plantas_vales where tipo_vale in ('asfalto', 'hormigon')) v
union all
-- Dinámico: la secuencia de áridos tiene que quedar en la cantidad total
-- de filas ingreso_arido/egreso_arido (incluye anuladas — el paso 3 las
-- renumera a todas, 1..N, sin excluirlas).
select 'secuencia_aridos_en_total_filas',
       s.last_value = v.total and s.is_called,
       'last_value=' || s.last_value::text || ' total_filas=' || v.total::text
from plantas_vales_numero_arido_seq s,
     (select count(*) as total from plantas_vales where tipo_vale in ('ingreso_arido', 'egreso_arido')) v
union all
select 'vista_bascula_viva_no_rompe',
       (select count(*) from plantas_v_bascula_viva) >= 0,
       (select count(*)::text from plantas_v_bascula_viva) || ' filas'
order by 1;

rollback;
