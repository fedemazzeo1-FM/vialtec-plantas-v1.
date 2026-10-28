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
 * @param {{ nombre: string, tipo: string, unidad: 'tn'|'m3', activo: boolean, insumos: Array }} formula
 *   `tipo` y `unidad` según src/config/tipos-producto.js.
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

// Validación de dosaje (2026-10-28, migración 70). Gemela de
// plantas_trg_validar_dosaje_formula: si se cambia un límite o la lista de
// ligantes, cambiar los dos. Origen: CAC D19 (AM3) cargada con 47 % de asfalto
// en vez de 4,7 % descontó 10 veces el asfalto de cada despacho.
export const LIGANTES = ['ASFALTO CA30', 'ASFALTO AM3', 'AM3 AUTOVIA']
export const MAX_PORCENTAJE_LIGANTE = 10
export const MAX_SUMA_PORCENTAJES = 110

const formatoPct = (n) => n.toLocaleString('es-AR', { maximumFractionDigits: 2 })

/**
 * Devuelve el mensaje de error del primer dosaje imposible, o null si está bien.
 * Solo mira insumos en %.
 *
 * @param {Array<{ material: string, cantidad: number|string, unidad: string }>} insumos
 * @returns {string|null}
 */
export function validarDosajeFormula(insumos) {
  let suma = 0
  for (const insumo of insumos || []) {
    if (insumo.unidad !== '%') continue
    const material = (insumo.material || '').trim().toUpperCase()
    const cantidad = Number(insumo.cantidad) || 0
    if (LIGANTES.includes(material) && cantidad > MAX_PORCENTAJE_LIGANTE) {
      return `${material} al ${formatoPct(cantidad)} %: un ligante no puede pasar de ${MAX_PORCENTAJE_LIGANTE} %. ¿Quisiste poner ${formatoPct(cantidad / 10)} %?`
    }
    if (cantidad > 100) {
      return `${material} al ${formatoPct(cantidad)} %: ningún insumo puede pasar de 100 %.`
    }
    suma += cantidad
  }
  if (suma > MAX_SUMA_PORCENTAJES) {
    return `Los insumos en % suman ${formatoPct(suma)} % (máximo ${MAX_SUMA_PORCENTAJES} %). Revisá el dosaje.`
  }
  return null
}
