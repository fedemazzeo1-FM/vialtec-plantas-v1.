-- ============================================================================
-- Vuelta atrás de la migración 77 (vales manuales). Borra la tabla con sus vales,
-- las funciones y la entidad de auditoría. Las filas de plantas_auditoria de
-- vales manuales se conservan (historial), así que la entidad solo se puede
-- borrar si no hay ninguna: si las hay, queda en el catálogo.
-- Los N° de remito que se hayan usado no se devuelven a la numeración.
-- ============================================================================
begin;
set local lock_timeout = '5s';
drop function if exists public.generar_vale_manual(timestamptz, uuid, numeric, numeric, bigint, text, text, text, numeric, text);
drop function if exists public.generar_remito_vale_manual(uuid);
drop function if exists public.anular_vale_manual(uuid, text);
drop function if exists public.plantas_auditoria_label_vale_manual(public.plantas_vales_manuales);
drop function if exists public.plantas_etiqueta_vale_manual(bigint);
drop table if exists public.plantas_vales_manuales;
delete from public.plantas_auditoria_entidades e
 where e.entidad = 'vale_manual'
   and not exists (select 1 from public.plantas_auditoria a where a.entidad = 'vale_manual');
commit;
