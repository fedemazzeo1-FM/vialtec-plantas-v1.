do $dryrev$
declare v_n int; v_txt text;
begin
  lock table plantas_vales in share row exclusive mode;
  create temp table dryrev_antes on commit drop as select id, acumulado_obra_tn as guardado from plantas_vales;
  execute $m66$
-- ============================================================================
-- Migración 66: el acumulado guardado se recalcula al corregir, anular o
-- reasignar un vale de asfalto
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Pedido de Federico (2026-10-20). El vale 10276 (P-0263) se corrigió de
-- 37,63 a 35,4 tn (y después a 35,65) y su acumulado_obra_tn siguió en
-- 37,63: corregir_vale_bascula cambiaba el peso pero no el acumulado
-- guardado. Lo mismo pasa con los vales siguientes del mismo pedido, y con
-- anular o reasignar un vale.
--
--   1. plantas_recalcular_acumulados_asfalto(pedido, obra, desde): vuelve a
--      calcular el acumulado guardado de los vales de asfalto del grupo
--      (mismo pedido; sin pedido, misma obra y día de Argentina) desde esa
--      fecha en adelante, con el mismo helper que la pesada, la vista y la
--      impresión (plantas_acumulado_asfalto, migración 65). No toca vales
--      anulados (conservan su foto) ni vales migrados del legado (no tienen
--      acumulado guardado).
--   2. Lo llaman corregir_vale_bascula (el vale corregido y los siguientes),
--      anular_vale_bascula (los siguientes), reasignar_vale_bascula (el
--      pedido de origen y el de destino) y registrar_pesada_bascula (una
--      pesada con fecha anterior a otras del mismo pedido). En corregir y
--      reasignar el recálculo va antes de auditar: la auditoría del vale
--      muestra también el cambio de su acumulado.
--   3. Datos: se corrigen los 18 vales que ya quedaron mal y que están mal
--      con cualquier regla (sumaban un vale anulado o el peso previo a una
--      corrección). Cada uno se verifica contra su valor actual antes de
--      cambiarlo; si alguno cambió, la migración no se aplica.
--        - Corregidos: 10213 (P-0227) y 10276 (P-0263).
--        - Con un vale anulado antes: P-0213 (10138-10140, 10142, 10143) y
--          P-0216 (10151-10159, 10162, 10164).
--      No se tocan los 10 vales nocturnos/de otro día guardados con la regla
--      vieja de corte diario (P-0212: 10144-10145; P-0233: 10240-10247): son
--      la foto que salió impresa en su momento (migración 65: "los vales
--      viejos conservan su acumulado_obra_tn guardado").
--
-- No cambia pedidos (P-0263 sigue abierto), ni la vista, ni lo impreso (la
-- impresión ya recalcula), ni las firmas de las funciones.
--
-- Reversión: supabase/scripts/revertir_migracion_66.sql
-- ============================================================================

-- 1) Recálculo del acumulado guardado
create function public.plantas_recalcular_acumulados_asfalto(p_pedido_id uuid, p_obra_id bigint, p_desde timestamptz)
returns integer
language plpgsql
set search_path to 'public'
as $function$
declare
  v_n integer;
begin
  if p_desde is null then
    return 0;
  end if;

  with objetivo as (
    select v.id, (plantas_acumulado_asfalto(v.pedido_id, v.obra_id, v.fecha_pesada) ->> 'tn')::numeric as acumulado
    from plantas_vales v
    where v.tipo_vale = 'asfalto'
      and not v.anulado
      and v.acumulado_obra_tn is not null
      and v.fecha_pesada >= p_desde
      and case
        when p_pedido_id is not null then v.pedido_id = p_pedido_id
        else v.pedido_id is null
          and v.obra_id is not distinct from p_obra_id
          and (v.fecha_pesada at time zone 'America/Argentina/Buenos_Aires')::date
              = (p_desde at time zone 'America/Argentina/Buenos_Aires')::date
      end
  )
  update plantas_vales v
    set acumulado_obra_tn = o.acumulado
    from objetivo o
    where v.id = o.id
      and v.acumulado_obra_tn is distinct from o.acumulado;

  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

revoke all on function public.plantas_recalcular_acumulados_asfalto(uuid, bigint, timestamptz) from public, anon, authenticated;

-- 2) Llamadas desde las funciones de Báscula (parches sobre la versión de
--    producción, con control de que sea exactamente la esperada)
do $parches$
declare
  v_src text;
  v_ancla text;
  v_extra text;
