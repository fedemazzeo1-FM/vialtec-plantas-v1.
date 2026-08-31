-- ============================================================================
-- Migración 13: Módulo Stock e Inventarios (MVP)
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Origen: memory/relevamiento-sistema-viejo.md §6 + Etapa 3 "Stock" + auditoría
-- contra Logica sis. plantas v1.rtf §2.3/§4.4 y Logica sist plantas v2.rtf §3.4.
-- Decisiones de diseño aprobadas por Federico (sesión 2026-08-31):
--   1. plantas_materiales suma stock_minimo_kg/stock_maximo_kg (antes solo
--      había mínimo documentado en el legado — el máximo no se encontró en
--      el relevamiento; Federico decidió agregarlo igual, configurable).
--   2. Relevamiento mensual NO pisa el stock directo: calcula diferencia e
--      inserta un movimiento 'ajuste' auditable (se aparta del legado a
--      propósito — el legado hacía overwrite directo sin auditoría).
--   3. Tabla dedicada plantas_stock_movimientos, única fuente de verdad del
--      historial (ingreso proveedor, egreso por despacho, egreso árido
--      directo, manuales, ajustes, recálculo post-corrección).
--   4. Sin DELETE en el historial — regla de auditoría ya aplicada en
--      Pedidos/Báscula/Despachos (memory/business-rules.md).
--   5. corregir_despacho() ajusta stock automáticamente (delta entre
--      cantidadReal vieja y nueva × fórmula) — movimiento 'recalculo_despacho'.
--   6. Analítica de proveedores queda en el Dashboard (sin cambios acá).
--   7. saveStockGuard implementado en registrar_relevamiento_stock (es la
--      operación bulk multi-material que el legado protegía — un movimiento
--      individual de ingreso/egreso/despacho nunca dispara este check, igual
--      que el legado: la guarda es específica del "guardado completo del
--      objeto stock", no de cada operación puntual).
--
-- Fuente de verdad por tipo de movimiento (memory/business-rules.md, ya
-- fijada en la migración 12 y reconfirmada por Federico esta sesión):
--   - Despacho (asfalto/hormigón): plantas_pedidos.cantidad_despachada
--     (remito final de Pedidos) × fórmula. Báscula NO dispara este descuento.
--   - Ingreso de áridos: cantidad DECLARADA EN EL REMITO (no el peso neto).
--   - Egreso de áridos directo: peso neto real de báscula.
--
-- Simplificación deliberada respecto del legado: el "backup automático de
-- emergencia" que saveStockGuard generaba en el sistema viejo (blob JSON con
-- key vt_stockbak_<timestamp>) NO se replica acá — no hay un mecanismo de
-- snapshot/backup en este proyecto todavía (eso es el módulo Backup, PENDIENTE
-- por separado, memory/modules-status.md #11). Acá saveStockGuard bloquea con
-- una excepción clara en vez de bloquear + backuppear; retomar cuando exista
-- Backup si Federico quiere el snapshot real.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) plantas_materiales — catálogo (gap #2 del relevamiento). `nombre` es la
--    clave de matching contra plantas_formulas.insumos/plantas_ingresos.material/
--    plantas_vales.material, que siguen siendo texto libre — no se migran a
--    FK en esta migración (fuera de alcance: tocaría Fórmulas/Báscula/Maestros).
-- ----------------------------------------------------------------------------
create table if not exists plantas_materiales (
  id               uuid primary key default gen_random_uuid(),
  nombre           text not null unique,
  unidad           text,
  categoria        text,
  -- false para Agua/Purgue (memory/business-rules.md: nunca se descuentan) —
  -- esos materiales no llevan card de stock ni movimientos. El match sigue
  -- siendo también por nombre en plantas_descontar_stock_despacho (defensa
  -- en profundidad: aunque alguien cree "Agua" con controla_stock=true por
  -- error, la excepción por nombre igual la protege).
  controla_stock   boolean not null default true,
  stock_minimo_kg  numeric,
  stock_maximo_kg  numeric,
  activo           boolean not null default true,
  created_at       timestamptz not null default now()
);

comment on table plantas_materiales is
  'Catálogo de materiales/insumos de Stock. nombre es la clave de matching (case-insensitive, trim) contra el texto libre de fórmulas/báscula/ingresos — ver plantas_buscar_material_id().';

alter table plantas_materiales enable row level security;
create policy "plantas_materiales: acceso autenticado" on plantas_materiales
  for all to authenticated using (true) with check (true);

-- ----------------------------------------------------------------------------
-- 2) plantas_stock — saldo actual por material, siempre en kg. Se modifica
--    EXCLUSIVAMENTE vía plantas_aplicar_movimiento_stock() — nunca con un
--    UPDATE directo desde el cliente, para no perder el registro en
--    plantas_stock_movimientos.
-- ----------------------------------------------------------------------------
create table if not exists plantas_stock (
  material_id     uuid primary key references plantas_materiales (id),
  cantidad_kg     numeric not null default 0,
  actualizado_en  timestamptz not null default now()
);

