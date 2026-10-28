-- ============================================================================
-- Migración 72 — usuarios sin sesión (anon) sin permisos de tabla en
-- plantas_formulas y plantas_usuarios_roles
-- ESTADO: BORRADOR, preparada (pedido de Federico 28/10/2026: no correr todavía).
-- Dry-run: supabase/scripts/dry_run_migracion_72.sql.
-- Reversión: supabase/scripts/revertir_migracion_72.sql.
-- ============================================================================
--
-- Origen: diagnóstico del 28/10 (lecturas sin sesión del 26/10 desde la
-- pantalla Auditoría con la sesión vencida). anon tiene SELECT, INSERT,
-- UPDATE, DELETE, TRUNCATE, REFERENCES y TRIGGER sobre estas dos tablas (grant
-- por defecto de Supabase). Hoy solo las frena la RLS: lectura solo para
-- authenticated y escritura de fórmulas por la matriz de permisos. TRUNCATE no
-- pasa por RLS.
--
-- Qué hace: revoke de todo a anon en las dos tablas (mismo criterio que las
-- tandas de flota). authenticated y service_role no cambian.
--
-- Efecto esperado en la app: ninguno. La app lee estas tablas solo con sesión
-- (login, perfil, Fórmulas, Auditoría). Una pestaña con la sesión vencida pasa
-- de recibir 0 filas (200) a un 401, igual que ya pasa con flota_obras.
--
-- OJO: anon tiene los mismos permisos en las otras 23 tablas y vistas
-- plantas_* (lista en memory/pending.md). Esta migración cubre solo las dos
-- pedidas; extenderla es otra decisión.
-- ============================================================================

revoke all on table public.plantas_formulas from anon;
revoke all on table public.plantas_usuarios_roles from anon;

-- Chequeo después de aplicar (debe dar 0 filas):
--   select table_name, privilege_type from information_schema.role_table_grants
--    where grantee = 'anon' and table_name in ('plantas_formulas', 'plantas_usuarios_roles');
