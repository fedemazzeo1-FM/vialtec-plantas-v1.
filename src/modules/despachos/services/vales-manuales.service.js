// Vales manuales (migración 77, 17/11/2026, pedido de Federico): SIMULACIONES con el formato del vale
// de balanza, para retiros que no pasaron por la báscula. Tabla propia (plantas_vales_manuales): no suman
// a producción ni a despachos, no tocan stock y no tienen pedido. Solo lectura directa; toda escritura va
// por las RPC (generar_vale_manual, generar_remito_vale_manual, anular_vale_manual), que validan el
// permiso despachos/aprobar y dejan la auditoría.

import { supabase } from '@/config/supabase'
import { fetchPaginado } from '@/services/fetch-paginado'

/** "M-00001" — gemela SQL: plantas_etiqueta_vale_manual(). */
export function formatearNumeroValeManual(numero) {
  if (numero == null) return '—'
  return `M-${String(numero).padStart(5, '0')}`
}

/** Listado completo, más reciente primero (con el nombre de la obra, aunque ya no esté activa). */
export async function fetchValesManuales() {
  return fetchPaginado(() =>
    supabase
      .from('plantas_vales_manuales')
      .select('*, obra:flota_obras(nombre)')
      .order('numero', { ascending: false })
  )
}

/**
 * @param {{ fechaPesada: string|Date, formulaId: string, pesoBruto: number, tara: number, obraId?: number|null,
 *   clienteExterno?: string|null, patente?: string, chofer?: string, temperatura?: number|null, observaciones?: string }} d
 */
export async function generarValeManual(d) {
  const { data, error } = await supabase.rpc('generar_vale_manual', {
    p_fecha_pesada: new Date(d.fechaPesada).toISOString(),
    p_formula_id: d.formulaId,
    p_peso_bruto: Number(d.pesoBruto),
    p_tara: Number(d.tara),
    p_obra_id: d.obraId ?? null,
    p_cliente_externo: d.clienteExterno || null,
    p_patente: d.patente || null,
    p_chofer: d.chofer || null,
    p_temperatura: d.temperatura === '' || d.temperatura == null ? null : Number(d.temperatura),
    p_observaciones: d.observaciones || null,
  })
  if (error) throw error
  return data
}

/** Asigna el N° de remito la primera vez; después devuelve siempre el mismo. */
export async function generarRemitoValeManual(valeId) {
  const { data, error } = await supabase.rpc('generar_remito_vale_manual', { p_vale_id: valeId })
  if (error) throw error
  return data
}

export async function anularValeManual(valeId, motivo) {
  const { data, error } = await supabase.rpc('anular_vale_manual', { p_vale_id: valeId, p_motivo: motivo })
  if (error) throw error
  return data
}