comment on table plantas_stock is
  'Saldo actual por material en kg. Escribir siempre vía plantas_aplicar_movimiento_stock(), nunca UPDATE directo.';

alter table plantas_stock enable row level security;
create policy "plantas_stock: acceso autenticado" on plantas_stock
  for all to authenticated using (true) with check (true);

-- ----------------------------------------------------------------------------
-- 3) plantas_stock_movimientos — historial único, append-only (memory/
--    business-rules.md: nunca se elimina — decisión 4). cantidad_kg con
--    signo (+ ingreso, - egreso), para que sumar la columna dé el saldo.
-- ----------------------------------------------------------------------------
create table if not exists plantas_stock_movimientos (
  id               uuid primary key default gen_random_uuid(),
  material_id      uuid not null references plantas_materiales (id),
  tipo             text not null check (tipo in (
                     'ingreso_proveedor', 'egreso_despacho', 'egreso_arido',
                     'ingreso_manual', 'egreso_manual', 'ajuste', 'recalculo_despacho'
                   )),
  cantidad_kg      numeric not null check (cantidad_kg <> 0),
  origen           text,   -- proveedor (ingresos) o motivo (egresos/ajustes)
  numero_remito    text,
  pedido_id        uuid references plantas_pedidos (id),
  vale_id          uuid references plantas_vales (id),
  ingreso_id       uuid references plantas_ingresos (id),
  observaciones    text,
  usuario_id       uuid,
  fecha_movimiento timestamptz not null default now(),
  created_at       timestamptz not null default now()
);

create index if not exists idx_plantas_stock_movimientos_material on plantas_stock_movimientos (material_id, fecha_movimiento desc);
create index if not exists idx_plantas_stock_movimientos_pedido on plantas_stock_movimientos (pedido_id) where pedido_id is not null;

comment on table plantas_stock_movimientos is
  'Historial único y append-only de todos los movimientos de stock: ingreso_proveedor/egreso_arido (Báscula, vía registrar_pesada_bascula), egreso_despacho/recalculo_despacho (Pedidos, vía plantas_descontar_stock_despacho), ingreso_manual/egreso_manual (Stock, registrar_movimiento_manual), ajuste (Stock, registrar_relevamiento_stock).';

alter table plantas_stock_movimientos enable row level security;
create policy "plantas_stock_movimientos: leer" on plantas_stock_movimientos
  for select to authenticated using (true);
create policy "plantas_stock_movimientos: insertar" on plantas_stock_movimientos
  for insert to authenticated with check (true);

-- ----------------------------------------------------------------------------
-- 4) plantas_buscar_material_id — matching por nombre (case-insensitive,
--    trim) contra el texto libre de fórmulas/báscula/ingresos.
-- ----------------------------------------------------------------------------
create or replace function plantas_buscar_material_id(p_nombre text)
returns uuid
language sql
stable
as $$
  select id from plantas_materiales
  where lower(btrim(nombre)) = lower(btrim(coalesce(p_nombre, '')))
  limit 1;
$$;

