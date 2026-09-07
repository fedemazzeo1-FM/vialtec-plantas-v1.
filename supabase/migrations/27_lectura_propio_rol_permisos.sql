-- 27_lectura_propio_rol_permisos.sql
-- Fix inmediato post-migración 26: la policy "plantas_permisos: admin todo"
-- (FOR ALL) es la única que existe sobre plantas_permisos — un usuario no
-- admin no puede ni siquiera hacer SELECT de su PROPIA fila, así que
-- auth.store.js#_cargarPerfil (que necesita leer qué módulos puede "ver" su
-- rol, para armar el menú) le traía 0 filas y el usuario se quedaba sin ver
-- ninguna pestaña salvo Home. Encontrado en revisión antes de que Federico
-- validara en el navegador, no en producción.
--
-- Agrega una segunda policy de SOLO LECTURA (Postgres combina políticas
-- permisivas del mismo comando con OR) que deja a cada usuario leer las
-- filas de SU PROPIO rol — nada sensible (es la config de qué puede hacer
-- su propio rol, no la de otros) y no toca escritura, que sigue admin-only
-- por la policy "admin todo" ya existente.

begin;

drop policy if exists "plantas_permisos: propio rol lee" on plantas_permisos;
create policy "plantas_permisos: propio rol lee" on plantas_permisos
  for select using (rol_id = plantas_rol_actual());

commit;
