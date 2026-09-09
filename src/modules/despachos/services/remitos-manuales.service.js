// Service de "Remito Manual/Blanco" (migración 36, 2026-09-09, pedido de
// Federico) — remitos oficiales sin pedido asociado (envío de materiales a
// obra u otro movimiento interno), con numeración automática que CONTINÚA
// la misma secuencia que los remitos de asfalto (plantas_remitos_numero_seq
// / plantas_pedidos.nro_remito_global). Único punto de acceso a
// plantas_remitos_manuales — no hay policy de insert/update/delete directa
// para `authenticated`, toda escritura pasa por la RPC generar_remito_manual
// (memory/conventions.md: un service por dominio, nada de Supabase directo
// desde los componentes).

import { supabase } from '@/config/supabase'
import { fetchPaginado } from '@/services/fetch-paginado'

/**
 * @param {{ descripcion: string, destino?: string, patente?: string, transportista?: string, fecha?: string|Date }} datos
 */
export async function generarRemitoManual(datos) {
  const fecha = datos.fecha ? new Date(datos.fecha).toISOString().slice(0, 10) : undefined
  const { data, error } = await supabase.rpc('generar_remito_manual', {
    p_descripcion: datos.descripcion,
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