-- ----------------------------------------------------------------------------
-- 5) plantas_calcular_consumo_kg — gemela SQL de calcularConsumoKg()
--    (src/modules/maestros/services/formulas.service.js). Si se cambia una,
--    cambiar la otra.
-- ----------------------------------------------------------------------------
create or replace function plantas_calcular_consumo_kg(p_insumo jsonb, p_cantidad_producida numeric)
returns numeric
language plpgsql
immutable
as $$
declare
  v_cantidad numeric := coalesce((p_insumo->>'cantidad')::numeric, 0);
  v_unidad   text := p_insumo->>'unidad';
begin
  case v_unidad
    when '%'  then return (v_cantidad / 100) * 1000 * p_cantidad_producida;
    when 'tn' then return v_cantidad * 1000 * p_cantidad_producida;
    when 'kg' then return v_cantidad * p_cantidad_producida;
    when 'L'  then return v_cantidad * p_cantidad_producida;
    else raise exception 'plantas_calcular_consumo_kg: unidad de insumo desconocida "%"', v_unidad;
  end case;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6) plantas_aplicar_movimiento_stock — helper interno (NO se otorga a
--    authenticated: solo lo llaman otras funciones SECURITY DEFINER que ya
--    validaron rol). Aplica el delta a plantas_stock e inserta el
--    movimiento en una sola operación. cantidad_kg=0 es un no-op silencioso
--    (nada que registrar).
-- ----------------------------------------------------------------------------
create or replace function plantas_aplicar_movimiento_stock(
  p_material_id    uuid,
  p_tipo           text,
  p_cantidad_kg    numeric,
  p_origen         text default null,
  p_numero_remito  text default null,
  p_pedido_id      uuid default null,
  p_vale_id        uuid default null,
  p_ingreso_id     uuid default null,
  p_observaciones  text default null
)
returns plantas_stock_movimientos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mov plantas_stock_movimientos;
begin
  if p_cantidad_kg = 0 or p_material_id is null then
    return null;
  end if;

  insert into plantas_stock (material_id, cantidad_kg)
  values (p_material_id, 0)
  on conflict (material_id) do nothing;

  update plantas_stock
    set cantidad_kg = cantidad_kg + p_cantidad_kg,
        actualizado_en = now()
    where material_id = p_material_id;

  insert into plantas_stock_movimientos (
    material_id, tipo, cantidad_kg, origen, numero_remito,
    pedido_id, vale_id, ingreso_id, observaciones, usuario_id
  ) values (
    p_material_id, p_tipo, p_cantidad_kg, p_origen, p_numero_remito,
    p_pedido_id, p_vale_id, p_ingreso_id, p_observaciones, auth.uid()
  )
  returning * into v_mov;

  return v_mov;
end;
$$;

revoke execute on function plantas_aplicar_movimiento_stock(uuid, text, numeric, text, text, uuid, uuid, uuid, text) from public;

