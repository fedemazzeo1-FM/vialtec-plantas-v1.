-- 28_cierre_rls_kv_store.sql
-- Cierre del hallazgo de seguridad pendiente desde el relevamiento inicial
-- (memory/pending.md, "RLS Maestros/Fórmulas" 2026-09-04/06): kv_store
-- tenía una única policy "Acceso publico kv" (FOR ALL TO public USING
-- true) — cualquiera, autenticado o no, podía leer Y escribir el storage
-- completo del sistema legado (todos los pedidos, vales, stock, etc. en
-- JSON crudo). Quedó abierta a propósito durante la migración porque el
-- legado (produccion.vialtec.app) todavía escribía ahí en vivo — cerrarla
-- antes hubiera roto esa escritura sin ganar nada (memory/pending.md,
-- CHECKLIST_CORTE_FINAL.md punto 8: "recién acá, con el legado apagado").
--
-- 2026-09-07: dominio ya transferido al sistema nuevo, legado decomisionado
-- — es seguro cerrar esto ahora.
--
-- IMPORTANTE — no se puede simplemente denegar todo: `plantas_v_bascula_viva`
-- y `plantas_v_stock_movimientos_viva` (supabase/scripts/vistas_puente_legado_bascula_stock.sql)
-- son vistas `security_invoker = true` que leen kv_store con los permisos
-- del usuario que las consulta (no son SECURITY DEFINER) — Báscula y Stock
-- las consultan en vivo desde el cliente (src/services/stock.service.js,
-- src/modules/bascula/services/bascula.service.js). Si se le quita el
-- SELECT a `authenticated`, esas dos pantallas rompen con "permission
-- denied for table kv_store" en vez de simplemente no mostrar filas
-- "Legado" (que es lo esperado ahora que ya no queda delta pendiente).
--
-- Cierre real: se saca el acceso de `anon`/`public` (nadie sin sesión
-- puede leer ni escribir) y se saca TODA escritura (nadie, ni siquiera
-- autenticado, escribe a kv_store desde el cliente — grep confirmado, cero
-- `.from('kv_store')` en src/). Queda SOLO lectura para `authenticated`,
-- que es lo mínimo que las 2 vistas puente necesitan hasta que se
-- simplifiquen/eliminen (memory/pending.md, limpieza opcional no
-- bloqueante).

begin;

drop policy if exists "Acceso publico kv" on kv_store;

create policy "kv_store: solo lectura autenticada" on kv_store
  for select
  to authenticated
  using (true);

commit;
