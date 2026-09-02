// Composable de Despachos: listado paginado + filtros, KPIs (mes + acumulado
// histórico), resumen por obra, modal de detalle de cargas, corrección
// post-despacho y remito imprimible. DespachosView.vue queda como template
// puro (memory/conventions.md).
//
// Despachos es una vista SOBRE plantas_pedidos (estado='despachado'), no una
// entidad propia — memory/relevamiento-sistema-viejo.md §3 / Logica sist
// plantas v2.rtf §3.5. La cantidad REAL/DIFERENCIA de cada fila es siempre
// cantidad_despachada del pedido (cantidadReal del remito final cargado en
// Pedidos) — memory/business-rules.md, "Fuente de verdad según el tipo de
// transacción".

import { computed, reactive, ref } from 'vue'
import {
  fetchDespachos,
  fetchAcumuladoHistorico,
  fetchTotalesMes,
  fetchResumenPorObra,
  fetchCargasDelPedido,
  corregirDespacho,
} from '@/services/despachos.service'
import { fetchObras } from '@/services/flota.service'
import { fetchFormulas } from '@/modules/maestros/services/formulas.service'

const TAMANO_PAGINA = 20

function mesActual() {
  const hoy = new Date()
  return `${hoy.getFullYear()}-${String(hoy.getMonth() + 1).padStart(2, '0')}`
}