-- ----------------------------------------------------------------------------
-- 7) plantas_descontar_stock_despacho — helper interno llamado desde
--    finalizar_despacho() (p_cantidad_anterior=0) y corregir_despacho()
--    (p_cantidad_anterior=valor viejo). Recorre los insumos de la fórmula
--    del pedido, excluye Agua/Purgue por nombre, y aplica el delta ×
--    fórmula a cada material que matchee en plantas_materiales. Si un
--    insumo de la fórmula no tiene material catalogado todavía (gap #2, se
--    sigue escribiendo como texto libre), se SALTEA sin bloquear el
--    despacho — igual criterio que Báscula con material sin catálogo.
-- ----------------------------------------------------------------------------
create or replace function plantas_descontar_stock_despacho(
  p_pedido_id         uuid,
  p_cantidad_anterior numeric,
  p_cantidad_nueva    numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido      plantas_pedidos;
  v_formula     plantas_formulas;
  v_insumo      jsonb;
  v_delta       numeric := coalesce(p_cantidad_nueva, 0) - coalesce(p_cantidad_anterior, 0);
  v_consumo_kg  numeric;
  v_material_id uuid;
  v_tipo        text;
begin
  if v_delta = 0 then
    return;
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id;
  if v_pedido.formula_id is null then
    return;
  end if;
  select * into v_formula from plantas_formulas where id = v_pedido.formula_id;
  if v_formula is null then
    return;
  end if;

  v_tipo := case when coalesce(p_cantidad_anterior, 0) = 0 then 'egreso_despacho' else 'recalculo_despacho' end;

  for v_insumo in select * from jsonb_array_elements(coalesce(v_formula.insumos, '[]'::jsonb))
  loop
    if lower(btrim(coalesce(v_insumo->>'material', ''))) in ('agua', 'purgue') then
      continue;
    end if;

    v_material_id := plantas_buscar_material_id(v_insumo->>'material');
    if v_material_id is null then
      continue;
    end if;

    v_consumo_kg := plantas_calcular_consumo_kg(v_insumo, v_delta);
    perform plantas_aplicar_movimiento_stock(
      v_material_id, v_tipo, -v_consumo_kg, null, null, p_pedido_id, null, null,
      'Fórmula ' || coalesce(v_formula.nombre, '') || ' — pedido ' || p_pedido_id::text
    );
  end loop;
end;
$$;

revoke execute on function plantas_descontar_stock_despacho(uuid, numeric, numeric) from public;

-- ----------------------------------------------------------------------------
-- 8) registrar_movimiento_manual — ingreso/egreso manual desde Stock
--    (Logica sis. plantas v1.rtf §4.4: "Ingreso manual"/"Salida manual").
--    Rol: plantista/admin (mismo criterio que PERMISOS_POR_ROL.stock='editar'
--    en auth.store.js).
-- ----------------------------------------------------------------------------
create or replace function registrar_movimiento_manual(
  p_material_id   uuid,
  p_tipo          text,
  p_cantidad_kg   numeric,
  p_origen        text default null,
  p_numero_remito text default null,
  p_observaciones text default null
)
returns plantas_stock_movimientos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol text;
  v_mov plantas_stock_movimientos;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista') then
    raise exception 'Tu rol (%) no puede registrar movimientos manuales de stock.', coalesce(v_rol, 'sin rol asignado');
  end if;
  if p_tipo not in ('ingreso_manual', 'egreso_manual') then
    raise exception 'tipo inválido: % (esperado ingreso_manual o egreso_manual)', p_tipo;
  end if;
  if not (p_cantidad_kg > 0) then
    raise exception 'cantidad_kg debe ser mayor a 0';
  end if;
  if not exists (select 1 from plantas_materiales where id = p_material_id and controla_stock) then
    raise exception 'El material no existe o no controla stock.';
  end if;

  v_mov := plantas_aplicar_movimiento_stock(
    p_material_id,
    p_tipo,
    case when p_tipo = 'ingreso_manual' then p_cantidad_kg else -p_cantidad_kg end,
    p_origen, p_numero_remito, null, null, null, p_observaciones
  );
  return v_mov;
end;
$$;

comment on function registrar_movimiento_manual is
  'Ingreso o egreso manual de stock (Logica sis. plantas v1.rtf §4.4), solo plantista/admin.';

