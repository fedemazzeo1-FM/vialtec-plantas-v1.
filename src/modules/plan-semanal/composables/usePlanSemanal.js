// Composable del Plan semanal: semana cargada, días de la matriz, totales y
// acciones sobre los pedidos (confirmar y, desde 2026-10-22, despachar).
// Extraído de PlanSemanalView.vue (2026-10-22) — la vista queda como
// template puro (memory/conventions.md). Toda la persistencia pasa por
// pedidos.service.js.
//
// Despachar desde el calendario (pedido de Federico 2026-10-22): usa los
// mismos composables que Pedidos (useDespachoAsfalto/useCargaHormigon) —
// mismas validaciones, mismas RPC (registrar_carga_* + finalizar_despacho,
// que validan rol/estado y registran la auditoría en la misma transacción)
// y mismo cierre parcial con pedido residual. No hay un segundo camino.

import { computed, ref } from 'vue'
import {
  obtenerRangoSemana,
  fetchPedidosSemana,
  fetchTotalesSemana,
  confirmarPedido,
} from '@/modules/pedidos/services/pedidos.service'
import { useDespachoAsfalto } from '@/modules/pedidos/composables/useDespachoAsfalto'
import { useCargaHormigon } from '@/modules/pedidos/composables/useCargaHormigon'
import { fetchObras } from '@/services/flota.service'
import { fetchFormulas } from '@/modules/maestros/services/formulas.service'
import { patentesService } from '@/modules/maestros/services/maestros.service'
import { hoyISO } from '@/services/fecha'
import { esCircuitoBascula, etiquetasTotales, sumarEnTotal, totalesVacios } from '@/config/tipos-producto'

const NOMBRES_DIA = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo']

