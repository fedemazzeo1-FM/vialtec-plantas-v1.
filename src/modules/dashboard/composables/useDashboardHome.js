// Composable de Home — réplica del "Panel de control" del legado
// (memory/pending.md, 2026-09-04). DashboardView.vue queda como template
// puro (memory/conventions.md): toda la carga/cálculo vive acá.

import { computed, reactive, ref } from 'vue'
import {
  fetchResumenSemanaHome,
  fetchProximosDespachos,
  fetchProduccionAnualAsfalto,
  fetchProduccionAnualHormigon,
  fetchDespachosPorFormulaSemana,
} from '@/modules/dashboard/services/dashboard.service'
import { fetchStockActual } from '@/services/stock.service'
import { fetchObras } from '@/services/flota.service'
import { fetchFormulas } from '@/modules/maestros/services/formulas.service'
import { obtenerRangoSemana } from '@/modules/pedidos/services/pedidos.service'
import { hoyISO } from '@/services/fecha'
// Mismo cálculo mes a mes que ya usa el Informe Mensual (Despachos →
// Resumen anual) — no se duplica acá (memory/conventions.md). Cruzado a
// nivel composable, no de service-a-service: dashboard.service.js ya lo
// importa `informe-mensual.service.js` en sentido contrario
// (PRODUCCION_PRE_MAYO_2026), así que importarlo también desde acá abajo
// crearía un ciclo — a este nivel (composable, no service) no hay ciclo.
import { fetchResumenAnual } from '@/modules/despachos/services/informe-mensual.service'