revoke execute on function registrar_movimiento_manual(uuid, text, numeric, text, text, text) from public;
grant execute on function registrar_movimiento_manual(uuid, text, numeric, text, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 9) registrar_relevamiento_stock — "Relevamiento mensual" (decisión 2:
--    NO pisa directo, calcula diferencia por material e inserta 'ajuste').
--    Implementa saveStockGuard (decisión 7 / Logica sist plantas v2.rtf
--    §"saveStockGuard"): sobre el TOTAL de plantas_stock (no solo los
--    materiales del relevamiento) — <50% de los materiales con valor pasan
--    a no tenerlo, o el total cae >90% → bloquea con excepción.
-- ----------------------------------------------------------------------------
create or replace function registrar_relevamiento_stock(
  p_conteos jsonb,
  p_motivo  text default 'Relevamiento mensual'
)
returns setof plantas_stock_movimientos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol               text;
  v_item              jsonb;
  v_material_id       uuid;
  v_nueva             numeric;
  v_actual            numeric;
  v_total_antes       numeric := 0;
  v_total_despues     numeric := 0;
  v_con_valor_antes   int := 0;
  v_con_valor_despues int := 0;
  v_mov               plantas_stock_movimientos;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista') then
    raise exception 'Tu rol (%) no puede cargar un relevamiento de stock.', coalesce(v_rol, 'sin rol asignado');
  end if;

  select coalesce(sum(cantidad_kg), 0), count(*) filter (where cantidad_kg > 0)
    into v_total_antes, v_con_valor_antes
    from plantas_stock;

  v_total_despues := v_total_antes;
  v_con_valor_despues := v_con_valor_antes;

  for v_item in select * from jsonb_array_elements(p_conteos)
  loop
    v_material_id := (v_item->>'material_id')::uuid;
    v_nueva := (v_item->>'cantidad_kg')::numeric;
    if v_nueva is null or v_nueva < 0 then
      raise exception 'cantidad_kg inválida para el material % (no puede ser negativa).', v_material_id;
    end if;

    select cantidad_kg into v_actual from plantas_stock where material_id = v_material_id;
    v_actual := coalesce(v_actual, 0);

    v_total_despues := v_total_despues - v_actual + v_nueva;
    if v_actual > 0 and v_nueva = 0 then v_con_valor_despues := v_con_valor_despues - 1; end if;
    if v_actual = 0 and v_nueva > 0 then v_con_valor_despues := v_con_valor_despues + 1; end if;
  end loop;

  if v_con_valor_antes > 0 and v_con_valor_despues < (v_con_valor_antes * 0.5) then
    raise exception 'saveStockGuard: el relevamiento deja sin stock a más de la mitad de los materiales que hoy tienen valor (% -> %). Guardado cancelado — revisá los conteos.',
      v_con_valor_antes, v_con_valor_despues;
  end if;
  if v_total_antes > 0 and v_total_despues < (v_total_antes * 0.1) then
    raise exception 'saveStockGuard: el relevamiento hace caer el stock total más de un 90%% (% kg -> % kg). Guardado cancelado — revisá los conteos.',
      v_total_antes, v_total_despues;
  end if;

  for v_item in select * from jsonb_array_elements(p_conteos)
  loop
    v_material_id := (v_item->>'material_id')::uuid;
    v_nueva := (v_item->>'cantidad_kg')::numeric;
    select cantidad_kg into v_actual from plantas_stock where material_id = v_material_id;
    v_actual := coalesce(v_actual, 0);

    if v_nueva <> v_actual then
      v_mov := plantas_aplicar_movimiento_stock(v_material_id, 'ajuste', v_nueva - v_actual, p_motivo, null, null, null, null, null);
      return next v_mov;
    end if;
  end loop;

  return;
end;
$$;

comment on function registrar_relevamiento_stock is
  'Relevamiento mensual (conteo manual): calcula la diferencia contra plantas_stock e inserta un movimiento "ajuste" por cada material que cambió — NO pisa el stock directo (decisión Federico 2026-08-31, se aparta del overwrite del legado). Bloquea con saveStockGuard si el resultado parece anómalo.';

