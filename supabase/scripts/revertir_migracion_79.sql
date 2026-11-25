-- ============================================================================
-- Vuelta atrás de la migración 79 (ingreso contra pedido de Flota).
-- Borra el trigger y las funciones nuevas, la columna cantidad_sumada y el
-- UNIQUE de flota_pedido_item_ingresos_planta (la tabla vuelve a como la dejó
-- Flota). NO toca lo ya registrado: vales, ingresos y stock son de Báscula, y
-- los vínculos y lo sumado en flota_pedido_items quedan como dato de Flota
-- (deshacerlo sería otro script, con lista y OK de Federico y de Flota).
-- La entidad de auditoría se borra solo si no tiene filas.
-- ============================================================================
begin;
set local lock_timeout = '5s';
drop trigger if exists plantas_ingresos_anulado_flota on public.plantas_ingresos;
drop function if exists public.plantas_trg_ingreso_anulado_flota();
drop function if exists public.registrar_ingreso_pedido_flota(uuid, numeric, numeric, text, text, text, numeric, text, text, text, timestamptz);
drop function if exists public.pesadas_sin_pedido_flota(uuid, integer);
drop function if exists public.desvincular_pesada_pedido_flota(uuid, text);
drop function if exists public.plantas_restar_pesada_de_item(uuid, text, boolean);
drop function if exists public.vincular_pesada_pedido_flota(uuid, uuid);
drop function if exists public.plantas_pedidos_flota_pendientes();
drop function if exists public.plantas_puede_vincular_flota();
alter table public.flota_pedido_item_ingresos_planta
  drop constraint if exists flota_pedido_item_ingresos_planta_ingreso_unico,
  drop column if exists cantidad_sumada;
delete from public.plantas_auditoria_entidades e
 where e.modulo = 'bascula' and e.entidad = 'vinculo_flota'
   and not exists (select 1 from public.plantas_auditoria a where a.modulo = 'bascula' and a.entidad = 'vinculo_flota');
commit;
