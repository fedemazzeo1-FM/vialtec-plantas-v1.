// Service de "Remito Manual/Blanco" (migración 36 + 37, 2026-09-09, pedido de
// Federico) — remitos oficiales sin pedido asociado (envío de materiales a
// obra u otro movimiento interno), con numeración automática que CONTINÚA
// la misma secuencia que los remitos de asfalto (plantas_remitos_numero_seq
// / plantas_pedidos.nro_remito_global), y con N items (cantidad/descripción)
// por remito en vez de una única descripción. Único punto de acceso a
// plantas_remitos_manuales/plantas_remitos_manuales_items — no hay policy de
// insert/update/delete directa para `authenticated`, toda escritura pasa por
// la RPC generar_remito_manual (memory/conventions.md: un service por
// dominio, nada de Supabase directo desde los componentes).

import { supabase } from '@/config/supabase'
import { fetchPaginado } from '@/services/fetch-paginado'

/**
 * @param {{ items: Array<{ cantidad?: number, descripcion: string }>, destino?: string,
 *   patente?: string, transportista?: string, fecha?: string|Date }} datos
 * @returns {Promise<{ remito: object, items: Array<{ cantidad: number|null, descripcion: string }> }>}
 */
export async function generarRemitoManual(datos) {
  const fecha = datos.fecha ? new Date(datos.fecha).toISOString().slice(0, 10) : undefined
  const { data, error } = await supabase.rpc('generar_remito_manual', {
    p_items: datos.items.map((i) => ({ cantidad: i.cantidad ?? null, descripcion: i.descripcion })),
    p_destino: datos.destino || null,
    p_patente: datos.patente || null,
    p_transportista: datos.transportista || null,
    p_fecha: fecha,
  })
  if (error) throw error
  return data
}

/**
 * Listado completo (orden más reciente primero) — paginado con el helper
 * común (memory/architecture.md: tabla que acumula historial sin límite,
 * nunca asumir que hoy es chica y va a seguir siéndolo).
 */
export async function fetchRemitosManuales() {
  return fetchPaginado(() =>
    supabase.from('plantas_remitos_manuales').select('*').order('numero_remito', { ascending: false })
  )
}

/** Items de un remito manual puntual (para reimprimir uno ya generado). */
export async function fetchItemsDeRemitoManual(remitoId) {
  const { data, error } = await supabase
    .from('plantas_remitos_manuales_items')
    .select('*')
    .eq('remito_id', remitoId)
    .order('orden', { ascending: true })
  if (error) throw error
  return data ?? []
}
