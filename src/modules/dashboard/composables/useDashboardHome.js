// Composable de Home — réplica del "Panel de control" del legado
// (memory/pending.md, 2026-09-04). DashboardView.vue queda como template
// puro (memory/conventions.md): toda la carga/cálculo vive acá.

import { computed, reactive, ref } from 'vue'
import { fetchResumenSemanaHome, fetchProximosDespachos, fetchConsumoSemanalPorMaterial } from '@/modules/dashboard/services/dashboard.service'
import { fetchStockActual } from '@/services/stock.service'
import { fetchObras } from '@/services/flota.service'
import { fetchFormulas } from '@/modules/maestros/services/formulas.service'
import { obtenerRangoSemana } from '@/modules/pedidos/services/pedidos.service'
import { hoyISO } from '@/services/fecha'

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
  // Consumo de material — últimas 8 semanas, selector de material
  // -------------------------------------------------------------------------

  const cargandoConsumo = ref(false)
  const consumo = ref({ semanas: [], porMaterial: {} })
  const materialSeleccionado = ref('')

  const materialesConsumo = computed(() => Object.keys(consumo.value.porMaterial).sort((a, b) => a.localeCompare(b, 'es')))

  const valoresMaterialSeleccionado = computed(() => consumo.value.porMaterial[materialSeleccionado.value] ?? [])

  /** [{ semana, valorTn, valorLabel }] para la lista + el sparkline del material elegido. */
  const filasConsumo = computed(() =>
    consumo.value.semanas.map((semana, i) => {
      const kg = valoresMaterialSeleccionado.value[i] ?? 0
      return {
        semana,
        kg,
        valorLabel: kg >= 1000 ? `${(kg / 1000).toFixed(2)} t` : `${kg.toFixed(0)} kg`,
      }
    })
  )

  async function cargarConsumo() {
    cargandoConsumo.value = true
    error.value = null
    try {
      consumo.value = await fetchConsumoSemanalPorMaterial(8)
      if (!materialSeleccionado.value || !consumo.value.porMaterial[materialSeleccionado.value]) {
        materialSeleccionado.value = materialesConsumo.value[0] ?? ''
      }
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoConsumo.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Arranque
  // -------------------------------------------------------------------------

  function iniciar() {
    cargarKpisYStock()
    cargarProximos()
    cargarConsumo()
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
    cargandoConsumo,
    materialesConsumo,
    materialSeleccionado,
    filasConsumo,
    iniciar,
  }
}
