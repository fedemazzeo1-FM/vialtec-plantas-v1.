// Composable de Pedidos: listado paginado + filtros, datos base (obras,
// fórmulas, patentes, choferes), transiciones de estado (crear/confirmar/
// postergar/cancelar/archivar/editar), historial y toasts de WhatsApp. El
// despacho multi-carga (asfalto y hormigón) vive en composables aparte —
// useDespachoAsfalto/useCargaHormigon— porque cada uno tiene su propio modal
// y su propio ciclo de guardado. PedidosView.vue queda como template puro
// (memory/conventions.md).

import { computed, reactive, ref } from 'vue'
import {
  fetchPedidos,
  fetchConteoEstados,
  crearPedido as crearPedidoService,
  actualizarPedido as actualizarPedidoDirecto,
  confirmarPedido as confirmarPedidoService,
  postergarPedido as postergarPedidoService,
  cancelarPedido as cancelarPedidoService,
  archivarPedido as archivarPedidoService,
  fetchHistorialPedido,
} from '@/modules/pedidos/services/pedidos.service'
import { fetchObras } from '@/services/flota.service'
import { fetchFormulas } from '@/modules/maestros/services/formulas.service'
import { patentesService, choferesService } from '@/modules/maestros/services/maestros.service'
import { useAuthStore } from '@/stores/auth.store'
import { toastCrearPedido, toastConfirmarPedido, toastConfirmarHormigonOperador } from '@/modules/pedidos/whatsapp'

const TAMANO_PAGINA = 50

function formularioPedidoVacio() {
  return {
    tipo_pedido: 'obra',
    obra_id: '',
    cliente_externo: '',
    encargado: '',
    formula_id: '',
    tipo: '',
    cantidad_solicitada: null,
    fecha_programada: '',
    ubicacion: '',
    observaciones: '',
  }
}

