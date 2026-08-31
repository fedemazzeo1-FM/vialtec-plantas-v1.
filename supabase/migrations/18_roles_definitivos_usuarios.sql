-- ============================================================================
-- Migración 18: Fase 2 — roles definitivos según el mapeo real (capturas de
-- "Usuarios del sistema" del legado, sesión 2026-08-31)
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Alcance de esta migración: SOLO los 12 emails de las capturas que
-- matchean 1:1 contra los 19 reales de flota_usuarios_email (migración 17).
-- Quedan afuera a propósito (ver resumen en el mensaje de la sesión, no
-- repetido acá):
--   - 7 de los 19 no aparecían en las capturas (alejandro.fernandez,
--     dario.bermudez, diego.vitale, elias.scholles, sebastian.pastorino,
--     sofia.mazzeo, trinidadluis100) — quedan como estaban (encargado,
--     ver_todas_obras=true) hasta el resto del mapeo.
--   - 3 personas de las capturas (Juan Martin Heinrich, Diego Sanchez vía
--     balanza@vialtec.com.ar, Angel Moreira) NO tienen fila en
--     flota_usuarios_email — no se crea nada para ellos acá, ver detalle.
--
-- Restricción real por obra (ver_todas_obras=false + obra_ids) SOLO para
-- Fabian Moreyra: es la única persona cuya lista completa de obras resolvió
-- 1:1 contra flota_obras sin ambigüedad. El resto de las personas con
-- "Predio Vialtec" / "BARRIO ALTOS DEL BARRANCO" / "Municipalidad
-- exaltacion de la cruz" en su lista quedan en ver_todas_obras=true —
-- esos 3 nombres de obra no resuelven limpio contra flota_obras (ver
-- detalle en el mensaje de la sesión), y restringir con una lista
-- incompleta sería peor que no restringir (le sacaría obras reales a
-- alguien por error).
-- ============================================================================

update plantas_usuarios_roles set
  rol = 'plantista', ver_todas_obras = true, ver_ventas = true, obra_ids = '{}'
where email = 'daniel.natel@vialtec.com.ar'; -- Daniel Natel, "Plantista (Jefe)"

update plantas_usuarios_roles set
  rol = 'plantista', ver_todas_obras = true, ver_ventas = true, obra_ids = '{}'
where email = 'felix.pereyra@vialtec.com.ar'; -- Felix Pereyra, "Plantista (Jefe)"

update plantas_usuarios_roles set
  rol = 'gerencia', ver_todas_obras = true, ver_ventas = true, obra_ids = '{}'
where email = 'fernando.mazzeo@vialtec.com.ar'; -- Fernando Mazzeo, "Gerencia"

update plantas_usuarios_roles set
  rol = 'gerencia', ver_todas_obras = true, ver_ventas = true, obra_ids = '{}'
where email = 'mariano.clifford@vialtec.com.ar'; -- Mariano Clifford, "Gerencia"

update plantas_usuarios_roles set
  rol = 'supervisor', ver_todas_obras = true, ver_ventas = false, obra_ids = '{}'
where email = 'ronaldbarberiro85@gmail.com'; -- Ronald Barberito, "Supervisor" — obras con 1 nombre sin resolver (BARRIO ALTOS DEL BARRANCO), ver_todas_obras se deja true

update plantas_usuarios_roles set
  rol = 'supervisor', ver_todas_obras = true, ver_ventas = false, obra_ids = '{}'
where email = 'jonatancena882@gmail.com'; -- Jonatan Cena, "Supervisor" — "Predio Vialtec" sin resolver

update plantas_usuarios_roles set
  rol = 'encargado', ver_todas_obras = true, ver_ventas = true, obra_ids = '{}'
where email = 'casaspen1@hotmail.com'; -- Gustavo Spen, "Encargado de obra" — "Predio Vialtec" sin resolver

update plantas_usuarios_roles set
  rol = 'encargado', ver_todas_obras = true, ver_ventas = true, obra_ids = '{}'
where email = 'damian.esteban@vialtec.com.ar'; -- Damian Esteban, "Encargado de obra" — "Predio Vialtec" + "Municipalidad exaltacion de la cruz" sin resolver

update plantas_usuarios_roles set
  rol = 'encargado', ver_todas_obras = true, ver_ventas = true, obra_ids = '{}'
where email = 'german.perez@vialtec.com.ar'; -- German Perez, "Encargado de obra" — "Predio Vialtec" sin resolver

update plantas_usuarios_roles set
  rol = 'encargado', ver_todas_obras = true, ver_ventas = true, obra_ids = '{}'
where email = 'leonel.canosa@vialtec.com.ar'; -- Leonel Canosa, "Encargado de obra" — "Predio Vialtec" + "BARRIO ALTOS DEL BARRANCO" sin resolver

-- Único caso con restricción real por obra: las 3 obras de su lista
-- resuelven limpio contra flota_obras (10=La Barranca-Campana,
-- 18=Makro, 28=Moorlands-Tortuguitas).
update plantas_usuarios_roles set
  rol = 'encargado', ver_todas_obras = false, ver_ventas = true, obra_ids = '{28,18,10}'
where email = 'fabian.moreyra@vialtec.com.ar'; -- Fabian Moreyra, "Encargado de obra"

-- federico.mazzeo@vialtec.com.ar ya es 'admin' desde la migración 07/17, sin cambios.
