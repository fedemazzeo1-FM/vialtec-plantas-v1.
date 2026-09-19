-- ============================================================================
-- Migración 43: cierre de 2 hallazgos críticos de la auditoría de 2026-09-19
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Autorizada por Federico (2026-09-19) tras la revisión general del sistema.
--
-- 1) Helpers internos de stock ejecutables desde la API.
--    plantas_aplicar_movimiento_stock, plantas_descontar_stock_despacho y
--    plantas_recalcular_stock_vale son SECURITY DEFINER, no validan rol y
--    tenían EXECUTE para anon y authenticated (ACL por defecto de Supabase:
--    `revoke ... from public` de las migraciones 13/22/31 NO alcanzaba, porque
--    anon/authenticated tienen grant propio). Cualquiera con la anon key
--    pública podía llamarlas por /rest/v1/rpc/... y mover stock real,
--    saltándose la RLS fina de la migración 23.
--    Se revoca EXECUTE a anon, authenticated y public. Los únicos llamadores
--    (anular_vale_bascula, corregir_vale_bascula, corregir_despacho,
--    finalizar_despacho, registrar_movimiento_manual, registrar_pesada_bascula,
--    registrar_relevamiento_stock) son SECURITY DEFINER con dueño postgres, así
--    que siguen funcionando (verificado en pg_proc antes de escribir esto: no
--    hay triggers ni vistas que las usen). service_role conserva su grant.
--
-- 2) Vistas que se saltaban la RLS.
--    plantas_v_stock_movimientos_viva y plantas_v_despachos_camion no tenían
--    security_invoker: se ejecutaban con los permisos del dueño y anon tenía
--    SELECT, así que un usuario SIN login leía 1382 movimientos de stock (con
--    responsable_email) y 614 despachos por camión (patentes, choferes,
--    remitos). Con security_invoker = true aplica la RLS del usuario que
--    consulta (mismo criterio que ya tienen plantas_v_bascula_viva y
--    plantas_v_obras_visibles).
--
-- Reversión:
--   grant execute on function <firma> to anon, authenticated;
--   alter view <vista> reset (security_invoker);
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Helpers internos de stock: solo el dueño (y service_role)
-- ----------------------------------------------------------------------------
revoke execute on function plantas_aplicar_movimiento_stock(uuid, text, numeric, text, text, uuid, uuid, uuid, text)
  from public, anon, authenticated;

revoke execute on function plantas_descontar_stock_despacho(uuid, numeric, numeric)
  from public, anon, authenticated;

revoke execute on function plantas_recalcular_stock_vale(uuid, uuid, numeric, text, text, text)
  from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2) Vistas con RLS del usuario que consulta
-- ----------------------------------------------------------------------------
alter view plantas_v_stock_movimientos_viva set (security_invoker = true);
alter view plantas_v_despachos_camion set (security_invoker = true);