export function useDespachos() {
  const error = ref(null)

  // -------------------------------------------------------------------------
  // Datos base (obras + fórmulas, para filtros y para resolver nombres)
  // -------------------------------------------------------------------------

  const obras = ref([])
  const formulas = ref([])
  const obrasPorId = computed(() => Object.fromEntries(obras.value.map((o) => [o.id, o])))
  const formulasPorId = computed(() => Object.fromEntries(formulas.value.map((f) => [f.id, f])))

  function destinoDe(pedido) {
    if (!pedido) return ''
    return pedido.tipo_pedido === 'venta' ? pedido.cliente_externo || '—' : obrasPorId.value[pedido.obra_id]?.nombre || '—'
  }

  async function cargarBase() {
    // Fix 2026-09-01: sin try/catch acá, un fallo de red rechazaba la
    // promesa que consume iniciar() sin `.catch()` — error no manejado en
    // consola, cargarDespachos()/cargarResumenPorObra() nunca se llamaban,
    // y la vista quedaba mostrando "No hay despachos que coincidan con el
    // filtro" (falso estado vacío, `cargando` nunca pasaba a `true`) en vez
    // del error real. Mismo patrón que ya usan cargarBase() en
    // useBascula.js/useSimulador.js.
    try {
      const [listaObras, listaFormulas] = await Promise.all([fetchObras(), fetchFormulas({ soloActivas: false })])
      obras.value = listaObras
      formulas.value = listaFormulas
    } catch (e) {
      error.value = e.message
    }
  }

  // -------------------------------------------------------------------------
  // KPIs
  // -------------------------------------------------------------------------

  const kpisMes = ref({ asfaltoTn: 0, hormigonM3: 0 })
  const kpisHistorico = ref({ asfaltoTn: 0, hormigonM3: 0 })

  async function cargarKpis() {
    try {
      const [mes, historico] = await Promise.all([fetchTotalesMes(mesActual()), fetchAcumuladoHistorico()])
      kpisMes.value = mes
      kpisHistorico.value = historico
    } catch (e) {
      error.value = e.message
    }
  }

  // -------------------------------------------------------------------------
  // Listado + filtros + paginación
  // -------------------------------------------------------------------------

  const filas = ref([])
  const totalDespachos = ref(0)
  const paginaActual = ref(1)
  const cargando = ref(false)
  const filtros = reactive({ tipo: '', obraId: '', formulaId: '', desde: '', hasta: '' })

  const filasConNombres = computed(() =>
    filas.value.map((p) => ({
      ...p,
      destino: destinoDe(p),
      formulaNombre: formulasPorId.value[p.formula_id]?.nombre ?? '—',
      diferencia: Number(p.cantidad_solicitada) - Number(p.cantidad_despachada ?? 0),
    }))
  )

  async function cargarDespachos() {
    cargando.value = true
    error.value = null
    try {
      const resultado = await fetchDespachos(
        {
          tipo: filtros.tipo || undefined,
          obraId: filtros.obraId || undefined,
          formulaId: filtros.formulaId || undefined,
          desde: filtros.desde || undefined,
          hasta: filtros.hasta || undefined,
        },
        { pagina: paginaActual.value, tamanoPagina: TAMANO_PAGINA }
      )
      filas.value = resultado.filas
      totalDespachos.value = resultado.total
    } catch (e) {
      error.value = e.message
    } finally {
      cargando.value = false
    }
  }

  function aplicarFiltros() {
    paginaActual.value = 1
    cargarDespachos()
  }

  function limpiarFiltros() {
    filtros.tipo = ''
    filtros.obraId = ''
    filtros.formulaId = ''
    filtros.desde = ''
    filtros.hasta = ''
    aplicarFiltros()
  }

  function cambiarPagina(pagina) {
    paginaActual.value = pagina
    cargarDespachos()
  }

  // -------------------------------------------------------------------------
  // Resumen por obra (selector de mes + grid de cards)
  // -------------------------------------------------------------------------

  const mesResumen = ref(mesActual())
  const resumenObras = ref([])
  const cargandoResumen = ref(false)

  async function cargarResumenPorObra() {
    cargandoResumen.value = true
    error.value = null
    try {
      const resumen = await fetchResumenPorObra(mesResumen.value)
      resumenObras.value = resumen.map((r) => ({
        ...r,
        nombre: r.obraId ? obrasPorId.value[r.obraId]?.nombre || `Obra #${r.obraId}` : r.clienteExterno,
      }))
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoResumen.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Modal "Ver detalle de cargas" (🚛) — patente + cantidad + remito/vale por
  // camión, rango de N° al pie (memory/relevamiento-sistema-viejo.md Etapa 3).
  // -------------------------------------------------------------------------

  const modalDetalleAbierto = ref(false)
  const pedidoDetalle = ref(null)
  const cargasDetalle = ref([])
  const cargandoDetalle = ref(false)

  const rangoNumerosDetalle = computed(() => {
    const numeros = cargasDetalle.value.map((c) => c.numeroRemitoOVale).filter(Boolean)
    if (!numeros.length) return '—'
    return numeros.length === 1 ? numeros[0] : `${numeros[0]}…${numeros[numeros.length - 1]}`
  })

  async function abrirDetalle(pedido) {
    pedidoDetalle.value = pedido
    modalDetalleAbierto.value = true
    cargandoDetalle.value = true
    error.value = null
    try {
      cargasDetalle.value = await fetchCargasDelPedido(pedido.id, pedido.tipo)
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoDetalle.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Modal "Corregir despacho" — Logica sis. plantas v1.rtf §5: solo sobre un
  // despacho ya cerrado, edita cantidadReal/remito/vale/notas.
  // -------------------------------------------------------------------------

  const modalCorregirAbierto = ref(false)
  const pedidoCorregir = ref(null)
  const formCorregir = reactive({ cantidadDespachada: null, nroRemitoGlobal: '', nroValeGlobal: '', notas: '' })
  const corrigiendo = ref(false)

  function abrirCorreccion(pedido) {
    pedidoCorregir.value = pedido
    formCorregir.cantidadDespachada = pedido.cantidad_despachada
    formCorregir.nroRemitoGlobal = pedido.nro_remito_global || ''
    formCorregir.nroValeGlobal = pedido.nro_vale_global || ''
    formCorregir.notas = ''
    error.value = null
    modalCorregirAbierto.value = true
  }

  async function guardarCorreccion() {
    if (!(Number(formCorregir.cantidadDespachada) > 0)) {
      error.value = 'La cantidad corregida debe ser mayor a 0.'
      return
    }
    corrigiendo.value = true
    error.value = null
    try {
      await corregirDespacho(pedidoCorregir.value.id, {
        cantidadDespachada: Number(formCorregir.cantidadDespachada),
        nroRemitoGlobal: formCorregir.nroRemitoGlobal.trim() || null,
        nroValeGlobal: formCorregir.nroValeGlobal.trim() || null,
        notas: formCorregir.notas.trim() || null,
      })
      modalCorregirAbierto.value = false
      await cargarDespachos()
    } catch (e) {
      error.value = e.message
    } finally {
      corrigiendo.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Modal "Ver remito" imprimible (Logica sis. plantas v1.rtf §4.5: "slip"
  // con datos del pedido + firma de responsable de planta + firma del
  // encargado). Reusa cargasDetalle si ya se abrió el detalle del mismo
  // pedido; si no, las trae.
  // -------------------------------------------------------------------------

  const modalRemitoAbierto = ref(false)
  const pedidoRemito = ref(null)
  const cargasRemito = ref([])
  const cargandoRemito = ref(false)

  async function abrirRemito(pedido) {
    pedidoRemito.value = pedido
    modalRemitoAbierto.value = true
    cargandoRemito.value = true
    error.value = null
    try {
      cargasRemito.value = await fetchCargasDelPedido(pedido.id, pedido.tipo)
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoRemito.value = false
    }
  }

  function imprimir() {
    window.print()
  }

  // -------------------------------------------------------------------------
  // Arranque
  // -------------------------------------------------------------------------

  function iniciar() {
    cargarBase().then(() => {
      cargarDespachos()
      cargarResumenPorObra()
    })
    cargarKpis()
  }

  return {
    error,
    obras,
    formulas,
    obrasPorId,
    formulasPorId,
    kpisMes,
    kpisHistorico,
    filas: filasConNombres,
    totalDespachos,
    paginaActual,
    cargando,
    filtros,
    TAMANO_PAGINA,
    aplicarFiltros,
    limpiarFiltros,
    cambiarPagina,
    cargarDespachos,
    mesResumen,
    resumenObras,
    cargandoResumen,
    cargarResumenPorObra,
    modalDetalleAbierto,
    pedidoDetalle,
    cargasDetalle,
    cargandoDetalle,
    rangoNumerosDetalle,
    abrirDetalle,
    modalCorregirAbierto,
    pedidoCorregir,
    formCorregir,
    corrigiendo,
    abrirCorreccion,
    guardarCorreccion,
    modalRemitoAbierto,
    pedidoRemito,
    cargasRemito,
    cargandoRemito,
    abrirRemito,
    imprimir,
    destinoDe,
    iniciar,
  }
}
