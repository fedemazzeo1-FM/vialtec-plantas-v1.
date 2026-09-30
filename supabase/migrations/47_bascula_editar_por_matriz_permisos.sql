-- ============================================================================
-- Migración 47: Editar/Eliminar vales de Báscula según la matriz de Roles
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Pedido de Federico (2026-09-30): habilitar "Editar" pesadas al rol
-- balancero.
--
-- Diagnóstico: la matriz de Roles (plantas_permisos, migración 26) YA tenía
-- balancero bascula:editar = true, pero ni corregir_vale_bascula() ni el
-- botón de la UI la leían: las dos tenían fijo `rol in ('admin','plantista')`
-- (migración 31). A la vez la matriz decía plantista bascula:editar = false y
-- bascula:eliminar = false, al revés de lo que el código dejaba hacer.
--
-- Qué hace:
--   1) corregir_vale_bascula() valida plantas_tiene_permiso('bascula','editar')
--      y anular_vale_bascula() valida plantas_tiene_permiso('bascula','eliminar')
--      (admin sigue con bypass total, igual que en todo el resto).
--   2) Para no quitarle nada a plantista, se habilitan plantista
--      bascula:editar y bascula:eliminar en la matriz (hoy los usa: Daniel y
--      Felix anularon 7 vales en los últimos 10 días).
--      Resultado: editar = admin, plantista, balancero; eliminar (anular) =
--      admin, plantista. Cambiable después desde la matriz sin migración.
--   3) Revoca EXECUTE a anon en las dos (auditoría 2026-09-19; validan rol
--      adentro, pero no hace falta exponerlas).
--
-- Cuerpos tomados de pg_get_functiondef de producción (2026-09-30); solo
-- cambia el chequeo de rol. Orden: aplicar esta migración ANTES del deploy
-- del frontend (si no, balancero ve el botón y el servidor lo rechaza).
--
-- Reversión: volver a correr las funciones de la migración 42 y
--   update plantas_permisos set habilitado = false
--   where rol_id = 'plantista' and modulo = 'bascula' and accion in ('editar','eliminar');
-- ============================================================================

update plantas_permisos set habilitado = true
where rol_id = 'plantista' and modulo = 'bascula' and accion in ('editar', 'eliminar');

create or replace function public.corregir_vale_bascula(p_vale_id uuid, p_peso_bruto numeric, p_tara numeric, p_patente text default null::text, p_chofer text default null::text, p_observaciones text default null::text, p_temperatura numeric default null::numeric, p_proveedor text default null::text, p_numero_remito text default null::text, p_cantidad_remito numeric default null::numeric, p_obra_id bigint default null::bigint)
 returns plantas_vales
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_vale        plantas_vales;
  v_peso_neto   numeric;
  v_neto_tn     numeric;
  v_material_id uuid;
begin
  if not plantas_tiene_permiso('bascula', 'editar') then
    raise exception 'Tu rol (%) no puede editar vales de báscula.', coalesce(plantas_rol_actual(), 'sin rol asignado');
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
$function$;

create or replace function public.anular_vale_bascula(p_vale_id uuid, p_motivo text)
 returns plantas_vales
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
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
$function$;

revoke execute on function corregir_vale_bascula(uuid, numeric, numeric, text, text, text, numeric, text, text, numeric, bigint) from public, anon;
grant execute on function corregir_vale_bascula(uuid, numeric, numeric, text, text, text, numeric, text, text, numeric, bigint) to authenticated;
revoke execute on function anular_vale_bascula(uuid, text) from public, anon;
grant execute on function anular_vale_bascula(uuid, text) to authenticated;