revoke execute on function registrar_relevamiento_stock(jsonb, text) from public;
grant execute on function registrar_relevamiento_stock(jsonb, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 10) finalizar_despacho / corregir_despacho — se agrega el descuento de
--     stock automático (decisión 5). CREATE OR REPLACE con el cuerpo
--     existente + una línea (`perform plantas_descontar_stock_despacho`).
-- ----------------------------------------------------------------------------
create or replace function finalizar_despacho(
  p_pedido_id      uuid,
  p_dividir        boolean default false,
  p_fecha_residual date default null
)
returns plantas_pedidos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol      text;
  v_pedido   plantas_pedidos;
  v_residual numeric;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista', 'plantista_hormigon') then
    raise exception 'Tu rol (%) no puede finalizar un despacho.', coalesce(v_rol, 'sin rol asignado');
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.estado <> 'confirmado' then
    raise exception 'El pedido tiene que estar confirmado para finalizar el despacho (estado actual: %).', v_pedido.estado;
  end if;
  if coalesce(v_pedido.cantidad_despachada, 0) <= 0 then
    raise exception 'Todavía no se cargó ninguna carga para este pedido.';
  end if;

  v_residual := v_pedido.cantidad_solicitada - v_pedido.cantidad_despachada;

  update plantas_pedidos set estado = 'despachado' where id = p_pedido_id;

  -- Descuento de stock (migración 13): primera vez que este pedido toca
  -- stock (anterior=0), por el total acumulado en cantidad_despachada.
  perform plantas_descontar_stock_despacho(p_pedido_id, 0, v_pedido.cantidad_despachada);

  insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id)
  values (p_pedido_id, 'despachado', now(), auth.uid());

  if p_dividir and v_residual > 0 then
    if p_fecha_residual is null then
      raise exception 'Elegí una fecha para el pedido residual.';
    end if;

    declare
      v_nuevo_id uuid;
    begin
      insert into plantas_pedidos (
        obra_id, formula_id, tipo, cantidad_solicitada, fecha_programada, estado,
        tipo_pedido, cliente_externo, encargado, ubicacion, observaciones
      ) values (
        v_pedido.obra_id, v_pedido.formula_id, v_pedido.tipo, v_residual, p_fecha_residual, 'confirmado',
        v_pedido.tipo_pedido, v_pedido.cliente_externo, v_pedido.encargado, v_pedido.ubicacion,
        'Pedido residual generado automáticamente al dividir el despacho del ' || v_pedido.id::text
      )
      returning id into v_nuevo_id;

      insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id, motivo)
      values (v_nuevo_id, 'confirmado', now(), auth.uid(), 'Residual del pedido ' || v_pedido.id::text);
    end;
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id;
  return v_pedido;
end;
$$;

comment on function finalizar_despacho is
  'Cierra un pedido confirmado como despachado con lo cargado hasta el momento, descuenta stock automáticamente (migración 13) y opcionalmente crea un pedido residual confirmado por el saldo.';

create or replace function corregir_despacho(
  p_pedido_id           uuid,
  p_cantidad_despachada numeric default null,
  p_nro_remito_global   text default null,
  p_nro_vale_global     text default null,
  p_notas               text default null
)
returns plantas_pedidos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol            text;
  v_pedido         plantas_pedidos;
  v_diff           jsonb;
  v_cantidad_nueva numeric;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista', 'plantista_hormigon') then
    raise exception 'Tu rol (%) no puede corregir un despacho.', coalesce(v_rol, 'sin rol asignado');
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.estado <> 'despachado' then
    raise exception 'Solo se puede corregir un despacho ya cerrado (estado actual: %).', v_pedido.estado;
  end if;
  if p_cantidad_despachada is not null and not (p_cantidad_despachada > 0) then
    raise exception 'La cantidad corregida debe ser mayor a 0.';
  end if;

  v_cantidad_nueva := coalesce(p_cantidad_despachada, v_pedido.cantidad_despachada);

  v_diff := jsonb_build_object(
    'cantidad_despachada', jsonb_build_object(
      'anterior', v_pedido.cantidad_despachada,
      'nueva', v_cantidad_nueva
    ),
    'nro_remito_global', jsonb_build_object(
      'anterior', v_pedido.nro_remito_global,
      'nuevo', coalesce(p_nro_remito_global, v_pedido.nro_remito_global)
    ),
    'nro_vale_global', jsonb_build_object(
      'anterior', v_pedido.nro_vale_global,
      'nuevo', coalesce(p_nro_vale_global, v_pedido.nro_vale_global)
    )
  );

  update plantas_pedidos
    set cantidad_despachada = v_cantidad_nueva,
        nro_remito_global   = coalesce(p_nro_remito_global, nro_remito_global),
        nro_vale_global     = coalesce(p_nro_vale_global, nro_vale_global)
    where id = p_pedido_id;

  -- Ajuste automático de stock (migración 13, decisión 5): delta entre la
  -- cantidadReal vieja y la nueva, × fórmula — movimiento 'recalculo_despacho'.
  perform plantas_descontar_stock_despacho(p_pedido_id, v_pedido.cantidad_despachada, v_cantidad_nueva);

  insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_id, motivo, datos_legados)
  values (p_pedido_id, 'corregido', now(), auth.uid(), p_notas, v_diff);

  select * into v_pedido from plantas_pedidos where id = p_pedido_id;
  return v_pedido;
