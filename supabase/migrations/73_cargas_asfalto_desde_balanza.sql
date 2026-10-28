-- ============================================================================
-- Migración 73 — cargas de asfalto desde los vales de balanza
-- ESTADO: BORRADOR, sin correr (Federico, 28/10/2026: dry-run y aplicación
-- juntos en la próxima sesión). Dry-run: supabase/scripts/dry_run_migracion_73.sql.
-- Reversión: supabase/scripts/revertir_migracion_73.sql.
-- ============================================================================
--
-- Origen: P-0264 (vale 10288) y P-0273 (vale 10312) se cargaron en "Registrar
-- despacho" con el peso BRUTO del camión en vez del neto (tipeado a mano).
-- Propuesta aprobada por Federico el 28/10: las cargas salen de los vales de
-- balanza del pedido y no se tipean.
--
-- Qué hace (registrar_carga_asfalto, misma firma; se recrea el cuerpo entero
-- con control del md5 de producción):
--   - Si el N° de vale existe en balanza (asfalto):
--       · rechaza si está anulado o si es de otro pedido;
--       · la cantidad y la patente salen del vale (peso_neto, patente): lo
--         que mande el cliente en p_cantidad_tn se ignora.
--   - Si el vale NO existe en balanza: solo se acepta con motivo
--     (p_observaciones) y la carga se audita con ese motivo ("Carga sin vale
--     de balanza: …"). La cantidad es la tipeada.
--   - Rechaza cargar dos veces el mismo vale en el mismo pedido.
-- Roles, estado del pedido y suma a cantidad_despachada: igual que antes.
-- Permisos: create or replace conserva los grants (authenticated sí, anon no).
-- ============================================================================
do $mig$
begin
  if md5(pg_get_functiondef('public.registrar_carga_asfalto(uuid, text, numeric, text, timestamp with time zone, text)'::regprocedure))
     <> '6a1bcee8cdb3ba18529a3ea7f24d5d72' then
    raise exception 'registrar_carga_asfalto cambió en producción: revisar antes de aplicar la 73';
  end if;
end;
$mig$;

create or replace function public.registrar_carga_asfalto(p_pedido_id uuid, p_numero_vale text, p_cantidad_tn numeric, p_patente text DEFAULT NULL::text, p_fecha_carga timestamp with time zone DEFAULT now(), p_observaciones text DEFAULT NULL::text)
 RETURNS plantas_cargas_asfalto
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_rol       text;
  v_pedido    plantas_pedidos;
  v_carga     plantas_cargas_asfalto;
  v_vale      plantas_vales;
  v_numero    text := btrim(coalesce(p_numero_vale, ''));
  v_cantidad  numeric;
  v_patente   text;
  v_motivo    text;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista') then
    raise exception 'Tu rol (%) no puede registrar cargas de asfalto.', coalesce(v_rol, 'sin rol asignado');
  end if;

  if v_numero = '' then
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

  if exists (select 1 from plantas_cargas_asfalto where pedido_id = p_pedido_id and numero_vale = v_numero) then
    raise exception 'El vale % ya está cargado en este pedido.', v_numero;
  end if;

  -- Migración 73: la carga sale del vale de balanza (no se tipea).
  select * into v_vale from plantas_vales
   where tipo_vale = 'asfalto' and numero_vale::text = v_numero
   limit 1;

  if found then
    if v_vale.anulado then
      raise exception 'El vale % está anulado en balanza.', v_numero;
    end if;
    if v_vale.pedido_id is distinct from p_pedido_id then
      raise exception 'El vale % es de otro pedido (%).', v_numero,
        coalesce(plantas_etiqueta_pedido((select numero from plantas_pedidos where id = v_vale.pedido_id)), 'sin pedido');
    end if;
    v_cantidad := v_vale.peso_neto;
    v_patente  := coalesce(v_vale.patente, p_patente);
  else
    if btrim(coalesce(p_observaciones, '')) = '' then
      raise exception 'El vale % no está en balanza: indicá el motivo para cargarlo a mano.', v_numero;
    end if;
    if not (p_cantidad_tn > 0) then
      raise exception 'cantidad_tn debe ser mayor a 0';
    end if;
    v_cantidad := p_cantidad_tn;
    v_patente  := p_patente;
    v_motivo   := 'Carga sin vale de balanza: ' || btrim(p_observaciones);
  end if;

  if not (v_cantidad > 0) then
    raise exception 'El vale % no tiene peso neto.', v_numero;
  end if;

  insert into plantas_cargas_asfalto (
    pedido_id, obra_id, numero_vale, cantidad_tn, patente, fecha_carga, observaciones
  ) values (
    v_pedido.id, v_pedido.obra_id, v_numero, v_cantidad, v_patente, p_fecha_carga, coalesce(v_motivo, p_observaciones)
  )
  returning * into v_carga;

  update plantas_pedidos
    set cantidad_despachada = coalesce(v_pedido.cantidad_despachada, 0) + v_cantidad
    where id = p_pedido_id;

  perform plantas_auditar('CREAR', 'despachos', 'carga_asfalto', v_carga.numero_vale,
    'Carga vale ' || v_carga.numero_vale || ' — ' || plantas_auditoria_label_pedido(p_pedido_id), v_motivo, null, to_jsonb(v_carga));

  return v_carga;
end;
$function$;

revoke execute on function public.registrar_carga_asfalto(uuid, text, numeric, text, timestamp with time zone, text) from public, anon;
grant execute on function public.registrar_carga_asfalto(uuid, text, numeric, text, timestamp with time zone, text) to authenticated;
