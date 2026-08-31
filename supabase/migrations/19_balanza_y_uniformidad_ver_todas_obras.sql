-- ============================================================================
-- Migración 19: alta de Diego Sánchez (balanza@vialtec.com.ar, confirmado
-- por Federico como su email corporativo real, no un login compartido de
-- kiosko) + vuelta a ver_todas_obras=true uniforme para todos (se pospone
-- la restricción real por obra hasta resolver "Predio Vialtec" y las 2
-- obras sin match contra flota_obras — ver mensaje de la sesión anterior)
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
-- ============================================================================

-- balanza@vialtec.com.ar no está en flota_usuarios_email (esa tabla solo
-- resuelve el "nombre" para mostrar, best-effort — auth.store.js cae al
-- email crudo si no hay match, no bloquea login). El rol se resuelve
-- 100% desde plantas_usuarios_roles por email, así que esto alcanza para
-- que Diego Sánchez opere.
insert into plantas_usuarios_roles (email, rol, ver_todas_obras, ver_ventas, obra_ids, activo)
values ('balanza@vialtec.com.ar', 'balancero', true, false, '{}', true)
on conflict (email) do update set
  rol             = excluded.rol,
  ver_todas_obras = excluded.ver_todas_obras,
  ver_ventas      = excluded.ver_ventas,
  obra_ids        = excluded.obra_ids,
  activo          = excluded.activo;

-- Vuelta a ver_todas_obras=true uniforme: la migración 18 había dejado a
-- Fabian Moreyra como único caso restringido (era el único con las 3 obras
-- resueltas sin ambigüedad) — Federico pidió por ahora que TODOS queden
-- con ver_todas_obras=true, sin restricción individual por SQL, hasta que
-- se termine de resolver el mapeo completo (Predio Vialtec, BARRIO ALTOS
-- DEL BARRANCO, Municipalidad exaltación de la cruz, y los 7 usuarios que
-- faltan de las capturas). Se revierte para no dejar a una sola persona en
-- un estado distinto del resto.
update plantas_usuarios_roles
  set ver_todas_obras = true, obra_ids = '{}'
where email = 'fabian.moreyra@vialtec.com.ar';