begin
  -- corregir_vale_bascula
  v_src := pg_get_functiondef('public.corregir_vale_bascula(uuid,numeric,numeric,text,text,text,numeric,text,text,numeric,bigint,text,text)'::regprocedure);
  if md5(v_src) <> '797ed596c289029530cc3d74deb9f605' then
    raise exception 'M66: corregir_vale_bascula no es la versión esperada (md5 %)', md5(v_src);
  end if;
  v_ancla := $a$  insert into plantas_vales_historial (vale_id, accion, pedido_anterior_id, pedido_nuevo_id, antes, despues, usuario_email, motivo)$a$;
  v_extra := $b$  -- Migración 66: el acumulado guardado de este vale y de los siguientes
  -- del mismo pedido se recalcula con el peso corregido.
  if v_vale.tipo_vale = 'asfalto' then
    perform plantas_recalcular_acumulados_asfalto(v_vale.pedido_id, v_vale.obra_id, v_vale.fecha_pesada);
    select * into v_vale from plantas_vales where id = p_vale_id;
  end if;

$b$;
  if (length(v_src) - length(replace(v_src, v_ancla, ''))) / length(v_ancla) <> 1 then
    raise exception 'M66: ancla de corregir_vale_bascula no encontrada una sola vez';
  end if;
  execute replace(v_src, v_ancla, v_extra || v_ancla);

  -- anular_vale_bascula
  v_src := pg_get_functiondef('public.anular_vale_bascula(uuid,text)'::regprocedure);
  if md5(v_src) <> '5d321660fcb55d6078fb9afda21e7c7c' then
    raise exception 'M66: anular_vale_bascula no es la versión esperada (md5 %)', md5(v_src);
  end if;
  v_ancla := $a$  insert into plantas_vales_historial (vale_id, accion, pedido_anterior_id, pedido_nuevo_id, motivo, usuario_email)$a$;
  v_extra := $b$  -- Migración 66: los vales siguientes del mismo pedido dejan de sumar el anulado.
  if v_vale.tipo_vale = 'asfalto' then
    perform plantas_recalcular_acumulados_asfalto(v_vale.pedido_id, v_vale.obra_id, v_vale.fecha_pesada);
  end if;

$b$;
  if (length(v_src) - length(replace(v_src, v_ancla, ''))) / length(v_ancla) <> 1 then
    raise exception 'M66: ancla de anular_vale_bascula no encontrada una sola vez';
  end if;
  execute replace(v_src, v_ancla, v_extra || v_ancla);

  -- reasignar_vale_bascula
  v_src := pg_get_functiondef('public.reasignar_vale_bascula(uuid,uuid,text)'::regprocedure);
  if md5(v_src) <> 'cf27eb059bfa765bd729cf8352c93f34' then
    raise exception 'M66: reasignar_vale_bascula no es la versión esperada (md5 %)', md5(v_src);
  end if;
  v_ancla := $a$  update plantas_pedidos
    set nro_remito_global = coalesce(nro_remito_global, nextval('plantas_remitos_numero_seq')::text)
    where id = v_destino.id;$a$;
  v_extra := $b$  -- Migración 66: recalcula el pedido de origen (sin este vale) y el de
  -- destino (con este vale) desde la fecha de la pesada. La obra de origen
  -- sale de la foto previa (el update de arriba ya la reemplazó).
  perform plantas_recalcular_acumulados_asfalto(v_origen.id, (v_aud_antes ->> 'obra_id')::bigint, v_vale.fecha_pesada);
  perform plantas_recalcular_acumulados_asfalto(v_destino.id, v_destino.obra_id, v_vale.fecha_pesada);
  select * into v_vale from plantas_vales where id = p_vale_id;

$b$;
  if (length(v_src) - length(replace(v_src, v_ancla, ''))) / length(v_ancla) <> 1 then
    raise exception 'M66: ancla de reasignar_vale_bascula no encontrada una sola vez';
  end if;
  execute replace(v_src, v_ancla, v_extra || v_ancla);

  -- registrar_pesada_bascula
  v_src := pg_get_functiondef('public.registrar_pesada_bascula(text,numeric,numeric,uuid,bigint,text,text,text,text,timestamptz,text,text,text,numeric,numeric)'::regprocedure);
  if md5(v_src) <> '6b69d3f3499968c8f0d680cd08697e38' then
    raise exception 'M66: registrar_pesada_bascula no es la versión esperada (md5 %)', md5(v_src);
  end if;
  v_ancla := $a$  perform plantas_auditar_vale('CREAR', v_vale.id);$a$;
  v_extra := $b$  -- Migración 66: una pesada con fecha anterior a otras del mismo pedido
  -- corrige el acumulado guardado de las siguientes (en el caso normal no
  -- hay siguientes y no cambia nada).
  if p_tipo_vale = 'asfalto' then
    perform plantas_recalcular_acumulados_asfalto(v_vale.pedido_id, v_vale.obra_id, v_vale.fecha_pesada);
  end if;

