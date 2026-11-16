-- ============================================================================
-- Vuelta atrás de la migración 75 (avisos por mail de Plantas). Deja el cron
-- informe-produccion-vialtec como estaba (desde plantas_avisos_respaldo) y
-- saca triggers, funciones, tablas, eventos y reglas de Plantas.
-- Los mails ya enviados quedan en core_notificaciones (son de la bandeja de
-- Flota): si hay alguno de un evento de Plantas, el evento no se borra (FK),
-- se desactiva.
-- ============================================================================
begin;
set local lock_timeout = '5s';

drop trigger plantas_avisos_stock on public.plantas_stock;
drop trigger plantas_avisos_stock on public.plantas_pedidos;
drop trigger plantas_avisos_stock on public.plantas_materiales;
drop trigger plantas_avisos_stock on public.plantas_formulas;
drop function public.plantas_trg_avisos_stock();
drop function public.plantas_avisos_stock_revisar();
drop function public.plantas_numero_ar(numeric, int);
drop table public.plantas_avisos_stock_estado;
drop function public.plantas_stock_estados(date);
drop function public.plantas_semaforo_stock(numeric, numeric, numeric);

delete from public.core_notificacion_reglas where evento in ('informe_plantas_mensual', 'plantas_stock_critico');
update public.core_notificacion_eventos set activo = false
 where clave in ('informe_plantas_mensual', 'plantas_stock_critico')
   and exists (select 1 from public.core_notificaciones n where n.evento = core_notificacion_eventos.clave);
delete from public.core_notificacion_eventos e
 where e.clave in ('informe_plantas_mensual', 'plantas_stock_critico')
   and not exists (select 1 from public.core_notificaciones n where n.evento = e.clave);

select cron.alter_job(
  (select jobid from cron.job where jobname = 'informe-produccion-vialtec'),
  schedule := split_part(r.definicion, E'\n', 1),
  command := substr(r.definicion, strpos(r.definicion, E'\n') + 1))
  from public.plantas_avisos_respaldo r where r.objeto = 'cron:informe-produccion-vialtec';
drop table public.plantas_avisos_respaldo;
commit;
