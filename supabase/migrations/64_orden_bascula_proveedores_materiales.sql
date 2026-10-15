-- ============================================================================
-- Migración 64: orden destacado de proveedores y materiales en Báscula
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Pedido de Federico (2026-10-15): en la puerta de Ingreso de áridos, los
-- desplegables muestran primero los destacados y después el resto en orden
-- alfabético. El orden se configura desde Maestros (no en el código).
--
--   1. plantas_proveedores.orden_bascula y plantas_materiales.orden_bascula
--      (smallint, opcional, > 0). Vacío = va después, en orden alfabético.
--   2. Datos iniciales: CANTERA POMPEYA S.A = 1, CERRO DEL AGUILA = 2;
--      6/20 = 1, 0/6 = 2, 10/30 = 3. Quedan en la auditoría como EDITAR de
--      'sistema (SQL)' (trigger de la migración 61).
--
-- Reversión: alter table ... drop column orden_bascula (en las dos tablas).
-- No toca stock, vales, ingresos ni ninguna tabla flota_*.
-- ============================================================================

alter table public.plantas_proveedores
  add column orden_bascula smallint check (orden_bascula > 0);

alter table public.plantas_materiales
  add column orden_bascula smallint check (orden_bascula > 0);

comment on column public.plantas_proveedores.orden_bascula is
  'Posición en el desplegable de Ingreso de áridos (Báscula). Null = después, alfabético.';
comment on column public.plantas_materiales.orden_bascula is
  'Posición en el desplegable de Ingreso de áridos (Báscula). Null = después, alfabético.';

update public.plantas_proveedores set orden_bascula = 1 where nombre = 'CANTERA POMPEYA S.A';
update public.plantas_proveedores set orden_bascula = 2 where nombre = 'CERRO DEL AGUILA';

update public.plantas_materiales set orden_bascula = 1 where nombre = '6/20';
update public.plantas_materiales set orden_bascula = 2 where nombre = '0/6';
update public.plantas_materiales set orden_bascula = 3 where nombre = '10/30';