$b$;
  if (length(v_src) - length(replace(v_src, v_ancla, ''))) / length(v_ancla) <> 1 then
    raise exception 'M66: ancla de registrar_pesada_bascula no encontrada una sola vez';
  end if;
  execute replace(v_src, v_ancla, v_extra || v_ancla);
end;
$parches$;

-- 3) Datos: los 18 vales que ya quedaron mal
do $datos$
declare
  r record;
  v_actual numeric;
  v_nuevo numeric;
  v_n integer := 0;
begin
  for r in
    select * from (values
      (10213, 76.74), (10276, 37.63),
      (10138, 429.08), (10139, 456.42), (10140, 491.24), (10142, 543.20), (10143, 571.90),
      (10151, 183.31), (10152, 221.59), (10153, 252.95), (10154, 288.45), (10155, 325.05),
      (10156, 363.08), (10157, 397.72), (10158, 434.96), (10159, 470.98), (10162, 580.46),
      (10164, 648.46)
    ) as t(numero_vale, guardado)
  loop
    select v.acumulado_obra_tn, (plantas_acumulado_asfalto(v.pedido_id, v.obra_id, v.fecha_pesada) ->> 'tn')::numeric
      into v_actual, v_nuevo
      from plantas_vales v
      where v.numero_vale = r.numero_vale and v.tipo_vale = 'asfalto' and not v.anulado
      for update;
    if not found then
      raise exception 'M66: el vale % no existe o está anulado', r.numero_vale;
    end if;
    if v_actual is distinct from r.guardado then
      raise exception 'M66: el vale % tiene guardado % (se esperaba %) — revisar antes de aplicar', r.numero_vale, v_actual, r.guardado;
    end if;
    update plantas_vales set acumulado_obra_tn = v_nuevo where numero_vale = r.numero_vale and tipo_vale = 'asfalto';
    v_n := v_n + 1;
  end loop;
  if v_n <> 18 then
    raise exception 'M66: se corrigieron % vales (se esperaban 18)', v_n;
  end if;
end;
$datos$;
$m66$;
  execute $r66$
-- ============================================================================
-- Reversión de la migración 66 (solo si hiciera falta volver atrás).
-- Saca el recálculo de corregir/anular/reasignar/registrar, borra
-- plantas_recalcular_acumulados_asfalto y devuelve a los 18 vales el
-- acumulado guardado que tenían antes.
-- OJO: después de aplicar la 66, cualquier corrección/anulación/reasignación
-- recalcula acumulados de otros vales. Revertir NO deshace esos recálculos
-- (quedan con el valor correcto); solo vuelve atrás los 18 del punto 3.
-- ============================================================================

do $rev$
declare
  v_src text;
  v_extra text;
  v_func text;
begin
  -- corregir_vale_bascula
  v_func := 'public.corregir_vale_bascula(uuid,numeric,numeric,text,text,text,numeric,text,text,numeric,bigint,text,text)';
  v_src := pg_get_functiondef(v_func::regprocedure);
  v_extra := $b$  -- Migración 66: el acumulado guardado de este vale y de los siguientes
  -- del mismo pedido se recalcula con el peso corregido.
  if v_vale.tipo_vale = 'asfalto' then
    perform plantas_recalcular_acumulados_asfalto(v_vale.pedido_id, v_vale.obra_id, v_vale.fecha_pesada);
    select * into v_vale from plantas_vales where id = p_vale_id;
  end if;

$b$;
  if position(v_extra in v_src) = 0 then raise exception 'REV66: corregir_vale_bascula no tiene el bloque de la 66'; end if;
  execute replace(v_src, v_extra, '');

  -- anular_vale_bascula
  v_src := pg_get_functiondef('public.anular_vale_bascula(uuid,text)'::regprocedure);
  v_extra := $b$  -- Migración 66: los vales siguientes del mismo pedido dejan de sumar el anulado.
  if v_vale.tipo_vale = 'asfalto' then
    perform plantas_recalcular_acumulados_asfalto(v_vale.pedido_id, v_vale.obra_id, v_vale.fecha_pesada);
  end if;

