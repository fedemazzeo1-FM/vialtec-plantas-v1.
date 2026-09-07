// Service del módulo Administración — tab "Roles" (2026-09-06, migración 26,
// pedido de Federico: "hacé lo que haya que hacer para que funcione").
// Único punto de acceso a Supabase para plantas_roles/plantas_permisos
// (memory/conventions.md). Escritura directa a tabla (no RPC): ambas tablas
// tienen RLS "admin todo" (migración 26) — mismo patrón que los catálogos de
// Maestros, que también escriben directo a tabla protegidos por RLS en vez
// de por una RPC dedicada. El único usuario que puede llegar a esta pantalla
// (nav.js + router guard, tab 'usuarios' = admin-only) es admin, así que la
// RLS ya es la barrera real.

import { supabase } from '@/config/supabase'

// Módulos y acciones de la matriz — deben coincidir con los CHECK de
// plantas_permisos (migración 26). 'administracion' queda afuera a
// propósito: ver ADMINISTRACION_SIEMPRE_ADMIN abajo.
export const MODULOS_MATRIZ = [
  { key: 'pedidos', label: 'Pedidos' },
  { key: 'bascula', label: 'Báscula' },
  { key: 'stock', label: 'Stock' },
  { key: 'despachos', label: 'Despachos' },
  { key: 'formulas', label: 'Fórmulas' },
  { key: 'maestros', label: 'Maestros' },
  { key: 'plan_semanal', label: 'Plan semanal' },
  { key: 'simulador', label: 'Simulador' },
]
export const ACCIONES_MATRIZ = [
  { key: 'ver', label: 'Ver' },
  { key: 'crear', label: 'Crear' },
  { key: 'editar', label: 'Editar' },
  { key: 'eliminar', label: 'Eliminar' },
  { key: 'aprobar', label: 'Aprobar' },
  { key: 'exportar', label: 'Exportar' },
]

export async function fetchRoles() {
  const [{ data: roles, error: errorRoles }, { data: usuarios, error: errorUsuarios }] = await Promise.all([
    // orden por creado_en + id: los 7 roles del sistema comparten el mismo
    // creado_en (sembrados juntos en la migración 26) — sin el desempate por
    // id el orden entre ellos no es determinístico (Postgres no garantiza
    // orden estable entre filas empatadas), y la lista "bailaba" en cada
    // refresh — visto en vivo al probar esta pantalla.
    supabase.from('plantas_roles').select('id, nombre, descripcion, es_sistema, activo').order('creado_en', { ascending: true }).order('id', { ascending: true }),
    supabase.from('plantas_usuarios_roles').select('rol'),
  ])
  if (errorRoles) throw errorRoles
  if (errorUsuarios) throw errorUsuarios

  const cantidadPorRol = {}
  for (const u of usuarios ?? []) cantidadPorRol[u.rol] = (cantidadPorRol[u.rol] ?? 0) + 1

  return (roles ?? []).map((r) => ({ ...r, cantidadUsuarios: cantidadPorRol[r.id] ?? 0 }))
}

/** Permisos de un rol como matriz completa { [modulo]: { [accion]: boolean } } — combos sin fila en la tabla quedan en false. */
export async function fetchPermisosRol(rolId) {
  const { data, error } = await supabase.from('plantas_permisos').select('modulo, accion, habilitado').eq('rol_id', rolId)
  if (error) throw error

  const matriz = {}
  for (const m of MODULOS_MATRIZ) {
    matriz[m.key] = {}
    for (const a of ACCIONES_MATRIZ) matriz[m.key][a.key] = false
  }
  for (const fila of data ?? []) {
    if (matriz[fila.modulo]) matriz[fila.modulo][fila.accion] = fila.habilitado
  }
  return matriz
}

/** admin -> slug ascii simple ('Administrativo Taller' -> 'administrativo_taller'). Colisión se resuelve sumando un sufijo numérico. */
function slugify(nombre) {
  return nombre
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
}

export async function generarIdRolUnico(nombre) {
  const base = slugify(nombre) || 'rol'
  const { data, error } = await supabase.from('plantas_roles').select('id').like('id', `${base}%`)
  if (error) throw error
  const existentes = new Set((data ?? []).map((r) => r.id))
  if (!existentes.has(base)) return base
  let i = 2
  while (existentes.has(`${base}_${i}`)) i++
  return `${base}_${i}`
}

/**
 * Alta/edición de un rol + su matriz completa. `esNuevo` decide si primero
 * hay que insertar la fila en plantas_roles (con el id ya generado por
 * generarIdRolUnico) antes de guardar los permisos.
 * @param {{ id: string, nombre: string, descripcion: string, esNuevo: boolean, permisos: Record<string, Record<string, boolean>> }} datos
 */
export async function guardarRol({ id, nombre, descripcion, esNuevo, permisos }) {
  if (esNuevo) {
    const { error } = await supabase.from('plantas_roles').insert({ id, nombre, descripcion, es_sistema: false, activo: true })
    if (error) throw error
  } else {
    const { error } = await supabase.from('plantas_roles').update({ nombre, descripcion }).eq('id', id)
    if (error) throw error
  }

  const filas = []
  for (const m of MODULOS_MATRIZ) {
    for (const a of ACCIONES_MATRIZ) {
      filas.push({ rol_id: id, modulo: m.key, accion: a.key, habilitado: !!permisos[m.key]?.[a.key] })
    }
  }
  const { error: errorPermisos } = await supabase
    .from('plantas_permisos')
    .upsert(filas, { onConflict: 'rol_id,modulo,accion' })
  if (errorPermisos) throw errorPermisos
}

export async function toggleActivoRol(rol) {
  const { error } = await supabase.from('plantas_roles').update({ activo: !rol.activo }).eq('id', rol.id)
  if (error) throw error
}
