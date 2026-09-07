// Service de Home/Dashboard — réplica del "Panel de control" del sistema
// legado (memory/pending.md, 2026-09-04: relevado en vivo contra
// produccion.vialtec.app a pedido de Federico), extendido 2026-09-06 con la
// producción anual por planta y el Gantt de despachos por fórmula (ver
// memory/pending.md).
//
// Todas las consultas acá están acotadas a una semana, 8 semanas o un
// puñado de pedidos confirmados — no aplica la regla de paginación
// (memory/architecture.md, mismo criterio que fetchPedidosSemana()/
// fetchTotalesSemana() de pedidos.service.js).

import { supabase } from '@/config/supabase'
import { obtenerRangoSemana } from '@/modules/pedidos/services/pedidos.service'
import { fetchFormulas } from '@/modules/maestros/services/formulas.service'

const TABLA_PEDIDOS = 'plantas_pedidos'

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

// ---------------------------------------------------------------------------
// Producción anual de asfalto por planta (2026-09-06, pedido de Federico:
// "diferenciar las plantas" — VialTec operó la planta asfáltica Ammann 140
// hasta abril/2026 y migró a la Marini 180 desde mayo/2026 en adelante).
//
// AMMANN_2026_TN es una constante histórica FIJA, no una consulta — sale de
// un resumen manual en Excel (ene-abr/2026, filas "Carpeta Asf" por mes,
// planilla que Federico compartió por WhatsApp) porque ese período nunca se
// cargó en ningún sistema (ni el legado ni este). No cambia nunca, así que
// no tiene sentido una tabla para un solo número — si en el futuro aparece
// una corrección de ese Excel, se actualiza este valor a mano.
// Desglose verificado (suma de la columna "SUMA (Tn/m3)" filtrada a
// material que empieza con "Carpeta Asf", por hoja): ene 3813.76 + feb
// 2973.06 + mar 2701.88 + abr 2428.01 = 11916.71 tn.
const AMMANN_2026_TN = 11916.71

// Hormigón pre-mayo/2026 (2026-09-06, pedido de Federico): mismo Excel que
// Ammann, pero sin diferenciar por planta ("el hormigón va todo junto") —
// un solo número que se suma al acumulado en vivo de este sistema. Suma de
// filas "H-xx"/"Mezcla Cemento" por hoja: ene 1371.5 + feb 1325.3 + mar
// 544.8 + abr 380.1 = 3621.7 m³. Confirmado con Federico: las filas
// "Salida 0/6" (549.6) y "Salida Arena" (10) del mismo Excel NO se cuentan
// (no son producción de mezcla, quedan afuera de todos los totales).
export const HORMIGON_PRE_MAYO_2026_M3 = 3621.7

// Desglose MES A MES de los dos totales fijos de arriba (2026-09-07, pedido
// de Federico — Informe Mensual: "Resumen Anual" no incluía ene-abr/2026
// porque fetchResumenAnual() solo consulta plantas_pedidos, y ese período
// nunca se cargó ahí — mismo motivo por el que existen AMMANN_2026_TN/
// HORMIGON_PRE_MAYO_2026_M3 arriba). Mismas cifras exactas, mismo Excel de
// origen, solo desagregadas por mes en vez de sumadas en un único total —
// ver los comentarios de arriba para la fuente y el desglose ya verificado
// (ene 3813.76+feb 2973.06+mar 2701.88+abr 2428.01 = 11916.71;
// ene 1371.5+feb 1325.3+mar 544.8+abr 380.1 = 3621.7). Usado por
// informe-mensual.service.js#fetchResumenAnual() — no se declara ahí para
// no duplicar los números (memory/conventions.md).
export const PRODUCCION_PRE_MAYO_2026 = {
  '2026-01': { asfaltoTn: 3813.76, hormigonM3: 1371.5 },
  '2026-02': { asfaltoTn: 2973.06, hormigonM3: 1325.3 },
  '2026-03': { asfaltoTn: 2701.88, hormigonM3: 544.8 },
  '2026-04': { asfaltoTn: 2428.01, hormigonM3: 380.1 },
}

/**
 * Marini 180 SÍ es una consulta en vivo (no una constante): es la planta que
 * usa este sistema desde mayo/2026, así que su acumulado sigue creciendo con
 * cada despacho nuevo — a diferencia de Ammann, que ya cerró. Nota: hasta
 * que se corra la migración final del corte (memory/pending.md "Paso 4"),
 * este número no incluye los despachos de asfalto que todavía viven solo en
 * el legado (kv_store) sin migrar a plantas_pedidos — crece solo,
 * automáticamente, a medida que se despachan o se migran.
 */