export function useDashboardHome() {
  const error = ref(null)

  // -------------------------------------------------------------------------
  // Header ("Vie 4 de septiembre · Semana del 31/08/2026 al 06/09/2026")
  // -------------------------------------------------------------------------

  const { lunes, domingo } = obtenerRangoSemana(new Date())
  const encabezadoFecha = new Date().toLocaleDateString('es-AR', { weekday: 'short', day: 'numeric', month: 'long' })
  const encabezadoRangoSemana = `${lunes.toISOString().slice(0, 10)} al ${domingo.toISOString().slice(0, 10)}`

  // -------------------------------------------------------------------------
  // KPIs semanales + stock (Ajustados/Críticos, mismo semáforo que Stock)
  // -------------------------------------------------------------------------

  const cargandoKpis = ref(false)
  const resumenSemana = reactive({ pedidosActivos: 0, confirmados: 0, despachos: { cantidad: 0, asfaltoTn: 0, hormigonM3: 0 } })
  const stockActual = ref([])

  const materialesAjustados = computed(() => stockActual.value.filter((m) => m.estado === 'amarillo').length)
  const materialesCriticos = computed(() => stockActual.value.filter((m) => m.estado === 'rojo').length)

  async function cargarKpisYStock() {
    cargandoKpis.value = true
    error.value = null
    try {
      const [resumen, stock] = await Promise.all([fetchResumenSemanaHome(), fetchStockActual()])
      Object.assign(resumenSemana, resumen)
      stockActual.value = stock
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoKpis.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Próximos despachos (confirmados, vencidos primero)
  // -------------------------------------------------------------------------

  const cargandoProximos = ref(false)
  const proximosDespachos = ref([])
  const obras = ref([])
  const formulas = ref([])
  const obrasPorId = computed(() => Object.fromEntries(obras.value.map((o) => [o.id, o])))
  const formulasPorId = computed(() => Object.fromEntries(formulas.value.map((f) => [f.id, f])))

  const hoy = hoyISO()

  /** Destino, fórmula/cantidad y etiqueta Vencido/Hoy/fecha — mismo criterio que la card del legado. */
  const filasProximos = computed(() =>
    proximosDespachos.value.map((p) => {
      const destino = p.tipo_pedido === 'venta' ? p.cliente_externo || '—' : obrasPorId.value[p.obra_id]?.nombre ?? 'Obra sin asignar'
      const formulaNombre = formulasPorId.value[p.formula_id]?.nombre ?? '—'
      const unidad = p.tipo === 'hormigon' ? 'm³' : 'tn'
      let etiqueta = null
      let etiquetaVariante = 'default'
      if (p.fecha_programada < hoy) {
        etiqueta = 'Vencido'
        etiquetaVariante = 'danger'
      } else if (p.fecha_programada === hoy) {
        etiqueta = 'Hoy'
        etiquetaVariante = 'warning'
      }
      const [, mes, dia] = p.fecha_programada.split('-')
      return {
        ...p,
        destino,
        formulaNombre,
        cantidadLabel: `${p.cantidad_solicitada} ${unidad}`,
        diaCorto: dia,
        mesCorto: new Date(2000, Number(mes) - 1, 1).toLocaleDateString('es-AR', { month: 'short' }).replace('.', '').toUpperCase(),
        etiqueta,
        etiquetaVariante,
      }
    })
  )

  async function cargarProximos() {
    cargandoProximos.value = true
    error.value = null
    try {
      const [listaProximos, listaObras, listaFormulas] = await Promise.all([
        fetchProximosDespachos(5),
        fetchObras(),
        fetchFormulas({ soloActivas: false }),
      ])
      proximosDespachos.value = listaProximos
      obras.value = listaObras
      formulas.value = listaFormulas
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoProximos.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Producción anual de asfalto — 3 cards (2026-09-06, pedido de Federico):
  // total del año, planta Ammann 140 (constante histórica, hasta abril/2026)
  // y planta Marini 180 (en vivo, desde mayo/2026 — ver dashboard.service.js).
  // -------------------------------------------------------------------------

  const cargandoProduccionAnual = ref(false)
  const produccionAnual = reactive({ ammannTn: 0, mariniTn: 0, totalTn: 0 })

  async function cargarProduccionAnual() {
    cargandoProduccionAnual.value = true
    error.value = null
    try {
      Object.assign(produccionAnual, await fetchProduccionAnualAsfalto())
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoProduccionAnual.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Producción anual de hormigón — 1 card (2026-09-06, pedido de Federico):
  // mismo criterio que produccionAnual (asfalto) pero sin plantas, un solo
  // total ("el hormigón va todo junto").
  // -------------------------------------------------------------------------

  const cargandoProduccionHormigon = ref(false)
  const produccionHormigon = reactive({ totalM3: 0 })

  async function cargarProduccionHormigon() {
    cargandoProduccionHormigon.value = true
    error.value = null
    try {
      Object.assign(produccionHormigon, await fetchProduccionAnualHormigon())
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoProduccionHormigon.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Producción mensual del año — 2 gráficos de barras (2026-09-07, pedido de
  // Federico: "ese gráfico [el del Informe Mensual] replicalo en Home").
  // Mismo dato que "Resumen anual" del Informe Mensual (fetchResumenAnual),
  // reusado tal cual — no se vuelve a calcular. Asfalto (tn) y Hormigón (m³)
  // quedan en 2 arrays separados a propósito: nunca comparten eje (dataviz
  // skill, VBarraMensual.vue es de una sola serie).
  // -------------------------------------------------------------------------

  const cargandoProduccionMensual = ref(false)
  const produccionMensualAsfalto = ref([])
  const produccionMensualHormigon = ref([])

  async function cargarProduccionMensual() {
    cargandoProduccionMensual.value = true
    error.value = null
    try {
      const mesActual = new Date().toISOString().slice(0, 7)
      const { filas } = await fetchResumenAnual(mesActual)
      produccionMensualAsfalto.value = filas.map((f) => ({ mes: f.mes, valor: f.asfaltoTn }))
      produccionMensualHormigon.value = filas.map((f) => ({ mes: f.mes, valor: f.hormigonM3 }))
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoProduccionMensual.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Gantt de despachos por fórmula — reemplaza "Consumo de material"
  // (2026-09-06, pedido de Federico: "qué fórmula sale más, cantidades, algo
  // copado"). Cada fila (fórmula) se normaliza contra su PROPIO máximo de
  // las 8 semanas — asfalto (tn) y hormigón (m³) nunca comparten una escala
  // común (memory: "un solo eje", ver dataviz skill), el ancho de cada barra
  // solo dice "cuánto respecto a la semana más fuerte de esta misma fórmula".
  // El orden de filas (por total desc) sí responde "qué fórmula sale más".
  // -------------------------------------------------------------------------

  const cargandoGantt = ref(false)
  const ganttSemanas = ref([])
  const ganttFilasRaw = ref([])

  const COLOR_TIPO = {
    asfalto: { barra: 'bg-[#2a78d6]', texto: 'text-[#2a78d6]', punto: 'bg-[#2a78d6]' },
    hormigon: { barra: 'bg-[#eb6834]', texto: 'text-[#eb6834]', punto: 'bg-[#eb6834]' },
  }

  const ganttFilas = computed(() =>
    ganttFilasRaw.value
      .map((f) => {
        const total = f.valores.reduce((a, b) => a + b, 0)
        const max = Math.max(...f.valores, 0)
        const unidad = f.tipo === 'hormigon' ? 'm³' : 'tn'
        return {
          nombre: f.nombre,
          tipo: f.tipo,
          unidad,
          total,
          totalLabel: `${total.toLocaleString('es-AR', { maximumFractionDigits: 1 })} ${unidad}`,
          color: COLOR_TIPO[f.tipo] ?? COLOR_TIPO.asfalto,
          celdas: f.valores.map((valor) => ({
            valor,
            pct: max > 0 ? Math.max(Math.round((valor / max) * 100), valor > 0 ? 10 : 0) : 0,
            label: `${valor.toLocaleString('es-AR', { maximumFractionDigits: 1 })} ${unidad}`,
          })),
        }
      })
      .sort((a, b) => b.total - a.total)
      .slice(0, 8)
  )

  async function cargarGantt() {
    cargandoGantt.value = true
    error.value = null
    try {
      const { semanas, porFormula } = await fetchDespachosPorFormulaSemana(8)
      ganttSemanas.value = semanas
      ganttFilasRaw.value = porFormula
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoGantt.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Arranque
  // -------------------------------------------------------------------------

  function iniciar() {
    cargarKpisYStock()
    cargarProximos()
    cargarProduccionAnual()
    cargarProduccionHormigon()
    cargarProduccionMensual()
    cargarGantt()
  }

  return {
    error,
    encabezadoFecha,
    encabezadoRangoSemana,
    cargandoKpis,
    resumenSemana,
    stockActual,
    materialesAjustados,
    materialesCriticos,
    cargandoProximos,
    filasProximos,
    cargandoProduccionAnual,
    produccionAnual,
    cargandoProduccionHormigon,
    produccionHormigon,
    cargandoProduccionMensual,
    produccionMensualAsfalto,
    produccionMensualHormigon,
    cargandoGantt,
    ganttSemanas,
    ganttFilas,
    iniciar,
  }
}
