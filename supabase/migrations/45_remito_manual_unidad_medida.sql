-- ============================================================================
-- Migración 45: Unidad de medida en los items del Remito Manual
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- BORRADOR — NO APLICADA. Requiere confirmación explícita de Federico antes
-- de correr en producción (memory/procedimientos.md: cambia schema).
--
-- Pedido de Federico (2026-09-28): en Despachos → Remitos Manuales, poder
-- elegir la unidad de medida de cada item (Tn, Kg, m³, Lts, Unidades), que
-- se guarde y salga impresa en el remito junto a la cantidad.
--
-- La unidad va por ITEM (plantas_remitos_manuales_items), no por remito: un
-- mismo remito puede llevar "20 Unidades | Palets" y "5 Tn | Arena".
--
-- Qué hace:
--   1) Columna nueva plantas_remitos_manuales_items.unidad (text, nullable).
--      Los 17 items existentes quedan en null (se imprimen como antes, solo
--      la cantidad). CHECK con la lista cerrada de unidades — la misma que
--      UNIDADES_REMITO_MANUAL en remitos-manuales.service.js.
--   2) generar_remito_manual() lee v_item->>'unidad', exige unidad cuando
--      el item tiene cantidad, y la devuelve en los items para imprimir.
--      Firma idéntica (p_items jsonb, ...): no cambian los grants. Cuerpo
--      tomado de la definición REAL de producción (pg_get_functiondef,
--      2026-09-28), idéntica a la migración 37.
--
-- Orden de aplicación: DEPLOY PRIMERO, migración después, en la misma
-- ventana. La RPC vieja ignora la clave 'unidad' del JSON (con el frontend
-- nuevo el remito se genera igual, solo que sin unidad). Al revés no: el
-- frontend viejo no manda 'unidad' y la RPC nueva rechaza items con
-- cantidad sin unidad.
--
-- Reversión:
--   volver a crear generar_remito_manual con el cuerpo de la migración 37;
--   alter table plantas_remitos_manuales_items drop column unidad;
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Columna unidad
-- ----------------------------------------------------------------------------
alter table plantas_remitos_manuales_items add column unidad text;

alter table plantas_remitos_manuales_items
  add constraint plantas_remitos_manuales_items_unidad_chk
  check (unidad is null or unidad in ('Tn', 'Kg', 'm³', 'Lts', 'Unidades'));

comment on column plantas_remitos_manuales_items.unidad is
  'Unidad de medida de la cantidad del item (Tn, Kg, m³, Lts, Unidades). Obligatoria si hay cantidad (la valida generar_remito_manual). Null en items anteriores a la migración 45.';

-- ----------------------------------------------------------------------------
-- 2) generar_remito_manual — + unidad por item
-- ----------------------------------------------------------------------------
create or replace function generar_remito_manual(
  p_items         jsonb,
  p_destino       text default null,
  p_patente       text default null,
  p_transportista text default null,
  p_fecha         date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_remito    plantas_remitos_manuales;
  v_item      jsonb;
  v_orden     integer := 0;
  v_items_out jsonb := '[]'::jsonb;
  v_descripcion text;
  v_cantidad    numeric;
  v_unidad      text;
begin
  if not plantas_tiene_permiso('despachos', 'aprobar') then
    raise exception 'Tu rol (%) no puede generar un remito manual.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Agregá al menos un item (cantidad/descripción).';
  end if;

  insert into plantas_remitos_manuales (destino, patente, transportista, fecha, creado_por)
  values (
    nullif(btrim(coalesce(p_destino, '')), ''),
    nullif(btrim(coalesce(p_patente, '')), ''),
    nullif(btrim(coalesce(p_transportista, '')), ''),
    coalesce(p_fecha, current_date),
    auth.email()
  )
  returning * into v_remito;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_descripcion := btrim(coalesce(v_item ->> 'descripcion', ''));
    if v_descripcion = '' then
      raise exception 'Cada item necesita una descripción.';
    end if;
    v_cantidad := nullif(v_item ->> 'cantidad', '')::numeric;
    v_unidad   := nullif(btrim(coalesce(v_item ->> 'unidad', '')), '');
    if v_cantidad is not null and v_unidad is null then
      raise exception 'Elegí la unidad de medida del item "%".', v_descripcion;
    end if;

    insert into plantas_remitos_manuales_items (remito_id, cantidad, unidad, descripcion, orden)
    values (v_remito.id, v_cantidad, v_unidad, v_descripcion, v_orden);

    v_items_out := v_items_out || jsonb_build_object('cantidad', v_cantidad, 'unidad', v_unidad, 'descripcion', v_descripcion);
    v_orden := v_orden + 1;
  end loop;

  return jsonb_build_object('remito', to_jsonb(v_remito), 'items', v_items_out);
end;
$$;

comment on function generar_remito_manual is
  'Genera un remito "en blanco"/manual con N items (cantidad/unidad/descripción, migraciones 37 y 45) — numero_remito automático, misma secuencia que los remitos de asfalto (plantas_remitos_numero_seq). Unidad obligatoria si el item tiene cantidad. Solo admin/plantista.';