export async function fetchProduccionAnualAsfalto() {
  const { data, error } = await supabase
    .from(TABLA_PEDIDOS)
    .select('cantidad_despachada')
    .eq('tipo', 'asfalto')
    .eq('estado', 'despachado')
    .gte('fecha_programada', '2026-05-01')

  if (error) throw error

  const mariniTn = (data ?? []).reduce((acc, p) => acc + (Number(p.cantidad_despachada) || 0), 0)

  return {
    ammannTn: AMMANN_2026_TN,
    mariniTn,
    totalTn: AMMANN_2026_TN + mariniTn,
  }
}

/**
 * Producción anual de hormigón (2026-09-06, pedido de Federico: card nueva
 * en Home, mismo criterio que fetchProduccionAnualAsfalto() pero SIN
 * diferenciar por planta — "el hormigón va todo junto" — un solo total.
 */
export async function fetchProduccionAnualHormigon() {
  const { data, error } = await supabase
    .from(TABLA_PEDIDOS)
    .select('cantidad_despachada')
    .eq('tipo', 'hormigon')
    .eq('estado', 'despachado')
    .gte('fecha_programada', '2026-05-01')

  if (error) throw error

  const enSistemaM3 = (data ?? []).reduce((acc, p) => acc + (Number(p.cantidad_despachada) || 0), 0)

  return { totalM3: HORMIGON_PRE_MAYO_2026_M3 + enSistemaM3 }
}

// ---------------------------------------------------------------------------
// Gantt de despachos por fórmula (2026-09-06, pedido de Federico: reemplaza
// la card "Consumo de material" que había antes — "qué fórmula sale más,
// cantidades, algo copado con respecto a la producción"). DESPACHOS reales
// por fórmula en su propia unidad (tn asfalto / m³ hormigón) — asfalto y
// hormigón nunca comparten un mismo eje (cada fórmula se normaliza contra
// su propio máximo en el Gantt, ver useDashboardHome.js). Mismo patrón de
// ventana de 8 semanas que el resto de este archivo.
//
// @returns {Promise<{ semanas: string[], porFormula: { nombre: string, tipo: string, valores: number[] }[] }>}
export async function fetchDespachosPorFormulaSemana(cantidadSemanas = 8, fechaReferencia = new Date()) {
  const semanas = []
  for (let i = cantidadSemanas - 1; i >= 0; i--) {
    const ref = new Date(fechaReferencia)
    ref.setDate(ref.getDate() - i * 7)
    const { lunes, domingo } = obtenerRangoSemana(ref)
    semanas.push({ lunes, domingo, label: `S${lunes.getDate()}/${lunes.getMonth() + 1}` })
  }

  const { data, error } = await supabase
    .from(TABLA_PEDIDOS)
    .select('fecha_programada, cantidad_despachada, formula_id, tipo')
    .eq('estado', 'despachado')
    .eq('archivado', false)
    .gte('fecha_programada', aFechaISO(semanas[0].lunes))
    .lte('fecha_programada', aFechaISO(semanas[semanas.length - 1].domingo))

  if (error) throw error

  const formulas = await fetchFormulas({ soloActivas: false })
  const formulasPorId = Object.fromEntries(formulas.map((f) => [f.id, f]))
  const semanasISO = semanas.map((s) => ({ desde: aFechaISO(s.lunes), hasta: aFechaISO(s.domingo) }))

  const porFormula = new Map() // formula_id -> { nombre, tipo, valores: number[] }

  for (const pedido of data ?? []) {
    const formula = pedido.formula_id ? formulasPorId[pedido.formula_id] : null
    const cantidad = Number(pedido.cantidad_despachada) || 0
    if (!formula || cantidad <= 0) continue

    const idxSemana = semanasISO.findIndex((s) => pedido.fecha_programada >= s.desde && pedido.fecha_programada <= s.hasta)
    if (idxSemana === -1) continue

    if (!porFormula.has(formula.id)) {
      porFormula.set(formula.id, { nombre: formula.nombre, tipo: pedido.tipo, valores: new Array(cantidadSemanas).fill(0) })
    }
    porFormula.get(formula.id).valores[idxSemana] += cantidad
  }

  return {
    semanas: semanas.map((s) => s.label),
    porFormula: [...porFormula.values()],
  }
}
