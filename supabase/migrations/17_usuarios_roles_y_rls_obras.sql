-- ============================================================================
-- Migración 17: Fase 2 — carga de los 19 usuarios reales + RLS de Pedidos
-- filtrada por obra
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Origen: Fase 2 de Usuarios/Roles/Permisos (sesión 2026-08-31).
--
-- Los 19 emails de acá abajo son los reales de flota_usuarios_email
-- (consultados en vivo contra la tabla, no inventados) — Federico rechazó
-- explícitamente un primer borrador con emails de plantilla
-- (plantista.asfalto@, supervisor1@, etc.) que no correspondían a ninguna
-- cuenta real.
--
-- Rol asignado: federico.mazzeo@vialtec.com.ar se preserva como 'admin' (ya
-- tenía esa fila desde la migración 07). Los otros 18 quedan en 'encargado'
-- como default UNIFORME — no tengo el perfil/función real de cada persona
-- más allá del nombre, así que no invento un rol distinto por persona
-- (mismo criterio que ya rechazaste en el borrador anterior, esta vez
-- aplicado al rol en vez de al email). 'encargado' es el default más
-- conservador de los dos que pediste ('encargado'/'plantista' según
-- perfil): ve pedidos y despachos, no puede confirmar/despachar/tocar
-- stock. Ajustar el rol real de cada uno es un UPDATE puntual por email
-- cuando tengas el mapeo persona-por-persona, no hace falta otra migración.
--
-- ver_todas_obras=true para los 19 (pedido explícito: "evitar bloqueos
-- iniciales") — la política de RLS de abajo YA queda funcionando, pero con
-- ver_todas_obras=true en todos el filtro por obra_ids no restringe a nadie
-- todavía: es intencional, el mecanismo se activa persona por persona
-- cuando Federico decida pasar a alguien a ver_todas_obras=false +
-- obra_ids={...} reales.
-- ver_ventas=true para todos (rol admin + 18 encargado, ambos están en el
-- set "admin/gerencia/encargado" que pediste con ver_ventas=true).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Carga de los 19 usuarios reales.
-- ----------------------------------------------------------------------------
insert into plantas_usuarios_roles (email, rol, ver_todas_obras, ver_ventas, obra_ids, activo)
values
  ('federico.mazzeo@vialtec.com.ar',    'admin',     true, true, '{}', true), -- ya existía como admin, se preserva
  ('alejandro.fernandez@vialtec.com.ar','encargado', true, true, '{}', true),
  ('casaspen1@hotmail.com',             'encargado', true, true, '{}', true), -- Gustavo Spen
  ('damian.esteban@vialtec.com.ar',     'encargado', true, true, '{}', true),
  ('daniel.natel@vialtec.com.ar',       'encargado', true, true, '{}', true),
  ('dario.bermudez@vialtec.com.ar',     'encargado', true, true, '{}', true),
  ('diego.vitale@vialtec.com.ar',       'encargado', true, true, '{}', true),
  ('elias.scholles@vialtec.com.ar',     'encargado', true, true, '{}', true),
  ('fabian.moreyra@vialtec.com.ar',     'encargado', true, true, '{}', true),
  ('felix.pereyra@vialtec.com.ar',      'encargado', true, true, '{}', true),
  ('fernando.mazzeo@vialtec.com.ar',    'encargado', true, true, '{}', true),
  ('german.perez@vialtec.com.ar',       'encargado', true, true, '{}', true),
  ('jonatancena882@gmail.com',          'encargado', true, true, '{}', true), -- Jonatan Cena
  ('leonel.canosa@vialtec.com.ar',      'encargado', true, true, '{}', true),
  ('mariano.clifford@vialtec.com.ar',   'encargado', true, true, '{}', true),
  ('ronaldbarberiro85@gmail.com',       'encargado', true, true, '{}', true), -- Ronald Barberito
  ('sebastian.pastorino@vialtec.com.ar','encargado', true, true, '{}', true),
  ('sofia.mazzeo@vialtec.com.ar',       'encargado', true, true, '{}', true),
  ('trinidadluis100@gmail.com',         'encargado', true, true, '{}', true) -- Luis Trinidad
on conflict (email) do update set
  rol             = excluded.rol,
  ver_todas_obras = excluded.ver_todas_obras,
  ver_ventas      = excluded.ver_ventas,
  obra_ids        = excluded.obra_ids,
  activo          = excluded.activo;

-- ----------------------------------------------------------------------------
-- 2) RLS de plantas_pedidos: SELECT filtrado por obra (reemplaza el
--    "leer"/using(true) de la migración 16). Fórmula exacta pedida por
--    Federico: ver_todas_obras=true, o la obra del pedido está en
--    obra_ids del usuario, o es una venta externa y el usuario tiene
--    ver_ventas=true. Con ver_todas_obras=true en los 19 usuarios de arriba,
--    esto hoy no restringe a nadie — el mecanismo queda listo para cuando
--    se empiece a poner ver_todas_obras=false + obra_ids reales.
--
--    Alcance de esta migración: SOLO plantas_pedidos (lo que pidió
--    Federico). plantas_vales/plantas_cargas_*/plantas_pedidos_historial
--    siguen con su SELECT amplio de la migración 16 — extenderles el mismo
--    filtro por obra es un paso natural siguiente, no incluido acá a
--    propósito para no ampliar el alcance sin que se pida explícito.
-- ----------------------------------------------------------------------------

drop policy if exists "plantas_pedidos: leer" on plantas_pedidos;

create policy "plantas_pedidos: leer segun obra" on plantas_pedidos
  for select to authenticated
  using (
    exists (
      select 1
      from plantas_usuarios_roles pur
      where pur.email = auth.email()
        and pur.activo = true
        and (
          pur.ver_todas_obras = true
          or plantas_pedidos.obra_id = any(pur.obra_ids)
          or (plantas_pedidos.tipo_pedido = 'venta' and pur.ver_ventas = true)
        )
    )
  );
