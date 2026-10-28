-- ============================================================================
-- Migración 72 — usuarios sin sesión (anon) sin permisos de tabla en plantas_*
-- ESTADO: APLICADA en producción el 2026-10-28 con OK de Federico (extendida a todas las
-- tablas y vistas plantas_*; dry-run OK).
-- Dry-run: supabase/scripts/dry_run_migracion_72.sql.
-- Reversión: supabase/scripts/revertir_migracion_72.sql.
-- ============================================================================
--
-- Origen: diagnóstico del 28/10 (lecturas sin sesión del 26/10 desde la
-- pantalla Auditoría con la sesión vencida). anon tiene SELECT, INSERT,
-- UPDATE, DELETE, TRUNCATE, REFERENCES y TRIGGER sobre las 25 tablas y vistas
-- plantas_* (grant por defecto de Supabase). Hoy solo las frena la RLS (y
-- TRUNCATE no pasa por RLS).
--
-- Qué hace: revoke de todo a anon en las 25 (mismo criterio que las tandas de
-- flota). authenticated y service_role no cambian. No toca funciones (sus
-- EXECUTE ya se revisaron en las migraciones 43 y 51) ni tablas flota_*.
--
-- Efecto esperado en la app: ninguno. La app lee plantas_* solo con sesión.
-- Una pestaña con la sesión vencida pasa de recibir 0 filas (200) a un 401,
-- igual que ya pasa con flota_obras. obras_remitos_plantas (Obras) lee la
-- vista de despachos dentro de una función SECURITY DEFINER: no cambia.
--
-- Tablas nuevas plantas_* que se creen después vuelven a recibir el grant
-- por defecto: revocar a anon en la migración que las cree.
-- ============================================================================

revoke all on table
  public.plantas_cargas_asfalto,
  public.plantas_cargas_hormigon,
  public.plantas_choferes,
  public.plantas_clientes,
  public.plantas_encargados,
  public.plantas_formulas,
  public.plantas_ingresos,
  public.plantas_materiales,
  public.plantas_obras_locales,
  public.plantas_patentes,
  public.plantas_pedidos,
  public.plantas_pedidos_historial,
  public.plantas_permisos,
  public.plantas_proveedores,
  public.plantas_remitos_manuales,
  public.plantas_remitos_manuales_items,
  public.plantas_roles,
  public.plantas_stock,
  public.plantas_stock_movimientos,
  public.plantas_usuarios_roles,
  public.plantas_vales,
  public.plantas_v_bascula_viva,
  public.plantas_v_despachos_camion,
  public.plantas_v_obras_visibles,
  public.plantas_v_stock_movimientos_viva
from anon;

-- Chequeo después de aplicar (debe dar 0 filas):
--   select table_name, privilege_type from information_schema.role_table_grants
--    where grantee = 'anon' and table_schema = 'public' and table_name like 'plantas\_%';
