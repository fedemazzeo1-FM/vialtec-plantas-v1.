-- ============================================================================
-- Migración 40: CRUD completo de Camiones (plantas_patentes) para balancero
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Pedido explícito de Federico (2026-09-16): balancero necesita permisos
-- completos (crear/editar/eliminar, además del "ver" que ya tenía) sobre la
-- entidad Camiones (plantas_patentes) en Maestros — es quien más rota este
-- catálogo en el día a día (altas/bajas de camiones externos).
--
-- Por qué NO se resuelve subiendo el flag en la matriz plantas_permisos
-- (modulo='maestros'): esa matriz es por MÓDULO completo, no por entidad —
-- plantas_patentes, plantas_materiales, plantas_proveedores y
-- plantas_clientes comparten las mismas 3 policies RLS
-- "plantas_tiene_permiso('maestros', accion)". Habilitar
-- maestros.crear/editar/eliminar=true para balancero en esa matriz le
-- daría TAMBIÉN CRUD sobre Materiales/Proveedores/Clientes, que no fue lo
-- pedido. En cambio, se agregan 3 policies ADICIONALES (permissive, se
-- OR-ean con las existentes) específicas de plantas_patentes para el rol
-- balancero — no tocan la matriz ni ninguna otra tabla/rol.
--
-- Eliminación física (hard delete): NO requiere cambio acá — ya existe
-- desde 2026-09-09 (`patentesService.eliminar()` en maestros.service.js hace
-- un DELETE real sobre plantas_patentes, sin soft-delete; plantas_vales/
-- plantas_cargas_asfalto/plantas_cargas_hormigon guardan la patente como
-- texto libre, no FK, así que borrar un camión del catálogo no rompe
-- ningún historial). Esta migración solo habilita que balancero PUEDA
-- ejecutar ese DELETE (y el insert/update) vía RLS.
-- ============================================================================

create policy "plantas_patentes: crear (balancero)" on plantas_patentes
  for insert to authenticated
  with check (plantas_rol_actual() = 'balancero');

create policy "plantas_patentes: editar (balancero)" on plantas_patentes
  for update to authenticated
  using (plantas_rol_actual() = 'balancero')
  with check (plantas_rol_actual() = 'balancero');

create policy "plantas_patentes: borrar (balancero)" on plantas_patentes
  for delete to authenticated
  using (plantas_rol_actual() = 'balancero');
