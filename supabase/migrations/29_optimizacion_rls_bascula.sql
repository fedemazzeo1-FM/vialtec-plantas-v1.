-- Migración 29: optimización de RLS — Báscula (y de paso Stock/Pedidos, mismo
-- patrón) tardaba ~700ms en listar el historial de una semana con solo ~900
-- vales en toda la tabla (memory/pending.md, pedido de Federico 2026-09-07:
-- "revisa el rendimiento... para identificar y destrabar cualquier cuello de
-- botella").
--
-- DIAGNÓSTICO (medido con EXPLAIN ANALYZE contra producción, rol
-- `authenticated` real, antes de este fix):
--   706ms para `select * from plantas_v_bascula_viva where fecha_pesada >=
--   ... limit 50` — de eso, ~490ms eran `plantas_puede_ver_bascula()`
--   reevaluada UNA VEZ POR CADA FILA de `plantas_vales`/`plantas_ingresos`
--   (908 + 503 = 1411 llamados) y otros ~45ms la policy de
--   `plantas_pedidos` reevaluando `auth.email()`/`current_setting()` fila por
--   fila (188 veces). Causa raíz: ninguna de las dos policies envuelve la
--   función en un `select` — sin eso, Postgres no puede tratarla como un
--   InitPlan (calculado una sola vez) y la re-ejecuta en cada fila del scan,
--   aunque el resultado sea idéntico para las 908 filas (no depende de
--   ninguna columna de la fila). Confirmado además por el propio advisor de
--   Supabase (`auth_rls_initplan`, WARN) sobre 2 de estas policies.
--
-- FIX (patrón oficial de Supabase, sin cambiar ningún comportamiento —
-- mismo resultado exacto para el mismo usuario, ver
-- https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select):
--   1. `plantas_rol_actual()`/`plantas_puede_ver_obra()`: `auth.email()` ->
--      `(select auth.email())` — cachea la lectura del JWT una sola vez por
--      sentencia en vez de una vez por invocación de la función.
--   2. Policies que llaman una función sin argumentos correlados a la fila
--      (`plantas_puede_ver_bascula()`, `plantas_puede_ver_stock()`) —
--      envueltas en `(select ...)` en el propio `USING`, para que Postgres
--      las trate como InitPlan (una sola evaluación para todo el query, no
--      una por fila).
--   3. Policy de `plantas_pedidos` (no usa la función de arriba, tiene el
--      `EXISTS` inline desde la migración 17) — mismo fix, `auth.email()` ->
--      `(select auth.email())` adentro del `EXISTS`.
--   4. `plantas_cargas_asfalto`/`plantas_cargas_hormigon` (migración 23) —
--      mismo patrón con `plantas_puede_ver_obra(obra_id)`, aunque acá el
--      resultado sí varía por fila (depende de `obra_id`): igual se
--      recomienda envolver en `select` (mismo doc de Supabase), Postgres
--      puede reusar el resultado para filas con el mismo `obra_id` en vez de
--      recalcular from scratch.
--
-- VERIFICADO en un `begin; ... rollback;` contra producción antes de
-- aplicar esto de verdad: la misma consulta bajó de 706ms a 13.4ms (~52x)
-- solo con los cambios de plantas_vales/plantas_ingresos/plantas_pedidos —
-- 0 filas de diferencia en el resultado.
--
-- No se tocó `plantas_v_bascula_viva` en sí (las 3 ramas de `kv_store` ya
-- cuestan ~3ms combinadas, no son el cuello de botella real) — la vista
-- puente sigue igual, ver memory/pending.md / CHECKLIST_CORTE_FINAL.md punto
-- 9 para su eventual simplificación (no bloqueante).

-- 1) Funciones: auth.email() -> (select auth.email())
create or replace function public.plantas_rol_actual()
returns text
language sql
stable security definer
set search_path to 'public'
as $function$
  select rol
  from plantas_usuarios_roles
  where email = (select auth.email())
    and activo = true
  limit 1;
$function$;

create or replace function public.plantas_puede_ver_obra(p_obra_id bigint, p_tipo_pedido text default null::text)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $function$
  select exists (
    select 1
    from plantas_usuarios_roles pur
    where pur.email = (select auth.email())
      and pur.activo = true
      and (
        pur.ver_todas_obras = true
        or p_obra_id = any(pur.obra_ids)
        or (p_tipo_pedido = 'venta' and pur.ver_ventas = true)
      )
  );
$function$;

-- 2) Policies: envolver la función (sin argumentos correlados a la fila) en
-- (select ...) para que el planner la trate como InitPlan.
alter policy "plantas_vales: leer segun rol" on public.plantas_vales
  using ((select plantas_puede_ver_bascula()));

alter policy "plantas_ingresos: leer segun rol" on public.plantas_ingresos
  using ((select plantas_puede_ver_bascula()));

alter policy "plantas_stock: leer segun rol" on public.plantas_stock
  using ((select plantas_puede_ver_stock()));

alter policy "plantas_stock_movimientos: leer segun rol" on public.plantas_stock_movimientos
  using ((select plantas_puede_ver_stock()));

alter policy "plantas_cargas_asfalto: leer segun obra" on public.plantas_cargas_asfalto
  using ((select plantas_puede_ver_obra(obra_id)));

alter policy "plantas_cargas_hormigon: leer segun obra" on public.plantas_cargas_hormigon
  using ((select plantas_puede_ver_obra(obra_id)));

-- 3) plantas_usuarios_roles y plantas_pedidos: auth.email() directo en el
-- propio texto de la policy (no pasa por ninguna función) -> (select ...).
alter policy "usuario lee su propio rol" on public.plantas_usuarios_roles
  using (email = (select auth.email()));

alter policy "plantas_pedidos: leer segun obra" on public.plantas_pedidos
  using (
    exists (
      select 1
      from plantas_usuarios_roles pur
      where pur.email = (select auth.email())
        and pur.activo = true
        and (
          pur.ver_todas_obras = true
          or plantas_pedidos.obra_id = any (pur.obra_ids)
          or (plantas_pedidos.tipo_pedido = 'venta' and pur.ver_ventas = true)
        )
    )
  );