$b$;
  if position(v_extra in v_src) = 0 then raise exception 'REV66: anular_vale_bascula no tiene el bloque de la 66'; end if;
  execute replace(v_src, v_extra, '');

  -- reasignar_vale_bascula
  v_src := pg_get_functiondef('public.reasignar_vale_bascula(uuid,uuid,text)'::regprocedure);
  v_extra := $b$  -- Migración 66: recalcula el pedido de origen (sin este vale) y el de
  -- destino (con este vale) desde la fecha de la pesada. La obra de origen
  -- sale de la foto previa (el update de arriba ya la reemplazó).
  perform plantas_recalcular_acumulados_asfalto(v_origen.id, (v_aud_antes ->> 'obra_id')::bigint, v_vale.fecha_pesada);
  perform plantas_recalcular_acumulados_asfalto(v_destino.id, v_destino.obra_id, v_vale.fecha_pesada);
  select * into v_vale from plantas_vales where id = p_vale_id;

$b$;
  if position(v_extra in v_src) = 0 then raise exception 'REV66: reasignar_vale_bascula no tiene el bloque de la 66'; end if;
  execute replace(v_src, v_extra, '');

  -- registrar_pesada_bascula
  v_src := pg_get_functiondef('public.registrar_pesada_bascula(text,numeric,numeric,uuid,bigint,text,text,text,text,timestamptz,text,text,text,numeric,numeric)'::regprocedure);
  v_extra := $b$  -- Migración 66: una pesada con fecha anterior a otras del mismo pedido
  -- corrige el acumulado guardado de las siguientes (en el caso normal no
  -- hay siguientes y no cambia nada).
  if p_tipo_vale = 'asfalto' then
    perform plantas_recalcular_acumulados_asfalto(v_vale.pedido_id, v_vale.obra_id, v_vale.fecha_pesada);
  end if;

$b$;
  if position(v_extra in v_src) = 0 then raise exception 'REV66: registrar_pesada_bascula no tiene el bloque de la 66'; end if;
  execute replace(v_src, v_extra, '');

  -- Controles: vuelven a ser las versiones previas a la 66
  if md5(pg_get_functiondef('public.corregir_vale_bascula(uuid,numeric,numeric,text,text,text,numeric,text,text,numeric,bigint,text,text)'::regprocedure)) <> '797ed596c289029530cc3d74deb9f605'
     or md5(pg_get_functiondef('public.anular_vale_bascula(uuid,text)'::regprocedure)) <> '5d321660fcb55d6078fb9afda21e7c7c'
     or md5(pg_get_functiondef('public.reasignar_vale_bascula(uuid,uuid,text)'::regprocedure)) <> 'cf27eb059bfa765bd729cf8352c93f34'
     or md5(pg_get_functiondef('public.registrar_pesada_bascula(text,numeric,numeric,uuid,bigint,text,text,text,text,timestamptz,text,text,text,numeric,numeric)'::regprocedure)) <> '6b69d3f3499968c8f0d680cd08697e38' then
    raise exception 'REV66: alguna función no quedó igual a la previa a la 66';
  end if;
end;
$rev$;

drop function public.plantas_recalcular_acumulados_asfalto(uuid, bigint, timestamptz);

-- Los 18 vales vuelven al acumulado guardado previo a la 66
update plantas_vales v
  set acumulado_obra_tn = t.guardado
  from (values
    (10213, 76.74), (10276, 37.63),
    (10138, 429.08), (10139, 456.42), (10140, 491.24), (10142, 543.20), (10143, 571.90),
    (10151, 183.31), (10152, 221.59), (10153, 252.95), (10154, 288.45), (10155, 325.05),
    (10156, 363.08), (10157, 397.72), (10158, 434.96), (10159, 470.98), (10162, 580.46),
    (10164, 648.46)
  ) as t(numero_vale, guardado)
  where v.numero_vale = t.numero_vale and v.tipo_vale = 'asfalto';
$r66$;
  select count(*) into v_n from plantas_vales v join dryrev_antes a on a.id = v.id where v.acumulado_obra_tn is distinct from a.guardado;
  if v_n <> 0 then raise exception 'DRY REV FALLA: % vales quedaron distintos', v_n; end if;
  if to_regprocedure('plantas_recalcular_acumulados_asfalto(uuid,bigint,timestamptz)') is not null then raise exception 'DRY REV FALLA: quedó la función'; end if;
  raise exception 'DRYRUN REVERSIÓN 66 OK — 66 aplicada y revertida: las 4 funciones vuelven a su md5 previo, la función nueva no existe, 0 vales distintos de antes';
end;
$dryrev$;
