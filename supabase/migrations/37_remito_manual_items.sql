-- ============================================================================
-- Migración 37: Remito Manual con items (cantidad/descripción) + limpieza
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Pedido de Federico (2026-09-09), sobre el Remito Manual recién armado
-- (migración 36): en vez de una única "Descripción" de texto libre, poder
-- cargar VARIOS renglones tipo "Cantidad | Descripción" (ej. "20 | Palets",
-- "5 | Bolsas de cemento"), con un botón para agregar más — mismo patrón
-- multi-fila que ya usan los despachos multi-camión (useDespachoAsfalto.js/
-- useCargaHormigon.js, "+ Agregar carga"). Tabla relacional nueva en vez de
-- un array JSON suelto (memory/CLAUDE.md: el proyecto viene justamente de
-- migrar del modelo de blobs JSON del legado a tablas relacionales reales,
-- no tiene sentido reintroducir ese patrón acá).
--
-- También pide borrar el remito de prueba que generó al armar la
-- funcionalidad (numero_remito = 1) y que la numeración se vea con cero a
-- la izquierda (eso es puramente de presentación, se resuelve en el
-- frontend con un formatter — RemitoImprimible.vue/formato-numeros.js — no
-- hace falta cambiar el tipo de columna).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) plantas_remitos_manuales_items — un remito manual puede tener N items.
--    Mismo criterio de auditoría que el resto (nunca se edita/borra desde la
--    UI, solo se crea vía la RPC de abajo — sin policy de insert/update/
--    delete directa para `authenticated`).
-- ----------------------------------------------------------------------------
create table if not exists plantas_remitos_manuales_items (
  id          uuid primary key default gen_random_uuid(),
  remito_id   uuid not null references plantas_remitos_manuales (id) on delete cascade,
  cantidad    numeric,
  descripcion text not null,
  orden       integer not null default 0,
  created_at  timestamptz not null default now()
);

comment on table plantas_remitos_manuales_items is
  'Items (cantidad/descripción) de un remito manual/en blanco — reemplaza la columna única plantas_remitos_manuales.descripcion (migración 36), que se dropea en esta misma migración. Solo se crea vía generar_remito_manual() (RPC).';

create index if not exists idx_remitos_manuales_items_remito on plantas_remitos_manuales_items (remito_id);

alter table plantas_remitos_manuales_items enable row level security;

create policy "plantas_remitos_manuales_items: leer" on plantas_remitos_manuales_items
  for select to authenticated using (true);

-- ----------------------------------------------------------------------------
-- 2) plantas_remitos_manuales — la columna descripcion queda superada por
--    los items de arriba.
-- ----------------------------------------------------------------------------
alter table plantas_remitos_manuales drop column if exists descripcion;

-- ----------------------------------------------------------------------------
-- 3) generar_remito_manual — reemplaza p_descripcion (text) por p_items
--    (jsonb, array de {cantidad, descripcion}). Inserta el remito + todos
--    sus items en la misma transacción y devuelve todo junto (jsonb) para
--    que el frontend pueda imprimir sin una segunda consulta.
-- ----------------------------------------------------------------------------

drop function if exists generar_remito_manual(text, text, text, text, date);

create function generar_remito_manual(
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

    insert into plantas_remitos_manuales_items (remito_id, cantidad, descripcion, orden)
    values (v_remito.id, v_cantidad, v_descripcion, v_orden);

    v_items_out := v_items_out || jsonb_build_object('cantidad', v_cantidad, 'descripcion', v_descripcion);
    v_orden := v_orden + 1;
  end loop;

  return jsonb_build_object('remito', to_jsonb(v_remito), 'items', v_items_out);
end;
$$;

comment on function generar_remito_manual is
  'Genera un remito "en blanco"/manual con N items (cantidad/descripción, migración 37) — numero_remito automático, misma secuencia que los remitos de asfalto (plantas_remitos_numero_seq). Solo admin/plantista.';

revoke execute on function generar_remito_manual(jsonb, text, text, text, date) from public;
grant execute on function generar_remito_manual(jsonb, text, text, text, date) to authenticated;

-- ----------------------------------------------------------------------------
-- 4) Limpieza de datos: borra el remito de prueba (numero_remito = 1,
--    generado por Federico probando la funcionalidad recién armada) y
--    reinicia la secuencia a 1 — es el único consumidor que tuvo hasta
--    ahora (ningún despacho de asfalto real llegó a usarla todavía), así
--    que el próximo remito real (manual o de un despacho) va a arrancar
--    limpio en 00001, tal como pidió Federico. Pedido explícito de
--    Federico ("borra el que hice de prueba, el 1") — memory/procedimientos.md:
--    esto sí es un DELETE real, pero sobre 1 fila de prueba identificada
--    explícitamente por él, no un borrado masivo.
-- ----------------------------------------------------------------------------
delete from plantas_remitos_manuales where numero_remito = 1;
alter sequence plantas_remitos_numero_seq restart with 1;