export function usePlanSemanal() {
  const fechaRef = ref(new Date())
  const pedidos = ref([])
  const totales = ref({ rango: null, porObra: [], total: totalesVacios() })
  const obras = ref([])
  const formulas = ref([])
  const patentes = ref([])
  const cargando = ref(false)
  const error = ref(null)

  const obrasPorId = computed(() => Object.fromEntries(obras.value.map((o) => [o.id, o])))
  const formulasPorId = computed(() => Object.fromEntries(formulas.value.map((f) => [f.id, f])))

  // Nombre a mostrar por destino — venta externa vs. obra propia vs. dato
  // huérfano (fix 2026-09-03, bug real reportado por Federico: "Obra #null").
  // La vista asumía que TODO pedido tiene obra_id, pero una venta externa
  // (tipo_pedido='venta') nunca la tiene por diseño — mismo criterio que
  // `destinoDe()` ya usa PedidosView/DespachosView, replicado acá (no existía
  // un helper compartido para esto, son 3 formas ligeramente distintas de
  // nombrar según qué objeto trae cada vista — no vale la pena forzar un solo
  // helper transversal por 3 líneas de lógica).
  function nombreDestinoPedido(p) {
    if (!p) return ''
    if (p.tipo_pedido === 'venta') return p.cliente_externo || 'Venta externa'
    if (p.obra_id) return obrasPorId.value[p.obra_id]?.nombre ?? `Obra #${p.obra_id}`
    // obra_id null y NO es venta -> dato huérfano real de la migración del
    // histórico legado (memory/pending.md, "Municipalidad Exaltación de la
    // Cruz" sin equivalente en flota_obras) — fallback legible en vez de
    // "Obra #null" literal, pero sigue señalando que falta resolverlo.
    return 'Obra sin asignar'
  }

  function nombreDestinoTotal(t) {
    if (t.obraId) return obrasPorId.value[t.obraId]?.nombre ?? `Obra #${t.obraId}`
    return t.clienteExterno || 'Obra sin asignar'
  }

  // Formato de mejora visual (2026-09-01, pedido de Federico: "dejalo bien
  // profesional"): cada día trae número de fecha + nombre de mes separados
  // (para el header de la columna) y un flag `esHoy` para resaltar la
  // columna del día actual, mismo criterio que un calendario semanal
  // estándar.
  const diasSemana = computed(() => {
    const { lunes } = obtenerRangoSemana(fechaRef.value)
    const hoy = hoyISO()
    return Array.from({ length: 7 }, (_, i) => {
      const fecha = new Date(lunes)
      fecha.setDate(lunes.getDate() + i)
      const iso = fecha.toISOString().slice(0, 10)
      const pedidosDia = pedidos.value.filter((p) => p.fecha_programada === iso)

      // Tilde + cantidades cuando el día cerró 100% despachado (2026-09-03,
      // réplica del legado pedida por Federico: "como tiene el sistema
      // viejo, abajo de la fecha"). Los totales del día usan cantidad_despachada
      // (cantidadReal) — mismo criterio de "fuente de verdad" que el resto de
      // la app (memory/business-rules.md), no cantidad_solicitada.
      const todosDespachados = pedidosDia.length > 0 && pedidosDia.every((p) => p.estado === 'despachado')
      // Un total por tipo de producto (config/tipos-producto.js), solo los
      // que tienen algo.
      const totalesDia = totalesVacios()
      for (const p of pedidosDia) {
        if (p.estado === 'despachado') sumarEnTotal(totalesDia, p.tipo, p.cantidad_despachada)
      }
      const totalesDiaLabels = etiquetasTotales(totalesDia, { soloConValor: true })

      return {
        etiqueta: NOMBRES_DIA[i],
        etiquetaCorta: NOMBRES_DIA[i].slice(0, 3),
        numeroDia: fecha.getDate(),
        mesLabel: fecha.toLocaleDateString('es-AR', { month: 'short' }).replace('.', ''),
        iso,
        esHoy: iso === hoy,
        esFinDeSemana: i >= 5,
        pedidos: pedidosDia,
        todosDespachados,
        totalesDiaLabels,
      }
    })
  })

  const rangoLabel = computed(() =>
    diasSemana.value.length ? `${diasSemana.value[0].iso} — ${diasSemana.value[6].iso}` : ''
  )

  // Franja diaria mobile (rediseño Mobile-First 2026-09-22): día
  // seleccionado en la franja horizontal de arriba, cuyo detalle se
  // despliega abajo. Se recalcula cada vez que cambia la semana cargada —
  // no tiene sentido arrastrar el ISO de la semana anterior a la nueva.
  const diaSeleccionadoIso = ref(null)

  const diaSeleccionado = computed(
    () => diasSemana.value.find((d) => d.iso === diaSeleccionadoIso.value) ?? diasSemana.value[0] ?? null
  )

  function seleccionarDiaPorDefecto() {
    const hoy = hoyISO()
    diaSeleccionadoIso.value = diasSemana.value.some((d) => d.iso === hoy) ? hoy : diasSemana.value[0]?.iso ?? null
  }

  /**
   * @param {{ mantenerDia?: boolean }} opciones mantenerDia: refresco tras
   *   confirmar/despachar — el usuario sigue en el día que estaba mirando
   *   (antes volvía a hoy).
   */
  async function cargarSemana({ mantenerDia = false } = {}) {
    cargando.value = true
    error.value = null
    try {
      const [listaPedidos, totalesSemana, listaObras, listaFormulas] = await Promise.all([
        fetchPedidosSemana(fechaRef.value),
        fetchTotalesSemana(fechaRef.value),
        fetchObras(),
        fetchFormulas({ soloActivas: true }),
      ])
      pedidos.value = listaPedidos
      totales.value = totalesSemana
      obras.value = listaObras
      formulas.value = listaFormulas
      const diaSigueEnLaSemana = diasSemana.value.some((d) => d.iso === diaSeleccionadoIso.value)
      if (!mantenerDia || !diaSigueEnLaSemana) seleccionarDiaPorDefecto()
    } catch (e) {
      error.value = e.message
    } finally {
      cargando.value = false
    }
  }

  const refrescarMismoDia = () => cargarSemana({ mantenerDia: true })

  function semanaAnterior() {
    const f = new Date(fechaRef.value)
    f.setDate(f.getDate() - 7)
    fechaRef.value = f
    cargarSemana()
  }

  function semanaSiguiente() {
    const f = new Date(fechaRef.value)
    f.setDate(f.getDate() + 7)
    fechaRef.value = f
    cargarSemana()
  }

  /** "Hoy" (rediseño Mobile-First 2026-09-22, pedido explícito de Federico:
   * volver rápido al día actual desde la franja) — salta directo a la semana
   * en curso, sea cual sea la que esté cargada, y selecciona el día de hoy. */
  function irAHoySemana() {
    fechaRef.value = new Date()
    cargarSemana()
  }

  async function confirmar(pedido) {
    error.value = null
    try {
      await confirmarPedido(pedido.id)
      await refrescarMismoDia()
    } catch (e) {
      error.value = e.message
    }
  }

  // Despacho: los mismos composables y modales que Pedidos. Al cerrar el
  // despacho con éxito se recarga la semana (el pedido pasa a despachado y,
  // si se dividió, aparece el residual en su fecha).
  const despacho = useDespachoAsfalto(refrescarMismoDia)
  const cargaHormigon = useCargaHormigon(refrescarMismoDia)

  // Patentes para las sugerencias del modal: se piden recién al primer
  // despacho (los roles que no despachan no hacen la consulta).
  let patentesPedidas = false
  async function cargarPatentes() {
    if (patentesPedidas) return
    patentesPedidas = true
    try {
      patentes.value = await patentesService.fetch({ soloActivos: true })
    } catch (e) {
      patentesPedidas = false
      error.value = e.message
    }
  }

  /** Abre el modal "Registrar despacho" que corresponde al circuito del pedido. */
  function abrirDespacho(pedido) {
    error.value = null
    cargarPatentes()
    if (esCircuitoBascula(pedido.tipo)) despacho.abrir(pedido)
    else cargaHormigon.abrir(pedido)
  }

  return {
    pedidos,
    totales,
    patentes,
    cargando,
    error,
    formulasPorId,
    nombreDestinoPedido,
    nombreDestinoTotal,
    diasSemana,
    rangoLabel,
    diaSeleccionadoIso,
    diaSeleccionado,
    cargarSemana,
    semanaAnterior,
    semanaSiguiente,
    irAHoySemana,
    confirmar,
    despacho,
    cargaHormigon,
    abrirDespacho,
  }
}