end;
$$;

comment on function corregir_despacho is
  'Edita cantidadReal/remito/vale/notas de un despacho ya cerrado (solo plantista/admin), reajusta stock automáticamente por la diferencia (migración 13) y deja todo auditado en plantas_pedidos_historial como evento ''corregido''.';

-- ----------------------------------------------------------------------------
-- 11) registrar_pesada_bascula — se agrega el movimiento de stock para
--     ingreso_arido (cantidad del REMITO, no el peso neto — memory/
--     business-rules.md) y egreso_arido (peso neto real). Firma sin
--     cambios (misma que la versión vigente, sin p_destino: se eliminó en
--     la migración 10). Si el material no matchea contra plantas_materiales
--     todavía, el movimiento de stock se omite sin bloquear el pesaje
--     (mismo criterio que plantas_descontar_stock_despacho).
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
    tipo_vale, pedido_id, obra_id, patente, chofer,
    peso_bruto, tara, peso_neto, unidad, acumulado_obra_tn, fecha_pesada, observaciones,
    temperatura, material
  ) values (
    p_tipo_vale, p_pedido_id, v_obra_id, p_patente, p_chofer,
    p_peso_bruto, p_tara, v_peso_neto, p_unidad, v_acumulado_tn, p_fecha_pesada, p_observaciones,
    p_temperatura,
    case when p_tipo_vale = 'egreso_arido' then p_material else null end
  )
  returning * into v_vale;

  if p_pedido_id is not null and p_tipo_vale = 'asfalto' then
    update plantas_pedidos
      set cantidad_despachada = coalesce(v_pedido.cantidad_despachada, 0) + v_neto_tn,
          estado = case
            when coalesce(v_pedido.cantidad_despachada, 0) + v_neto_tn >= v_pedido.cantidad_solicitada
            then 'despachado' else estado end
      where id = p_pedido_id;
  end if;

  if p_tipo_vale = 'ingreso_arido' then
    insert into plantas_ingresos (
      material, proveedor, numero_remito, cantidad, unidad, origen, vale_id, fecha_ingreso, observaciones
    ) values (
      p_material, p_proveedor, p_numero_remito, coalesce(p_cantidad_remito, v_neto_tn), 'tn',
      'bascula', v_vale.id, p_fecha_pesada, p_observaciones
    )
    returning id into v_ingreso_id;

    -- Stock: suma la cantidad DECLARADA en el remito (no el peso neto) —
    -- memory/business-rules.md, reconfirmado por Federico 2026-08-31.
    v_material_id := plantas_buscar_material_id(p_material);
    if v_material_id is not null then
      perform plantas_aplicar_movimiento_stock(
        v_material_id, 'ingreso_proveedor', coalesce(p_cantidad_remito, v_neto_tn) * 1000,
        p_proveedor, p_numero_remito, null, v_vale.id, v_ingreso_id, null
      );
    end if;
  end if;

  if p_tipo_vale = 'egreso_arido' then
    -- Stock: resta el peso neto real pesado — memory/business-rules.md.
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
  'Registra un vale de báscula y actualiza el pedido asociado (asfalto) y el stock (ingreso_arido/egreso_arido, migración 13) de forma atómica.';

revoke execute on function registrar_pesada_bascula(text, numeric, numeric, uuid, bigint, text, text, text, text, timestamptz, text, text, text, numeric, numeric) from public;
grant execute on function registrar_pesada_bascula(text, numeric, numeric, uuid, bigint, text, text, text, text, timestamptz, text, text, text, numeric, numeric) to authenticated;
