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
