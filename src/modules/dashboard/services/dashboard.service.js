// Service de Home/Dashboard — réplica del "Panel de control" del sistema
// legado (memory/pending.md, 2026-09-04: relevado en vivo contra
// produccion.vialtec.app a pedido de Federico). Consultas propias de este
// módulo; reusa calcularConsumoTotalKg (formulas.service.js) en vez de
// duplicar el cálculo de consumo (memory/conventions.md — mismo patrón que
// useAlertaStockSemana.js, pero histórico semana a semana en vez de
// proyectado a la semana en curso).
//
// Todas las consultas acá están acotadas a una semana o a un puñado de
// pedidos confirmados — no aplica la regla de paginación (memory/architecture.md,
// mismo criterio que fetchPedidosSemana()/fetchTotalesSemana() de
// pedidos.service.js).

import { supabase } from '@/config/supabase'
import { obtenerRangoSemana } from '@/modules/pedidos/services/pedidos.service'
import { fetchFormulas, calcularConsumoTotalKg } from '@/modules/maestros/services/formulas.service'

const TABLA_PEDIDOS = 'plantas_pedidos'
const MATERIALES_SIN_DESCUENTO = ['agua', 'purgue'] // memory/business-rules.md

function aFechaISO(date) {
  return date.toISOString().slice(0, 10)
}

/**
 * KPIs semanales del Home — réplica de 3 de las 5 cards "Panel de control"
 * del legado (Ajustados/Críticos salen de Stock, ver useDashboardHome.js):
 * - pedidosActivos: solicitado+confirmado+postergado de la semana en curso
 *   ("en curso" — NO incluye despachado/cancelado, a diferencia de
 *   fetchPedidosSemana() de Plan Semanal, que tiene otro criterio).
 * - confirmados: solo confirmado ("X para despachar").
 * - despachos: cantidad + tn(asfalto)/m³(hormigón) de lo DESPACHADO esta semana.
 */
export async function fetchResumenSemanaHome(fechaReferencia = new Date()) {
  const { lunes, domingo } = obtenerRangoSemana(fechaReferencia)

  const { data, error } = await supabase
    .from(TABLA_PEDIDOS)
    .select('estado, tipo, cantidad_despachada')
    .gte('fecha_programada', aFechaISO(lunes))
    .lte('fecha_programada', aFechaISO(domingo))
    .eq('archivado', false)

  if (error) throw error

  let pedidosActivos = 0
  let confirmados = 0
  let despachosCantidad = 0
  let asfaltoTn = 0
  let hormigonM3 = 0

  for (const p of data ?? []) {
    if (p.estado === 'solicitado' || p.estado === 'confirmado' || p.estado === 'postergado') pedidosActivos += 1
    if (p.estado === 'confirmado') confirmados += 1
    if (p.estado === 'despachado') {
      despachosCantidad += 1
      const cantidad = Number(p.cantidad_despachada) || 0
      if (p.tipo === 'hormigon') hormigonM3 += cantidad
      else asfaltoTn += cantidad
    }
  }

  return { pedidosActivos, confirmados, despachos: { cantidad: despachosCantidad, asfaltoTn, hormigonM3 } }
}

/**
 * Próximos despachos: pedidos `confirmado`, los `limite` más próximos por
 * fecha_programada ascendente (memory/pending.md — réplica del legado:
 * "Todos los pedidos confirmados", vencidos primero por el propio orden).
 */
export async function fetchProximosDespachos(limite = 5) {
  const { data, error } = await supabase
    .from(TABLA_PEDIDOS)
    .select('*')
    .eq('estado', 'confirmado')
    .eq('archivado', false)
    .order('fecha_programada', { ascending: true })
    .limit(limite)

  if (error) throw error
  return data ?? []
}

/**
 * Consumo real semanal (últimas `cantidadSemanas` semanas, hoy incluida)
 * por material, a partir de los pedidos DESPACHADOS de cada semana
 * (cantidad_despachada × fórmula — mismo cálculo que
 * useAlertaStockSemana.js, pero histórico semana a semana en vez de
 * proyectado a la semana en curso). Semanas sin despacho de un material
 * quedan en 0 (no se omiten — el gráfico del legado no salta semanas).
 *
 * @returns {Promise<{ semanas: string[], porMaterial: Record<string, number[]> }>}
 *   `semanas` son las etiquetas en orden cronológico (más vieja primero);
 *   `porMaterial[nombre]` es un array del mismo largo, kg por semana.
 */
export async function fetchConsumoSemanalPorMaterial(cantidadSemanas = 8, fechaReferencia = new Date()) {
  const semanas = []
  for (let i = cantidadSemanas - 1; i >= 0; i--) {
    const ref = new Date(fechaReferencia)
    ref.setDate(ref.getDate() - i * 7)
    const { lunes, domingo } = obtenerRangoSemana(ref)
    semanas.push({ lunes, domingo, label: `S${lunes.getDate()}/${lunes.getMonth() + 1}` })
  }

  const { data, error } = await supabase
    .from(TABLA_PEDIDOS)
    .select('fecha_programada, cantidad_despachada, formula_id')
    .eq('estado', 'despachado')
    .eq('archivado', false)
    .gte('fecha_programada', aFechaISO(semanas[0].lunes))
    .lte('fecha_programada', aFechaISO(semanas[semanas.length - 1].domingo))

  if (error) throw error

  const formulas = await fetchFormulas({ soloActivas: false })
  const formulasPorId = Object.fromEntries(formulas.map((f) => [f.id, f]))
  const semanasISO = semanas.map((s) => ({ desde: aFechaISO(s.lunes), hasta: aFechaISO(s.domingo) }))

  const consumoPorMaterial = new Map() // nombre -> number[cantidadSemanas]

  for (const pedido of data ?? []) {
    const formula = pedido.formula_id ? formulasPorId[pedido.formula_id] : null
    const cantidad = Number(pedido.cantidad_despachada) || 0
    if (!formula || cantidad <= 0) continue

    const idxSemana = semanasISO.findIndex((s) => pedido.fecha_programada >= s.desde && pedido.fecha_programada <= s.hasta)
    if (idxSemana === -1) continue

    for (const insumo of calcularConsumoTotalKg(formula, cantidad)) {
      const clave = (insumo.material || '').trim()
      if (!clave || MATERIALES_SIN_DESCUENTO.includes(clave.toLowerCase())) continue
      if (!consumoPorMaterial.has(clave)) consumoPorMaterial.set(clave, new Array(cantidadSemanas).fill(0))
      consumoPorMaterial.get(clave)[idxSemana] += insumo.kg
    }
  }

  return {
    semanas: semanas.map((s) => s.label),
    porMaterial: Object.fromEntries(consumoPorMaterial),
  }
}
