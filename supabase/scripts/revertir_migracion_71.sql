-- ============================================================================
-- Reversión de la migración 71. Vuelve registrar_carga_hormigon a la firma de
-- 7 parámetros (md5 865c753f93641fb08a5fbde915cad25d) y la vista
-- plantas_v_despachos_camion a su definición anterior (mixer = 'hormigon',
-- 'm3', fecha_carga).
-- La columna plantas_cargas_hormigon.fecha_despacho NO se borra (perdería las
-- fechas ya cargadas); si se quiere borrar, hacerlo aparte a propósito.
-- OJO: con el frontend de la 71 deployado, revertir rompe "Registrar despacho"
-- de mixer (manda p_fecha_despacho). Revertir también el frontend.
-- ============================================================================
begin;

do $rev$
declare
  v_def   text := pg_get_functiondef('public.registrar_carga_hormigon(uuid, text, numeric, text, text, timestamp with time zone, text, date)'::regprocedure);
  c_reempl constant text[][] := array[
    array[$a$p_observaciones text DEFAULT NULL::text, p_fecha_despacho date DEFAULT NULL::date)$a$,
          $a$p_observaciones text DEFAULT NULL::text)$a$],
    array[$a$  if p_fecha_despacho > (now() at time zone 'America/Argentina/Buenos_Aires')::date then
    raise exception 'La fecha de despacho no puede ser futura.';
  end if;
  if v_pedido.estado <> 'confirmado' then$a$,
          $a$  if v_pedido.estado <> 'confirmado' then$a$],
    array[$a$pedido_id, obra_id, numero_remito, volumen_m3, patente_mixer, chofer, fecha_carga, observaciones, fecha_despacho
  ) values ($a$,
          $a$pedido_id, obra_id, numero_remito, volumen_m3, patente_mixer, chofer, fecha_carga, observaciones
  ) values ($a$],
    array[$a$p_patente_mixer, p_chofer, p_fecha_carga, p_observaciones, p_fecha_despacho
  )$a$,
          $a$p_patente_mixer, p_chofer, p_fecha_carga, p_observaciones
  )$a$]
  ];
  i int;
begin
  for i in 1 .. array_length(c_reempl, 1) loop
    if position(c_reempl[i][1] in v_def) = 0 then
      raise exception 'Reversión 71: no se encontró el parche %', i;
    end if;
    v_def := replace(v_def, c_reempl[i][1], c_reempl[i][2]);
  end loop;
  drop function public.registrar_carga_hormigon(uuid, text, numeric, text, text, timestamp with time zone, text, date);
  execute v_def;
  if md5(pg_get_functiondef('public.registrar_carga_hormigon(uuid, text, numeric, text, text, timestamp with time zone, text)'::regprocedure))
     <> '865c753f93641fb08a5fbde915cad25d' then
    raise exception 'Reversión 71: el cuerpo no quedó como el original';
  end if;
end;
$rev$;

revoke execute on function public.registrar_carga_hormigon(uuid, text, numeric, text, text, timestamp with time zone, text) from public, anon;
grant execute on function public.registrar_carga_hormigon(uuid, text, numeric, text, text, timestamp with time zone, text) to authenticated;

create or replace view public.plantas_v_despachos_camion with (security_invoker = true) as
 SELECT 'asfalto'::text AS material,
    v.fecha_pesada AS fecha,
    v.obra_id,
    v.pedido_id,
    v.patente,
    v.chofer,
    (v.numero_vale)::text AS numero_remito,
    v.peso_neto AS volumen,
    v.unidad AS unidad_volumen
   FROM plantas_vales v
  WHERE (v.tipo_vale = 'asfalto'::text)
UNION ALL
 SELECT 'asfalto'::text AS material,
    ca.fecha_carga AS fecha,
    ca.obra_id,
    ca.pedido_id,
    ca.patente,
    NULL::text AS chofer,
    ca.numero_vale AS numero_remito,
    ca.cantidad_tn AS volumen,
    'tn'::text AS unidad_volumen
   FROM plantas_cargas_asfalto ca
UNION ALL
 SELECT 'hormigon'::text AS material,
    c.fecha_carga AS fecha,
    c.obra_id,
    c.pedido_id,
    c.patente_mixer AS patente,
    c.chofer,
    c.numero_remito,
    c.volumen_m3 AS volumen,
    'm3'::text AS unidad_volumen
   FROM plantas_cargas_hormigon c;

commit;
