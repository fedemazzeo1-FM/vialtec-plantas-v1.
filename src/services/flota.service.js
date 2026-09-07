// Lecturas de solo lectura sobre tablas flota_* compartidas con el sistema de
// flota (memory/architecture.md). VialTec Plantas NO es dueño de este schema:
// acá solo se lee, nunca se escribe. Cualquier necesidad de escritura sobre
// flota_* requiere el protocolo de memory/procedimientos.md.

import { supabase } from '@/config/supabase'

/** Obras (catálogo compartido, ~20 filas — no necesita fetchPaginado). */
export async function fetchObras({ soloActivas = true } = {}) {
  let query = supabase
    .from('flota_obras')
    .select('id, nombre, codigo, activo')
    .order('nombre', { ascending: true })

  if (soloActivas) query = query.eq('activo', true)

  const { data, error } = await query
  if (error) throw error
  return data
}

/**
 * Mapa email -> nombre para mostrar, contra flota_usuarios_email (mismo
 * patrón que ya usa auth.store.js para el usuario logueado). Usado por
 * stock.service.js para resolver el "Responsable" del historial de
 * movimientos (plantas_stock_movimientos.responsable_email, migración 15) —
 * auth.users no se expone vía API, por eso el server guarda el email
 * (auth.email()) y acá se cruza contra flota_* en vez de contra auth.users.
 *
 * @param {string[]} emails
 * @returns {Promise<Record<string,string>>}
 */
export async function fetchNombresPorEmail(emails) {
  const unicos = [...new Set(emails.filter(Boolean))]
  if (!unicos.length) return {}

  const { data, error } = await supabase.from('flota_usuarios_email').select('email, nombre').in('email', unicos)
  if (error) throw error
  return Object.fromEntries((data ?? []).map((u) => [u.email, u.nombre]))
}

/**
 * Teléfono (formato wa.me listo, ej. "5491149977622") de un usuario del
 * sistema de flota, buscado por NOMBRE — no por email (2026-09-07, pedido de
 * Federico: mapear el teléfono que ya carga flota_usuarios_email para que el
 * WppToast de Pedidos apunte directo al chat personal del "encargado que
 * pidió", en vez de abrir wa.me sin destinatario).
 *
 * Match exacto (case/espacios-insensitive) contra `flota_usuarios_email.nombre`
 * — a propósito NO es un fuzzy match: `plantas_pedidos.encargado` es texto
 * libre tipeado en ESTE sistema (no arrastra la inconsistencia histórica del
 * legado que ya hizo descartar un merge automático para choferes, ver
 * memory/pending.md). Si no hay match exacto, devuelve null y el toast cae
 * al comportamiento de siempre (wa.me sin número, el usuario elige el
 * contacto a mano) — nunca se envía a un número adivinado.
 *
 * @param {string} nombre
 * @returns {Promise<string|null>}
 */
export async function fetchTelefonoPorNombre(nombre) {
  const nombreLimpio = (nombre || '').trim()
  if (!nombreLimpio) return null

  const { data, error } = await supabase
    .from('flota_usuarios_email')
    .select('telefono')
    .ilike('nombre', nombreLimpio)
    .not('telefono', 'is', null)
    .limit(1)
    .maybeSingle()
  if (error) throw error
  return data?.telefono || null
}
