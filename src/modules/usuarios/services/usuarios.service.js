// Service del módulo "Usuarios y Permisos por rol" (pedido de Federico,
// 2026-09-03: "Incluir la pestaña/tab 'Usuarios' dentro del Módulo de
// Permisos por Rol para unificar ahí toda la administración de cuentas y
// asignación de roles. Restringir el acceso a este módulo y sus
// configuraciones exclusivamente a usuarios con rol Admin.").
//
// Único punto de acceso a Supabase para plantas_usuarios_roles desde el
// módulo Usuarios (memory/conventions.md) — ningún componente .vue llama a
// Supabase directamente.
//
// IMPORTANTE — depende de la migración 21 (BORRADOR, todavía NO aplicada,
// ver supabase/migrations/21_admin_gestion_usuarios_roles.sql): hoy la RLS
// de plantas_usuarios_roles (migración 07) solo permite a cada usuario leer
// SU PROPIA fila, y no hay ninguna vía de escritura desde el cliente. Hasta
// que Federico confirme y se aplique la migración 21:
//   - fetchUsuarios() va a devolver como mucho la fila del usuario logueado
//     (no error, pero lista incompleta para un admin).
//   - guardarUsuario() va a fallar con "function admin_upsert_usuario_rol
//     does not exist" (la RPC todavía no existe en la base).
// La pantalla (AdministracionView.vue) ya queda armada y lista para
// funcionar apenas se aplique — no hace falta tocar este service de nuevo.

import { supabase } from '@/config/supabase'

/**
 * Roles asignables a un usuario — DINÁMICO desde 2026-09-06 (migración 26):
 * antes era un array hardcodeado de los 7 roles fijos; ahora sale de
 * `plantas_roles` (activos), así que un rol nuevo creado en la tab "Roles"
 * de Administración aparece acá automáticamente, sin tocar código.
 * @returns {Promise<{id: string, nombre: string}[]>}
 */
export async function fetchRolesAsignables() {
  const { data, error } = await supabase.from('plantas_roles').select('id, nombre').eq('activo', true).order('nombre')
  if (error) throw error
  return data
}

export async function fetchUsuarios() {
  const { data, error } = await supabase
    .from('plantas_usuarios_roles')
    .select('id, email, rol, ver_todas_obras, ver_ventas, obra_ids, activo')
    .order('email', { ascending: true })
  if (error) throw error
  return data
}

/**
 * Alta/edición de usuario+rol — pasa por la RPC `admin_upsert_usuario_rol`
 * (migración 21), no por `.upsert()` directo: el chequeo de "solo admin"
 * tiene que validarse server-side, no solo ocultando el botón en la UI
 * (mismo patrón que el resto de las escrituras de negocio, memory/
 * business-rules.md).
 * @param {{ email: string, rol: string, verTodasObras: boolean, verVentas: boolean, obraIds: number[], activo: boolean }} datos
 */
export async function guardarUsuario(datos) {
  const { data, error } = await supabase.rpc('admin_upsert_usuario_rol', {
    p_email: datos.email,
    p_rol: datos.rol,
    p_ver_todas_obras: datos.verTodasObras,
    p_ver_ventas: datos.verVentas,
    p_obra_ids: datos.obraIds ?? [],
    p_activo: datos.activo,
  })
  if (error) throw error
  return data
}