export function usePedidos() {
  const error = ref(null)
  const auth = useAuthStore()

  // -------------------------------------------------------------------------
  // Datos base
  // -------------------------------------------------------------------------

  const obras = ref([])
  const formulas = ref([])
  const patentes = ref([])
  const choferes = ref([])

  const obrasPorId = computed(() => Object.fromEntries(obras.value.map((o) => [o.id, o])))
  const formulasPorId = computed(() => Object.fromEntries(formulas.value.map((f) => [f.id, f])))

  function obraNombreDe(pedido) {
    return pedido?.obra_id ? obrasPorId.value[pedido.obra_id]?.nombre ?? `Obra #${pedido.obra_id}` : ''
  }

  async function cargarBase() {
    const [listaObras, listaFormulas, listaPatentes, listaChoferes] = await Promise.all([
      fetchObras(),
      fetchFormulas({ soloActivas: true }),
      patentesService.fetch({ soloActivos: true }),
      choferesService.fetch({ soloActivos: true }),
    ])
    obras.value = listaObras
    formulas.value = listaFormulas
    patentes.value = listaPatentes
    choferes.value = listaChoferes
  }

  // -------------------------------------------------------------------------
  // Toasts de WhatsApp (memory/relevamiento: WppToast — nunca se envía por
  // API, solo se sugiere el mensaje + link a wa.me). Varios pueden convivir
  // (ej. al confirmar un pedido de hormigón salen 2: encargado + operador).
  // -------------------------------------------------------------------------

  const whatsappToasts = ref([])
  let contadorToast = 0

  function mostrarToastWhatsapp(toast) {
    contadorToast += 1
    whatsappToasts.value.push({ id: contadorToast, ...toast })
  }

  function descartarToastWhatsapp(id) {
    whatsappToasts.value = whatsappToasts.value.filter((t) => t.id !== id)
  }

  // -------------------------------------------------------------------------
  // Listado + filtros + paginación
  // -------------------------------------------------------------------------

  const pedidos = ref([])
  const totalPedidos = ref(0)
  const paginaActual = ref(1)
  const cargando = ref(false)
  const filtros = reactive({ estado: '', obraId: '', tipo: '', desde: '', hasta: '', incluirArchivados: false })

  // KPI de conteo por estado (memory/relevamiento-sistema-viejo.md §1) — no
  // depende de los filtros ni de la paginación, son los totales activos de
  // todo el sistema. Se refresca en cada cargarPedidos() (no bloqueante:
  // no hace falta esperarlo para pintar la tabla).
  const conteoEstados = ref({ solicitado: 0, confirmado: 0, despachado: 0, postergado: 0, cancelado: 0 })

  async function cargarConteoEstados() {
    try {
      conteoEstados.value = await fetchConteoEstados()
    } catch (e) {
      error.value = e.message
    }
  }

  /** obra o cliente externo, ya resuelto por nombre — regla del tipo_pedido. */
  const filas = computed(() =>
    pedidos.value.map((p) => ({
      ...p,
      destino: p.tipo_pedido === 'venta' ? p.cliente_externo || '—' : obraNombreDe(p) || '—',
      formulaNombre: formulasPorId.value[p.formula_id]?.nombre ?? '—',
    }))
  )

  async function cargarPedidos() {
    cargando.value = true
    error.value = null
    try {
      const resultado = await fetchPedidos(
        {
          estado: filtros.estado || undefined,
          obraId: filtros.obraId || undefined,
          tipo: filtros.tipo || undefined,
          desde: filtros.desde || undefined,
          hasta: filtros.hasta || undefined,
          incluirArchivados: filtros.incluirArchivados,
        },
        { pagina: paginaActual.value, tamanoPagina: TAMANO_PAGINA }
      )
      pedidos.value = resultado.filas
      totalPedidos.value = resultado.total
    } catch (e) {
      error.value = e.message
    } finally {
      cargando.value = false
    }
    cargarConteoEstados()
  }

  /** Cualquier cambio de filtro vuelve a la página 1 (si no, se puede quedar en una página que ya no existe). */
  function aplicarFiltros() {
    paginaActual.value = 1
    cargarPedidos()
  }

  function limpiarFiltros() {
    filtros.estado = ''
    filtros.obraId = ''
    filtros.tipo = ''
    filtros.desde = ''
    filtros.hasta = ''
    filtros.incluirArchivados = false
    aplicarFiltros()
  }

  function cambiarPagina(pagina) {
    paginaActual.value = pagina
    cargarPedidos()
  }

  // -------------------------------------------------------------------------
  // Alta de pedido
  // -------------------------------------------------------------------------

  const modalNuevoAbierto = ref(false)
  const guardandoNuevo = ref(false)
  const formNuevo = reactive(formularioPedidoVacio())

  function abrirNuevo() {
    Object.assign(formNuevo, formularioPedidoVacio())
    modalNuevoAbierto.value = true
  }

  function alSeleccionarFormula() {
    formNuevo.tipo = formulasPorId.value[formNuevo.formula_id]?.tipo ?? ''
  }

  function validarFormPedido(form) {
    if (form.tipo_pedido === 'venta' && !form.cliente_externo.trim()) return 'Completá el cliente externo.'
    if (form.tipo_pedido === 'obra' && !form.obra_id) return 'Completá la obra.'
    if (!form.formula_id || !form.cantidad_solicitada || !form.fecha_programada) return 'Completá fórmula, cantidad y fecha.'
    return null
  }

  async function guardarNuevo() {
    const mensajeError = validarFormPedido(formNuevo)
    if (mensajeError) {
      error.value = mensajeError
      return
    }

    guardandoNuevo.value = true
    error.value = null
    try {
      const pedidoCreado = await crearPedidoService(
        {
          tipo_pedido: formNuevo.tipo_pedido,
          obra_id: formNuevo.tipo_pedido === 'obra' ? formNuevo.obra_id : null,
          cliente_externo: formNuevo.tipo_pedido === 'venta' ? formNuevo.cliente_externo.trim() : null,
          encargado: formNuevo.encargado.trim() || null,
          formula_id: formNuevo.formula_id,
          tipo: formNuevo.tipo,
          cantidad_solicitada: formNuevo.cantidad_solicitada,
          fecha_programada: formNuevo.fecha_programada,
          ubicacion: formNuevo.ubicacion.trim() || null,
          observaciones: formNuevo.observaciones || null,
        },
        { usuarioLegado: auth.nombre }
      )
      modalNuevoAbierto.value = false
      mostrarToastWhatsapp(toastCrearPedido(pedidoCreado, { obraNombre: obraNombreDe(pedidoCreado) }))
      aplicarFiltros()
    } catch (e) {
      error.value = e.message
    } finally {
      guardandoNuevo.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Edición de pedido (campos generales — no cambia estado)
  // -------------------------------------------------------------------------

  const modalEditarAbierto = ref(false)
  const guardandoEditar = ref(false)
  const pedidoEditando = ref(null)
  const formEditar = reactive(formularioPedidoVacio())

  function abrirEdicion(pedido) {
    pedidoEditando.value = pedido
    Object.assign(formEditar, {
      tipo_pedido: pedido.tipo_pedido,
      obra_id: pedido.obra_id || '',
      cliente_externo: pedido.cliente_externo || '',
      encargado: pedido.encargado || '',
      formula_id: pedido.formula_id,
      tipo: pedido.tipo,
      cantidad_solicitada: pedido.cantidad_solicitada,
      fecha_programada: pedido.fecha_programada,
      ubicacion: pedido.ubicacion || '',
      observaciones: pedido.observaciones || '',
    })
    error.value = null
    modalEditarAbierto.value = true
  }

  function alSeleccionarFormulaEditar() {
    formEditar.tipo = formulasPorId.value[formEditar.formula_id]?.tipo ?? ''
  }

  async function guardarEdicion() {
    const mensajeError = validarFormPedido(formEditar)
    if (mensajeError) {
      error.value = mensajeError
      return
    }

    guardandoEditar.value = true
    error.value = null
    try {
      await actualizarPedidoDirecto(pedidoEditando.value.id, {
        tipo_pedido: formEditar.tipo_pedido,
        obra_id: formEditar.tipo_pedido === 'obra' ? formEditar.obra_id : null,
        cliente_externo: formEditar.tipo_pedido === 'venta' ? formEditar.cliente_externo.trim() : null,
        encargado: formEditar.encargado.trim() || null,
        formula_id: formEditar.formula_id,
        tipo: formEditar.tipo,
        cantidad_solicitada: formEditar.cantidad_solicitada,
        fecha_programada: formEditar.fecha_programada,
        ubicacion: formEditar.ubicacion.trim() || null,
        observaciones: formEditar.observaciones || null,
      })
      modalEditarAbierto.value = false
      await cargarPedidos()
    } catch (e) {
      error.value = e.message
    } finally {
      guardandoEditar.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Confirmar / postergar / cancelar / archivar
  // -------------------------------------------------------------------------

  async function confirmar(pedido) {
    error.value = null
    try {
      await confirmarPedidoService(pedido.id, { usuarioLegado: auth.nombre })
      mostrarToastWhatsapp(toastConfirmarPedido(pedido, { obraNombre: obraNombreDe(pedido) }))
      if (pedido.tipo === 'hormigon') {
        mostrarToastWhatsapp(toastConfirmarHormigonOperador(pedido, { obraNombre: obraNombreDe(pedido) }))
      }
      await cargarPedidos()
    } catch (e) {
      error.value = e.message
    }
  }

  const modalPostergarAbierto = ref(false)
  const pedidoPostergar = ref(null)
  const fechaNuevaPostergar = ref('')
  const motivoPostergar = ref('')
  const postergando = ref(false)

  function abrirPostergacion(pedido) {
    pedidoPostergar.value = pedido
    fechaNuevaPostergar.value = pedido.fecha_programada || ''
    motivoPostergar.value = ''
    error.value = null
    modalPostergarAbierto.value = true
  }

  async function confirmarPostergacion() {
    postergando.value = true
    error.value = null
    try {
      await postergarPedidoService(pedidoPostergar.value.id, {
        fechaNueva: fechaNuevaPostergar.value || null,
        motivo: motivoPostergar.value || null,
      })
      modalPostergarAbierto.value = false
      await cargarPedidos()
    } catch (e) {
      error.value = e.message
    } finally {
      postergando.value = false
    }
  }

  const modalCancelAbierto = ref(false)
  const pedidoCancelar = ref(null)
  const motivoCancelacion = ref('')
  const cancelando = ref(false)

  function abrirCancelacion(pedido) {
    pedidoCancelar.value = pedido
    motivoCancelacion.value = ''
    modalCancelAbierto.value = true
  }

  async function confirmarCancelacion() {
    cancelando.value = true
    error.value = null
    try {
      await cancelarPedidoService(pedidoCancelar.value.id, motivoCancelacion.value, { usuarioLegado: auth.nombre })
      modalCancelAbierto.value = false
      await cargarPedidos()
    } catch (e) {
      error.value = e.message
    } finally {
      cancelando.value = false
    }
  }

  async function archivar(pedido) {
    error.value = null
    try {
      await archivarPedidoService(pedido.id)
      await cargarPedidos()
    } catch (e) {
      error.value = e.message
    }
  }

  // -------------------------------------------------------------------------
  // Historial del pedido (modal "Ver historial" — timeline, append-only)
  // -------------------------------------------------------------------------

  const modalHistorialAbierto = ref(false)
  const pedidoHistorial = ref(null)
  const eventosHistorial = ref([])
  const cargandoHistorial = ref(false)

  async function abrirHistorial(pedido) {
    pedidoHistorial.value = pedido
    modalHistorialAbierto.value = true
    cargandoHistorial.value = true
    error.value = null
    try {
      eventosHistorial.value = await fetchHistorialPedido(pedido.id)
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoHistorial.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Arranque
  // -------------------------------------------------------------------------

  function iniciar() {
    cargarBase().then(cargarPedidos)
  }

  return {
    error,
    obras,
    formulas,
    patentes,
    choferes,
    obrasPorId,
    formulasPorId,
    obraNombreDe,
    pedidos,
    filas,
    totalPedidos,
    paginaActual,
    cargando,
    filtros,
    conteoEstados,
    TAMANO_PAGINA,
    cargarPedidos,
    aplicarFiltros,
    limpiarFiltros,
    cambiarPagina,
    whatsappToasts,
    descartarToastWhatsapp,
    modalNuevoAbierto,
    guardandoNuevo,
    formNuevo,
    abrirNuevo,
    alSeleccionarFormula,
    guardarNuevo,
    modalEditarAbierto,
    guardandoEditar,
    formEditar,
    abrirEdicion,
    alSeleccionarFormulaEditar,
    guardarEdicion,
    confirmar,
    modalPostergarAbierto,
    pedidoPostergar,
    fechaNuevaPostergar,
    motivoPostergar,
    postergando,
    abrirPostergacion,
    confirmarPostergacion,
    modalCancelAbierto,
    pedidoCancelar,
    motivoCancelacion,
    cancelando,
    abrirCancelacion,
    confirmarCancelacion,
    archivar,
    modalHistorialAbierto,
    pedidoHistorial,
    eventosHistorial,
    cargandoHistorial,
    abrirHistorial,
    iniciar,
  }
}
