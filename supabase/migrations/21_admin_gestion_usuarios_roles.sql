-- ============================================================================
-- Migración 21 (BORRADOR — NO APLICADA): Módulo "Usuarios y Permisos por rol"
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Origen: pedido explícito de Federico (2026-09-03) — "Incluir la pestaña/tab
-- 'Usuarios' dentro del Módulo de Permisos por Rol para unificar ahí toda la
-- administración de cuentas y asignación de roles. Restringir el acceso a
-- este módulo y sus configuraciones exclusivamente a usuarios con rol Admin."
--
-- Esta migración NO se corrió todavía (memory/procedimientos.md: cualquier
-- cambio de schema/RLS necesita aviso previo y confirmación de Federico).
-- Queda acá como borrador listo para revisar y aplicar cuando confirme.
--
-- Qué cambia:
--   1) Nueva policy de SELECT en plantas_usuarios_roles: admin puede leer
--      TODAS las filas (hoy, migración 07, cada usuario solo puede leer la
--      suya — comentario explícito ahí: "Gestión (insert/update/delete)
--      queda sin policy todavía -> hasta que exista la pantalla ABM de
--      Roles" — esta migración es exactamente esa pantalla).
--   2) RPC `admin_upsert_usuario_rol(...)` SECURITY DEFINER: única vía de
--      escritura (alta/edición de rol, obras visibles, activo/inactivo).
--      Verifica plantas_rol_actual() = 'admin' server-side (mismo patrón que
--      migración 07/16 — la UI solo oculta el botón, el enforcement real es
--      acá). Valida el rol contra la lista de 7 roles conocidos
--      (memory/business-rules.md) para no permitir cargar un rol inexistente
--      que después no matchee ningún permiso en PERMISOS_POR_ROL.
--
-- Reversibilidad: 100% aditivo, no toca datos existentes ni las policies de
-- lectura propia ya vigentes. Si algo sale mal:
--   drop function if exists admin_upsert_usuario_rol(text, text, boolean, boolean, integer[], boolean);
--   drop policy if exists "admin lee todos los usuarios" on plantas_usuarios_roles;
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Admin puede leer todas las filas (además de "cada uno lee la suya",
--    migración 07, que sigue vigente sin cambios).
-- ----------------------------------------------------------------------------
create policy "admin lee todos los usuarios"
  on plantas_usuarios_roles for select
  to authenticated
  using (plantas_rol_actual() = 'admin');

-- ----------------------------------------------------------------------------
-- 2) admin_upsert_usuario_rol — única vía de escritura sobre
--    plantas_usuarios_roles desde el cliente. Upsert por email: si no existe
--    la fila la crea (alta de usuario), si existe la actualiza.
-- ----------------------------------------------------------------------------
create or replace function admin_upsert_usuario_rol(
  p_email text,
  p_rol text,
  p_ver_todas_obras boolean default false,
  p_ver_ventas boolean default false,
  p_obra_ids integer[] default '{}',
  p_activo boolean default true
)
returns plantas_usuarios_roles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol_actual text;
  v_resultado plantas_usuarios_roles;
begin
  v_rol_actual := plantas_rol_actual();
  if v_rol_actual is distinct from 'admin' then
    raise exception 'Solo un usuario con rol admin puede administrar usuarios y roles.';
  end if;

  if p_rol not in ('admin', 'plantista', 'encargado', 'supervisor', 'balancero', 'gerencia', 'plantista_hormigon') then
    raise exception 'Rol "%" inválido. Roles válidos: admin, plantista, encargado, supervisor, balancero, gerencia, plantista_hormigon.', p_rol;
  end if;

  insert into plantas_usuarios_roles (email, rol, ver_todas_obras, ver_ventas, obra_ids, activo)
  values (lower(trim(p_email)), p_rol, p_ver_todas_obras, p_ver_ventas, coalesce(p_obra_ids, '{}'), p_activo)
  on conflict (email) do update set
    rol = excluded.rol,
    ver_todas_obras = excluded.ver_todas_obras,
    ver_ventas = excluded.ver_ventas,
    obra_ids = excluded.obra_ids,
    activo = excluded.activo
  returning * into v_resultado;

  return v_resultado;
end;
$$;

comment on function admin_upsert_usuario_rol(text, text, boolean, boolean, integer[], boolean) is
  'Alta/edición de usuario+rol de VialTec Plantas — exclusivo para rol admin (chequeo server-side). Único punto de escritura sobre plantas_usuarios_roles desde el cliente (memory/procedimientos.md).';

revoke execute on function admin_upsert_usuario_rol(text, text, boolean, boolean, integer[], boolean) from public;
grant execute on function admin_upsert_usuario_rol(text, text, boolean, boolean, integer[], boolean) to authenticated;

-- Verificado por consulta (2026-09-03): plantas_usuarios_roles ya tiene
-- `plantas_usuarios_roles_email_key UNIQUE (email)` -- el `on conflict
-- (email)` de arriba funciona sin pasos previos. También ya existe un CHECK
-- (`plantas_usuarios_roles_rol_check`) con la misma lista de 7 roles -- el
-- chequeo explícito dentro de la función es redundante con eso, pero se deja
-- para dar un mensaje de error más claro antes de llegar al constraint.
