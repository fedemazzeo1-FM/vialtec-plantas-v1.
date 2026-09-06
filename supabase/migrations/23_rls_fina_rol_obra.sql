-- Migración 23: RLS fina por rol/obra (tarea P0.2, memory/pending.md).
--
-- Estado previo a esta migración (auditado en vivo 2026-09-06):
-- - plantas_pedidos YA tiene SELECT filtrado por obra (migración 17) — no
--   se toca acá. Hoy los 22 usuarios reales tienen ver_todas_obras=true,
--   así que el filtro no restringe a nadie todavía (decisión de Federico
--   de no bloquear antes de asignar obra_ids reales persona por persona).
-- - plantas_usuarios_roles ya está bien scopeado (migración 21).
-- - Toda la escritura de Pedidos/Báscula/Stock ya pasa por RPC SECURITY
--   DEFINER (bypassea RLS) — sin política de INSERT/UPDATE/DELETE para
--   `authenticated` en esas tablas, confirmado antes de escribir esto.
--
-- Gaps que cierra esta migración:
-- 1) plantas_cargas_asfalto/hormigon y plantas_pedidos_historial seguían
--    con SELECT sin filtrar (using(true)) — se extiende el mismo criterio
--    de obra que ya usa plantas_pedidos (mismo helper, no duplicado).
-- 2) plantas_vales/plantas_ingresos (detalle de Báscula) y plantas_stock/
--    plantas_stock_movimientos seguían legibles por cualquier autenticado
--    aunque su pantalla ni siquiera aparece en el menú de encargado/
--    supervisor/plantista_hormigon (PERMISOS_POR_ROL, src/stores/auth.store.js)
--    — se restringe por rol.
-- 3) plantas_formulas/materiales/patentes/proveedores/choferes/encargados
--    aceptaban INSERT/UPDATE/DELETE de cualquier autenticado (confirmado
--    en código: maestros.service.js/formulas.service.js escriben directo,
--    sin RPC) — se restringe la escritura a admin/plantista. Fórmulas y
--    materiales afectan el cálculo de consumo/descuento de stock, así que
--    era el gap de mayor riesgo real de los tres.
--
-- Impacto esperado: sin cambio visible en los gaps de "obra" (todos con
-- ver_todas_obras=true hoy); cambio real e inmediato en Báscula/Stock
-- (encargado/supervisor/plantista_hormigon dejan de poder leerlas por API
-- directa, ya no las veían en el menú) y en los catálogos (solo admin/
-- plantista pueden escribir).

-- ---------------------------------------------------------------------------
-- Helpers (mismo patrón que plantas_rol_actual(), STABLE SECURITY DEFINER
-- para poder leer plantas_usuarios_roles desde una policy sin RLS circular).
-- ---------------------------------------------------------------------------

create or replace function public.plantas_puede_ver_bascula()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select plantas_rol_actual() in ('admin', 'plantista', 'balancero');
$$;

create or replace function public.plantas_puede_ver_stock()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select plantas_rol_actual() in ('admin', 'plantista', 'balancero', 'gerencia');
$$;

-- Misma fórmula que ya usa la policy de plantas_pedidos (migración 17),
-- extraída a función para no duplicarla en cada tabla nueva que cuelga de
-- un pedido/obra.
create or replace function public.plantas_puede_ver_obra(p_obra_id bigint, p_tipo_pedido text default null)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1
    from plantas_usuarios_roles pur
    where pur.email = auth.email()
      and pur.activo = true
      and (
        pur.ver_todas_obras = true
        or p_obra_id = any(pur.obra_ids)
        or (p_tipo_pedido = 'venta' and pur.ver_ventas = true)
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- 1) Cargas de asfalto/hormigón y historial de pedidos: filtro por obra.
-- ---------------------------------------------------------------------------

drop policy if exists "plantas_cargas_asfalto: leer" on plantas_cargas_asfalto;
create policy "plantas_cargas_asfalto: leer segun obra" on plantas_cargas_asfalto
  for select to authenticated
  using (plantas_puede_ver_obra(obra_id));

drop policy if exists "plantas_cargas_hormigon: leer" on plantas_cargas_hormigon;
create policy "plantas_cargas_hormigon: leer segun obra" on plantas_cargas_hormigon
  for select to authenticated
  using (plantas_puede_ver_obra(obra_id));

drop policy if exists "plantas_pedidos_historial: leer" on plantas_pedidos_historial;
create policy "plantas_pedidos_historial: leer segun obra" on plantas_pedidos_historial
  for select to authenticated
  using (
    exists (
      select 1 from plantas_pedidos pp
      where pp.id = plantas_pedidos_historial.pedido_id
        and plantas_puede_ver_obra(pp.obra_id, pp.tipo_pedido)
    )
  );

-- ---------------------------------------------------------------------------
-- 2) Báscula (vales/ingresos) y Stock: filtro por rol (tabs de
--    PERMISOS_POR_ROL, src/stores/auth.store.js).
-- ---------------------------------------------------------------------------

drop policy if exists "plantas_vales: leer" on plantas_vales;
create policy "plantas_vales: leer segun rol" on plantas_vales
  for select to authenticated
  using (plantas_puede_ver_bascula());

drop policy if exists "plantas_ingresos: leer" on plantas_ingresos;
create policy "plantas_ingresos: leer segun rol" on plantas_ingresos
  for select to authenticated
  using (plantas_puede_ver_bascula());

drop policy if exists "plantas_stock: leer" on plantas_stock;
create policy "plantas_stock: leer segun rol" on plantas_stock
  for select to authenticated
  using (plantas_puede_ver_stock());

drop policy if exists "plantas_stock_movimientos: leer" on plantas_stock_movimientos;
create policy "plantas_stock_movimientos: leer segun rol" on plantas_stock_movimientos
  for select to authenticated
  using (plantas_puede_ver_stock());

-- ---------------------------------------------------------------------------
-- 3) Catálogos de Maestros: lectura abierta (la necesitan varios roles
--    para dropdowns), escritura restringida a admin/plantista. Reemplaza
--    la policy "ALL using(true)" de cada tabla por 4 policies separadas
--    (select/insert/update/delete) — "ALL" no permite dejar el SELECT
--    abierto y la escritura cerrada en una sola policy.
-- ---------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array['plantas_formulas', 'plantas_materiales', 'plantas_patentes', 'plantas_proveedores', 'plantas_choferes', 'plantas_encargados']
  loop
    execute format('drop policy if exists %I on %I', t || ': acceso autenticado', t);

    execute format(
      'create policy %I on %I for select to authenticated using (true)',
      t || ': leer', t
    );
    execute format(
      'create policy %I on %I for insert to authenticated with check (plantas_rol_actual() in (%L, %L))',
      t || ': crear admin/plantista', t, 'admin', 'plantista'
    );
    execute format(
      'create policy %I on %I for update to authenticated using (plantas_rol_actual() in (%L, %L)) with check (plantas_rol_actual() in (%L, %L))',
      t || ': editar admin/plantista', t, 'admin', 'plantista', 'admin', 'plantista'
    );
    execute format(
      'create policy %I on %I for delete to authenticated using (plantas_rol_actual() in (%L, %L))',
      t || ': borrar admin/plantista', t, 'admin', 'plantista'
    );
  end loop;
end $$;
