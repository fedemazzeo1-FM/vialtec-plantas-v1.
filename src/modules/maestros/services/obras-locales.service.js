// Filtro de visibilidad LOCAL de Obras en Plantas (migración 32, 2026-09-08).
// NUNCA escribe en flota_obras (tabla compartida, propiedad de Flota — solo
// lectura, memory/architecture.md). Esto solo guarda, por obra_id, si Plantas
// la "archivó" para dejar de mostrarla en sus propios desplegables operativos
// (Pedidos, Báscula, Despachos, Plan Semanal, Dashboard, Usuarios) — no tiene
// ninguna relación con el estado real de la obra en Flota (activa/pausada/
// finalizada), que se sigue gestionando en equipos2.vialtec.app.
//
// Deliberadamente sin RPC: es un catálogo propio y liviano (mismo criterio
// que crudEntidad() de maestros.service.js), un upsert directo alcanza — la
// RLS de la migración 32 ya restringe la escritura a admin/plantista.

import { supabase } from '@/config/supabase'

const TABLA = 'plantas_obras_locales'

/** @returns {Promise<Record<number, { archivada: boolean, archivada_en: string|null, archivada_por: string|null }>>} */
export async function fetchEstadoLocalObras() {
  const { data, error } = await supabase.from(TABLA).select('obra_id, archivada, archivada_en, archivada_por')
  if (error) throw error
  return Object.fromEntries((data ?? []).map((fila) => [fila.obra_id, fila]))
}

/**
 * @param {number} obraId
 * @param {boolean} archivada
 * @param {string|null} emailUsuario auth.user?.email de quien archiva — solo a título informativo, no hay auditoría server-side para este catálogo liviano.
 */
export async function setObraArchivadaLocal(obraId, archivada, emailUsuario) {
  const { error } = await supabase.from(TABLA).upsert({
    obra_id: obraId,
    archivada,
    archivada_en: archivada ? new Date().toISOString() : null,
    archivada_por: archivada ? emailUsuario || null : null,
  })
  if (error) throw error
}
