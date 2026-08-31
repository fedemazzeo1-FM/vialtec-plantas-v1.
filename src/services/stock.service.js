// Service de Stock — único punto de acceso a Supabase para plantas_stock y
// plantas_stock_movimientos (migración 13). El catálogo de materiales
// (plantas_materiales) vive en maestros.service.js — este service lo LEE,
// no lo duplica (memory/conventions.md: lógica compartida en un solo lugar).
//
// Todo el stock se maneja en kg internamente (memory/business-rules.md); la
// UI convierte a tn dividiendo por 1000. Escribir SIEMPRE vía las RPC
// (registrar_movimiento_manual / registrar_relevamiento_stock) o, para
// ingreso/egreso de áridos y descuento por despacho, vía las RPC de
// Báscula/Pedidos (registrar_pesada_bascula / finalizar_despacho /
// corregir_despacho) — nunca un UPDATE directo sobre plantas_stock, se
// perdería el registro en plantas_stock_movimientos.

import { supabase } from '@/config/supabase'
import { fetchPagina } from '@/services/fetch-paginado'

/**
 * Semáforo 3 colores contra stock_minimo_kg/stock_maximo_kg del material
 * (memory/relevamiento-sistema-viejo.md §6). El punto de corte exacto entre
 * "verde" y "amarillo" no está documentado con precisión en el legado (solo
 * se confirmó que existen 3 estados y una barra min/max) — acá se usa un
 * margen del 20% por encima del mínimo como "ajustado". Ajustar si Federico
 * define un valor real de producción.
 */
export function calcularEstadoSemaforo(cantidadKg, minimoKg, maximoKg) {
  if (minimoKg == null) return 'verde'
  if (cantidadKg <= 0 || cantidadKg < minimoKg) return 'rojo'
  if (cantidadKg < minimoKg * 1.2) return 'amarillo'
  return 'verde'
}

/**
 * Cards de "Stock actual": un material por fila (solo controla_stock=true,
 * activo=true), con su saldo actual (0 si todavía no tiene ningún
 * movimiento) y el estado del semáforo ya calculado.
 */
export async function fetchStockActual() {
  const [materiales, stock] = await Promise.all([
    supabase.from('plantas_materiales').select('*').eq('activo', true).eq('controla_stock', true).order('nombre', { ascending: true }),
    supabase.from('plantas_stock').select('*'),
  ])
  if (materiales.error) throw materiales.error
  if (stock.error) throw stock.error

  const stockPorMaterial = new Map((stock.data ?? []).map((s) => [s.material_id, s]))

  return (materiales.data ?? []).map((material) => {
    const fila = stockPorMaterial.get(material.id)
    const cantidadKg = Number(fila?.cantidad_kg ?? 0)
    return {
      ...material,
      cantidadKg,
      actualizadoEn: fila?.actualizado_en ?? null,
      estado: calcularEstadoSemaforo(cantidadKg, material.stock_minimo_kg, material.stock_maximo_kg),
    }
  })
}

// ---------------------------------------------------------------------------
// Historial de movimientos (paginado — memory/architecture.md, tabla que
// crece sin límite)
// ---------------------------------------------------------------------------

const TIPOS_INGRESO = ['ingreso_proveedor', 'ingreso_manual']

/**
 * @param {{ materialId?: string, tipo?: string, desde?: string, hasta?: string }} filtros
 */
export async function fetchMovimientos(filtros = {}, { pagina = 1, tamanoPagina = 30 } = {}) {
  const resultado = await fetchPagina(
    () => {
      let query = supabase
        .from('plantas_stock_movimientos')
        .select('*, plantas_materiales(nombre)', { count: 'exact' })
        .order('fecha_movimiento', { ascending: false })

      if (filtros.materialId) query = query.eq('material_id', filtros.materialId)
      if (filtros.tipo) query = query.eq('tipo', filtros.tipo)
      if (filtros.desde) query = query.gte('fecha_movimiento', filtros.desde)
      if (filtros.hasta) query = query.lte('fecha_movimiento', `${filtros.hasta}T23:59:59`)

      return query
    },
    { pagina, tamanoPagina }
  )

  return {
    ...resultado,
    filas: resultado.filas.map((m) => ({
      ...m,
      materialNombre: m.plantas_materiales?.nombre ?? '—',
      esIngreso: TIPOS_INGRESO.includes(m.tipo) || m.cantidad_kg > 0,
    })),
  }
}

// ---------------------------------------------------------------------------
// Movimientos manuales + relevamiento (RPC, migración 13)
// ---------------------------------------------------------------------------

/**
 * @param {{ materialId: string, tipo: 'ingreso_manual'|'egreso_manual', cantidadKg: number,
 *   origen?: string, numeroRemito?: string, observaciones?: string }} datos
 */
export async function registrarMovimientoManual({ materialId, tipo, cantidadKg, origen, numeroRemito, observaciones }) {
  const { data, error } = await supabase.rpc('registrar_movimiento_manual', {
    p_material_id: materialId,
    p_tipo: tipo,
    p_cantidad_kg: Number(cantidadKg),
    p_origen: origen || null,
    p_numero_remito: numeroRemito || null,
    p_observaciones: observaciones || null,
  })
  if (error) throw error
  return data
}

/**
 * Relevamiento mensual — NO pisa el stock directo (decisión de Federico,
 * 2026-08-31): la RPC calcula la diferencia contra plantas_stock e inserta
 * un movimiento 'ajuste' por cada material que cambió. Puede rechazar el
 * guardado completo (saveStockGuard) si el resultado parece anómalo.
 *
 * @param {Array<{ materialId: string, cantidadKg: number }>} conteos
 * @param {string} [motivo]
 */
export async function registrarRelevamiento(conteos, motivo) {
  const payload = conteos.map((c) => ({ material_id: c.materialId, cantidad_kg: Number(c.cantidadKg) }))
  const { data, error } = await supabase.rpc('registrar_relevamiento_stock', {
    p_conteos: payload,
    p_motivo: motivo || 'Relevamiento mensual',
  })
  if (error) throw error
  return data ?? []
}
