// Service de Fórmulas — único punto de acceso a Supabase para plantas_formulas.
// Ningún componente .vue debe importar `supabase` directamente: pasa por acá.
//
// Nota sobre paginación (memory/architecture.md): plantas_formulas es un catálogo
// acotado (fórmulas activas + históricas de la planta, no un historial que crezca
// sin límite como pedidos o vales), por eso NO aplica fetchPaginado()/.range() acá.

import { supabase } from '@/config/supabase'

const TABLA = 'plantas_formulas'

/**
 * @param {{ soloActivas?: boolean }} opciones
 */
export async function fetchFormulas({ soloActivas = false } = {}) {
  let query = supabase.from(TABLA).select('*').order('nombre', { ascending: true })
  if (soloActivas) query = query.eq('activo', true)

  const { data, error } = await query
  if (error) throw error
  return data
}

export async function getFormula(id) {
  const { data, error } = await supabase.from(TABLA).select('*').eq('id', id).single()
  if (error) throw error
  return data
}

/**
 * @param {{ nombre: string, tipo: 'asfalto'|'hormigon', unidad: 'tn'|'m3', activo: boolean, insumos: Array }} formula
 */
export async function crearFormula(formula) {
  const { data, error } = await supabase.from(TABLA).insert(formula).select().single()
  if (error) throw error
  return data
}

/**
 * Update parcial. Para insumos, se espera el array completo (se reemplaza
 * entero el JSONB, no hay merge parcial de insumos a nivel DB).
 */
export async function actualizarFormula(id, cambios) {
  const { data, error } = await supabase.from(TABLA).update(cambios).eq('id', id).select().single()
  if (error) throw error
  return data
}

export async function setFormulaActiva(id, activo) {
  return actualizarFormula(id, { activo })
}

/**
 * Conversión de un insumo a kg consumidos, según memory/business-rules.md:
 *   % -> (cantidad / 100) * 1000 * cantidadProducida
 *   tn -> cantidad * 1000 * cantidadProducida
 *   kg | L -> cantidad * cantidadProducida
 */
export function calcularConsumoKg(insumo, cantidadProducida) {
  const cantidad = Number(insumo.cantidad) || 0

  switch (insumo.unidad) {
    case '%':
      return (cantidad / 100) * 1000 * cantidadProducida
    case 'tn':
      return cantidad * 1000 * cantidadProducida
    case 'kg':
    case 'L':
      return cantidad * cantidadProducida
    default:
      throw new Error(`calcularConsumoKg: unidad de insumo desconocida "${insumo.unidad}"`)
  }
}

/** Consumo en kg de todos los insumos de una fórmula, para una cantidad producida dada. */
export function calcularConsumoTotalKg(formula, cantidadProducida) {
  return (formula.insumos || []).map((insumo) => ({
    material: insumo.material,
    kg: calcularConsumoKg(insumo, cantidadProducida),
  }))
}
