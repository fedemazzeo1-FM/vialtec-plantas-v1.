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
// Catálogo de clientes de venta externa (2026-09-14, filtro "Cliente externo"
// pedido por Federico) — mismo catálogo que ya usa el <select> de Pedidos
// (migración 35), no se duplica la query.
import { clientesService } from '@/modules/maestros/services/maestros.service'
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
import {
  generarRemitoManual,
  fetchRemitosManuales,
  fetchItemsDeRemitoManual,
} from '@/modules/despachos/services/remitos-manuales.service'

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
  // Clientes de venta externa (2026-09-14): solo para el filtro "Cliente
  // externo" de abajo — a diferencia de Pedidos, acá no hace falta el
  // fallback "(no está en el catálogo)" porque es un filtro, no un campo que
  // se guarda (un cliente_externo que no está en el catálogo simplemente no
  // aparece como opción de filtro, no hay nada que perder).
  const clientes = ref([])
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
      const [listaObras, listaFormulas, listaPatentes, listaClientes] = await Promise.all([
        fetchObras(),
        fetchFormulas({ soloActivas: false }),
        patentesService.fetch(),
        clientesService.fetch(),
      ])
      obras.value = listaObras
      formulas.value = listaFormulas
      patentes.value = listaPatentes
      clientes.value = listaClientes
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
  const filtros = reactive({ tipo: '', obraId: '', formulaId: '', clienteExterno: '', desde: '', hasta: '' })

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
          clienteExterno: filtros.clienteExterno || undefined,
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
    filtros.clienteExterno = ''
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
  // Modal "Ver remito" imprimible — SOLO para Remito Manual desde acá
  // (2026-09-14, pedido de Federico: el botón "Remito" por pedido despachado
  // se removió de esta vista, esa impresión queda únicamente en Báscula
  // sobre un vale ya pesado — abrirImpresionRemito). Antes este modal
  // también servía para el remito de un despacho puntual (abrirRemito(),
  // DespachoImprimible.vue) — ver historial de git si hace falta esa
  // versión.
  // -------------------------------------------------------------------------

  const modalRemitoAbierto = ref(false)

  // Fix 2026-09-14 (pedido de Federico: el Remito Manual salía en horizontal,
  // tenía que ser vertical "para mantener la misma línea visual que el resto
  // de los remitos del sistema"). Mismo mecanismo ya usado por
  // useBascula.js#imprimir() para su propio remito: se inyecta un <style>
  // con `@page { size: A4 portrait }` justo antes de imprimir — como es la
  // última regla `@page` del documento, gana por cascada sobre el `@page
  // landscape` global de main.css — y se remueve enseguida después de
  // `window.print()` para no afectar el modal de "Imprimir vale" (asfalto,
  // sigue landscape, 2 copias lado a lado), que reusa esta misma función.
  // Se activa solo cuando el modal abierto es el del remito (de despacho o
  // manual, los dos usan RemitoImprimible.vue con la clase `modo-remito` en
  // DespachosView.vue) — el de vale no toca este ref.
  function imprimir() {
    let estiloTemporal = null
    if (modalRemitoAbierto.value) {
      estiloTemporal = document.createElement('style')
      estiloTemporal.textContent = '@page { size: A4 portrait; margin: 0; }'
      document.head.appendChild(estiloTemporal)
    }
    window.print()
    estiloTemporal?.remove()
  }

  // -------------------------------------------------------------------------
  // "Remito Manual/Blanco" (migración 36+37, 2026-09-09, pedido de
  // Federico): remito oficial sin pedido asociado — envío de materiales a
  // obra u otro movimiento interno, con N items (cantidad/descripción,
  // "+ Agregar item" — mismo patrón multi-fila que useDespachoAsfalto.js/
  // useCargaHormigon.js). N° de remito automático, misma secuencia que los
  // remitos de asfalto (RemitoImprimible.vue es el mismo componente único
  // que usa el resto del sistema, ver DespachoImprimible.vue).
  // -------------------------------------------------------------------------

  const remitosManuales = ref([])
  const cargandoRemitosManuales = ref(false)
  // Plegado por defecto (2026-09-14, pedido de Federico): la card ocupaba
  // espacio arriba de la tabla principal de Despachos aunque no se necesite
  // ver el listado a cada rato — mismo patrón de toggle que las puertas de
  // Báscula (useBascula.js#toggleColapso), acá para una sola card en vez de
  // por-slot.
  const remitosManualesColapsado = ref(true)

  function toggleRemitosManualesColapsado() {
    remitosManualesColapsado.value = !remitosManualesColapsado.value
  }

  async function cargarRemitosManuales() {
    cargandoRemitosManuales.value = true
    try {
      remitosManuales.value = await fetchRemitosManuales()
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoRemitosManuales.value = false
    }
  }

  function itemVacio() {
    return { cantidad: null, descripcion: '' }
  }

  function formRemitoManualVacio() {
    return {
      items: [itemVacio()],
      destino: '',
      patente: '',
      transportista: '',
      fecha: new Date().toISOString().slice(0, 10),
    }
  }

  const modalRemitoManualAbierto = ref(false)
  const formRemitoManual = reactive(formRemitoManualVacio())
  const generandoRemitoManual = ref(false)
  const errorRemitoManual = ref(null)

  function abrirRemitoManual() {
    Object.assign(formRemitoManual, formRemitoManualVacio())
    errorRemitoManual.value = null
    modalRemitoManualAbierto.value = true
  }

  function agregarItemRemitoManual() {
    formRemitoManual.items.push(itemVacio())
  }

  function quitarItemRemitoManual(index) {
    if (formRemitoManual.items.length <= 1) return
    formRemitoManual.items.splice(index, 1)
  }

  // Impresión: reusa el mismo modal/mecanismo que el remito de un despacho
  // (modalRemitoAbierto/imprimir()) — es el mismo documento (RemitoImprimible.vue),
  // solo cambia qué props le arma la vista (ver DespachosView.vue). Forma:
  // { remito: {...fila de plantas_remitos_manuales}, items: [{cantidad, descripcion}] }.
  const remitoManualParaImprimir = ref(null)

  // Props genéricos para RemitoImprimible.vue — mismo mapeo que useBascula.js/
  // DespachoImprimible.vue, acá armado desde plantas_remitos_manuales (sin
  // pedido/obra detrás).
  const remitoManualProps = computed(() => {
    if (!remitoManualParaImprimir.value) return null
    const { remito, items } = remitoManualParaImprimir.value
    return {
      numeroRemito: remito.numero_remito,
      fecha: remito.fecha,
      destino: remito.destino,
      items: items.map((i) => ({
        cantidad: i.cantidad != null ? String(i.cantidad) : '',
        detalle: i.descripcion,
      })),
      patente: remito.patente || '',
      transportista: remito.transportista || '',
      lugarEntrega: remito.destino || '',
    }
  })

  async function guardarRemitoManual() {
    const itemsValidos = formRemitoManual.items.filter((i) => i.descripcion.trim())
    if (!itemsValidos.length) {
      errorRemitoManual.value = 'Agregá al menos un item con descripción.'
      return
    }
    generandoRemitoManual.value = true
    errorRemitoManual.value = null
    try {
      const resultado = await generarRemitoManual({ ...formRemitoManual, items: itemsValidos })
      modalRemitoManualAbierto.value = false
      remitoManualParaImprimir.value = resultado
      modalRemitoAbierto.value = true
      await cargarRemitosManuales()
    } catch (e) {
      errorRemitoManual.value = e.message
    } finally {
      generandoRemitoManual.value = false
    }
  }

  // "Reimprimir" desde el listado: ese registro no trae los items (el
  // listado solo pide la fila de plantas_remitos_manuales, liviano) — se
  // buscan acá recién cuando hace falta imprimir de nuevo.
  async function verRemitoManual(remito) {
    error.value = null
    try {
      const items = await fetchItemsDeRemitoManual(remito.id)
      remitoManualParaImprimir.value = { remito, items }
      modalRemitoAbierto.value = true
    } catch (e) {
      error.value = e.message
    }
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
    cargarRemitosManuales()
  }

  return {
    error,
    obras,
    formulas,
    patentes,
    clientes,
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
    imprimir,
    remitosManuales,
    cargandoRemitosManuales,
    remitosManualesColapsado,
    toggleRemitosManualesColapsado,
    cargarRemitosManuales,
    modalRemitoManualAbierto,
    formRemitoManual,
    generandoRemitoManual,
    errorRemitoManual,
    abrirRemitoManual,
    agregarItemRemitoManual,
    quitarItemRemitoManual,
    guardarRemitoManual,
    remitoManualParaImprimir,
    remitoManualProps,
    verRemitoManual,
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
