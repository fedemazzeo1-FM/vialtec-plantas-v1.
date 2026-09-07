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
  fetchValesDelPedido,
  fetchValeCompleto,
  corregirDespacho,
} from '@/services/despachos.service'
import { fetchObras } from '@/services/flota.service'
import { fetchFormulas } from '@/modules/maestros/services/formulas.service'
// Reuso de Home (memory/conventions.md: no duplicar lógica compartida entre
// módulos) — 2026-09-06, pedido de Federico: las cards de producción anual
// de asfalto de Despachos tienen que mostrar exactamente lo mismo que las
// 3 cards de Home (Total año / Ammann 140 / Marini 180), mismo cálculo.
import { fetchProduccionAnualAsfalto } from '@/modules/dashboard/services/dashboard.service'
import { patentesService } from '@/modules/maestros/services/maestros.service'
// Reuso de Báscula (memory/conventions.md: no duplicar lógica compartida
// entre módulos) — el acumulado dinámico del día y el formato de N° de vale
// son exactamente los mismos que usa ValeImprimible.vue desde BasculaView.
import { obtenerAcumuladoHastaFecha, formatearNumeroVale } from '@/modules/bascula/services/bascula.service'
import { fetchDatosInformeMensual } from '@/modules/despachos/services/informe-mensual.service'

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
  // Patentes: solo para resolver Propio/Tercero en el remito/vale imprimible
  // (ValeImprimible.vue#transporteLabel, mismo criterio que Báscula) — no se
  // usa en ningún otro lado de esta vista.
  const patentes = ref([])
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
      const [listaObras, listaFormulas, listaPatentes] = await Promise.all([
        fetchObras(),
        fetchFormulas({ soloActivas: false }),
        patentesService.fetch(),
      ])
      obras.value = listaObras
      formulas.value = listaFormulas
      patentes.value = listaPatentes
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
  // Producción anual de asfalto por planta — mismas 3 cards que Home
  // (Total año 2026 / Ammann 140 / Marini 180), ver dashboard.service.js.
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
  // "Exportar informe mensual" (2026-09-02, pedido de Federico — botón
  // EXPORTAR INFORME MENSUAL en Resumen por obra): arma el .xlsx completo
  // (Resumen mensual + Resumen anual + una hoja por obra/cliente) para el
  // mismo `mesResumen` que ya está seleccionado en esta sección — el
  // informe sigue al selector de mes que ya existía, no uno nuevo.
  // Import dinámico de exceljs (misma razón que xlsx en Báscula/Stock: no
  // inflar el chunk de Despachos con una librería pesada que no todos usan).
  // -------------------------------------------------------------------------

  const exportandoInforme = ref(false)

  async function exportarInformeMensual() {
    exportandoInforme.value = true
    error.value = null
    try {
      const [datos, { generarInformeMensualExcel }] = await Promise.all([
        fetchDatosInformeMensual(mesResumen.value),
        import('@/modules/despachos/services/excel-informe-mensual'),
      ])
      await generarInformeMensualExcel(datos)
    } catch (e) {
      error.value = e.message
    } finally {
      exportandoInforme.value = false
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
  // "Imprimir vale" (2026-09-02, roadmap Mobile/UX — selector Vale/Remito
  // pedido por Federico para las salidas de asfalto): Despachos ya tenía
  // "Ver remito" (arriba); esto agrega la otra opción, reusando
  // ValeImprimible.vue tal cual lo arma useBascula.js (mismo componente,
  // mismas props — memory/conventions.md, no duplicar el imprimible). Un
  // despacho puede tener 0 vales asociados (hormigón, o asfalto sin pesar en
  // báscula), 1 (caso típico) o varios (multi-camión) — con más de uno se
  // pide elegir cuál antes de abrir el modal de impresión.
  // -------------------------------------------------------------------------

  const modalSeleccionValeAbierto = ref(false)
  const pedidoParaSeleccionVale = ref(null)
  const valesDisponibles = ref([])

  const modalImpresionValeAbierto = ref(false)
  const valeParaImprimir = ref(null)
  const pedidoParaImprimirVale = ref(null)
  const acumuladoParaImprimirVale = ref(null)
  const rangoValesParaImprimirVale = ref({ valeDesde: null, valeHasta: null, cantidadVales: 0 })

  async function abrirVale(valeId, pedido) {
    error.value = null
    try {
      const vale = await fetchValeCompleto(valeId)
      valeParaImprimir.value = vale
      pedidoParaImprimirVale.value = pedido
      modalImpresionValeAbierto.value = true
      const { acumuladoTn, valeDesde, valeHasta, cantidadVales } = await obtenerAcumuladoHastaFecha({
        pedidoId: pedido.id,
        obraId: pedido.obra_id,
        fechaCorte: vale.fecha_pesada,
      })
      acumuladoParaImprimirVale.value = acumuladoTn
      rangoValesParaImprimirVale.value = { valeDesde, valeHasta, cantidadVales }
    } catch (e) {
      error.value = e.message
    }
  }

  async function abrirImpresionVale(pedido) {
    error.value = null
    try {
      const vales = await fetchValesDelPedido(pedido.id)
      if (!vales.length) {
        error.value = 'Este despacho no tiene vales de báscula asociados para imprimir.'
        return
      }
      if (vales.length === 1) {
        await abrirVale(vales[0].id, pedido)
      } else {
        pedidoParaSeleccionVale.value = pedido
        valesDisponibles.value = vales
        modalSeleccionValeAbierto.value = true
      }
    } catch (e) {
      error.value = e.message
    }
  }

  async function elegirVale(valeId) {
    modalSeleccionValeAbierto.value = false
    await abrirVale(valeId, pedidoParaSeleccionVale.value)
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
    cargarProduccionAnual()
  }

  return {
    error,
    obras,
    formulas,
    patentes,
    obrasPorId,
    formulasPorId,
    kpisMes,
    kpisHistorico,
    cargandoProduccionAnual,
    produccionAnual,
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
    exportandoInforme,
    exportarInformeMensual,
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
    modalSeleccionValeAbierto,
    pedidoParaSeleccionVale,
    valesDisponibles,
    modalImpresionValeAbierto,
    valeParaImprimir,
    pedidoParaImprimirVale,
    acumuladoParaImprimirVale,
    rangoValesParaImprimirVale,
    abrirImpresionVale,
    elegirVale,
    formatearNumeroVale,
    destinoDe,
    iniciar,
  }
}
