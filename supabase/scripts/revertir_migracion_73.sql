-- ============================================================================
-- Reversión de la migración 73: registrar_carga_asfalto vuelve a tomar la
-- cantidad tipeada (cuerpo de producción al 28/10/2026, md5
-- 6a1bcee8cdb3ba18529a3ea7f24d5d72). No toca cargas ya registradas.
-- OJO: con el frontend de la 73 publicado, las cargas siguen saliendo de
-- balanza en pantalla; revertir también el frontend si hace falta.
-- ============================================================================
begin;

CREATE OR REPLACE FUNCTION public.registrar_carga_asfalto(p_pedido_id uuid, p_numero_vale text, p_cantidad_tn numeric, p_patente text DEFAULT NULL::text, p_fecha_carga timestamp with time zone DEFAULT now(), p_observaciones text DEFAULT NULL::text)
 RETURNS plantas_cargas_asfalto
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

-- Debe dar 6a1bcee8cdb3ba18529a3ea7f24d5d72 (si no, revisar antes del commit)
select md5(pg_get_functiondef('public.registrar_carga_asfalto(uuid, text, numeric, text, timestamp with time zone, text)'::regprocedure));

commit;
