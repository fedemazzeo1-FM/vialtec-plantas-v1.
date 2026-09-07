// Composable de Pedidos: listado paginado + filtros, datos base (obras,
// fórmulas, patentes, choferes), transiciones de estado (crear/confirmar/
// postergar/cancelar/archivar/editar), historial y toasts de WhatsApp. El
// despacho multi-carga (asfalto y hormigón) vive en composables aparte —
// useDespachoAsfalto/useCargaHormigon— porque cada uno tiene su propio modal
// y su propio ciclo de guardado. PedidosView.vue queda como template puro
// (memory/conventions.md).

import { computed, reactive, ref } from 'vue'
import {
  fetchTodosLosPedidos,
  fetchResumenPeriodo,
  crearPedido as crearPedidoService,
  actualizarPedido as actualizarPedidoDirecto,
  confirmarPedido as confirmarPedidoService,
  postergarPedido as postergarPedidoService,
  cancelarPedido as cancelarPedidoService,
  archivarPedido as archivarPedidoService,
  fetchHistorialPedido,
  obtenerRangoSemana,
} from '@/modules/pedidos/services/pedidos.service'
import { fetchObras, fetchTelefonoPorNombre } from '@/services/flota.service'
import { fetchFormulas } from '@/modules/maestros/services/formulas.service'
import { patentesService, choferesService } from '@/modules/maestros/services/maestros.service'
import { useAuthStore } from '@/stores/auth.store'
import { toastCrearPedido, toastConfirmarPedido, toastConfirmarHormigonOperador } from '@/modules/pedidos/whatsapp'

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
    // Fix 2026-09-01: sin try/catch acá, un fallo de red dejaba
    // `iniciar()` (`cargarBase().then(cargarPedidos)`) como una promesa
    // rechazada sin `.catch()` — error no manejado en consola,
    // `cargarPedidos()` nunca se llamaba, y la vista quedaba mostrando "No
    // hay pedidos que coincidan con el filtro" (falso estado vacío) en vez
    // del error real. Mismo patrón que ya usan cargarBase() en
    // useBascula.js/useSimulador.js.
    try {
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
    } catch (e) {
      error.value = e.message
    }
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
  const cargando = ref(false)
  const filtros = reactive({ estado: '', obraId: '', desde: '', hasta: '', incluirArchivados: false })

  // -------------------------------------------------------------------------
  // Vista por semana (2026-09-01, pedido de Federico): con 184 pedidos
  // históricos migrados, la lista sin acotar por fecha quedaba saturada.
  // Default: semana en curso (mismo cálculo que Plan Semanal,
  // obtenerRangoSemana() ya existía ahí — reutilizado, no duplicado). El
  // usuario puede pasar a "histórico completo" (saca el filtro de fecha,
  // deja el resto de los filtros como están) — la navegación semana por
  // semana (anterior/siguiente) se sacó el 2026-09-02 por simplificación de
  // UX (roadmap Mobile, pedido de Federico). Nota de relevamiento en vivo
  // del sistema legado (2026-09-01): la
  // pantalla de Pedidos del legado NO filtra por semana — muestra todo lo
  // activo (no despachado/cancelado) agrupado por material, sin filtro de
  // fecha, porque una vez despachado/archivado prácticamente desaparece de
  // ahí (el historial completo vive en "Despachos", no en "Pedidos"). Acá se
  // eligió semana-por-defecto en vez de replicar ese comportamiento porque
  // nuestro Pedidos sí lista todos los estados juntos (incluido despachado
  // reciente) — el problema real (184 filas de golpe) es el mismo, la
  // solución adaptada a nuestro diseño.
  const vistaSemana = ref(true)
  const semanaRef = ref(new Date())

  const rangoSemanaLabel = computed(() => {
    const { lunes, domingo } = obtenerRangoSemana(semanaRef.value)
    const aISO = (d) => d.toISOString().slice(0, 10)
    return `${aISO(lunes)} — ${aISO(domingo)}`
  })

  function aplicarRangoSemana() {
    const { lunes, domingo } = obtenerRangoSemana(semanaRef.value)
    filtros.desde = lunes.toISOString().slice(0, 10)
    filtros.hasta = domingo.toISOString().slice(0, 10)
    vistaSemana.value = true
    aplicarFiltros()
  }

  // Nota 2026-09-02 (roadmap Mobile/UX, "simplificación de navegación"): se
  // sacaron semanaAnterior()/semanaSiguiente() — la vista ya no ofrece
  // navegar semana por semana, solo semana en curso vs. histórico completo
  // (irASemanaActual() vuelve a la semana en curso desde el histórico).
  function irASemanaActual() {
    semanaRef.value = new Date()
    aplicarRangoSemana()
  }

  /** "Ver histórico completo": saca el acotado por semana, deja el resto de filtros (estado/obra/tipo) intactos. */
  function verHistoricoCompleto() {
    vistaSemana.value = false
    filtros.desde = ''
    filtros.hasta = ''
    aplicarFiltros()
  }

  // KPI de conteo por estado + totales de tn/m³ (memory/relevamiento-
  // sistema-viejo.md §1) — fix 2026-09-01 (pedido de Federico): antes era
  // SIEMPRE global (todo el histórico no archivado, fetchConteoEstados()),
  // ahora acota al mismo período que la lista de abajo (semana en curso por
  // default, o el rango elegido en "histórico completo"/filtros). No
  // depende del tab Asfalto/Hormigón a propósito — muestra el desglose
  // completo de ambos materiales siempre, el tab solo cambia qué lista se
  // ve debajo. Se refresca en cada cargarPedidos() (no bloqueante).
  const conteoEstados = ref({ solicitado: 0, confirmado: 0, despachado: 0, postergado: 0, cancelado: 0 })
  const totalesPeriodo = ref({ asfaltoTn: 0, hormigonM3: 0 })

  async function cargarResumenPeriodo() {
    try {
      const resumen = await fetchResumenPeriodo({
        desde: filtros.desde || undefined,
        hasta: filtros.hasta || undefined,
        obraId: filtros.obraId || undefined,
        incluirArchivados: filtros.incluirArchivados,
      })
      conteoEstados.value = resumen.conteoEstados
      totalesPeriodo.value = { asfaltoTn: resumen.asfaltoTn, hormigonM3: resumen.hormigonM3 }
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

  // Agrupado por tipo con contador (2026-09-04, rediseño en cards — replica
  // exacta del legado, memory/pending.md: "Hormigón"/"Asfalto" como títulos
  // de sección, cada uno con "X pedidos"). Orden fijo Hormigón primero,
  // Asfalto después — mismo orden confirmado en vivo contra produccion.vialtec.app.
  // Ya no hay tab que filtre a un solo tipo: las dos secciones conviven
  // siempre, mismos `filtros`/`vistaSemana` de arriba para las dos.
  const pedidosPorTipo = computed(() => [
    { tipo: 'hormigon', label: 'Hormigón', filas: filas.value.filter((p) => p.tipo === 'hormigon') },
    { tipo: 'asfalto', label: 'Asfalto', filas: filas.value.filter((p) => p.tipo === 'asfalto') },
  ])

  async function cargarPedidos() {
    cargando.value = true
    error.value = null
    try {
      // fetchTodosLosPedidos() (fix 2026-09-04, rediseño en cards): antes
      // paginaba server-side por tab de tipo — al
      // unificar en una sola vista agrupada por sección no hay "página" que
      // mostrar, el legado tampoco pagina Pedidos (se apoya en el filtro de
      // semana/estado para acotar el volumen). Sigue respetando la regla de
      // paginación (memory/architecture.md): fetchPaginado() por debajo, no
      // un .select() sin límite.
      pedidos.value = await fetchTodosLosPedidos({
        estado: filtros.estado || undefined,
        obraId: filtros.obraId || undefined,
        desde: filtros.desde || undefined,
        hasta: filtros.hasta || undefined,
        incluirArchivados: filtros.incluirArchivados,
      })
    } catch (e) {
      error.value = e.message
    } finally {
      cargando.value = false
    }
    cargarResumenPeriodo()
  }

  function aplicarFiltros() {
    cargarPedidos()
  }

  function limpiarFiltros() {
    filtros.estado = ''
    filtros.obraId = ''
    filtros.desde = ''
    filtros.hasta = ''
    filtros.incluirArchivados = false
    vistaSemana.value = false // "Limpiar" saca también el acotado por semana, no solo estado/obra
    aplicarFiltros()
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
      // Teléfono del encargado (2026-09-07): match exacto por nombre contra
      // flota_usuarios_email — best-effort, un error acá (o simplemente no
      // tener ese usuario cargado en flota) no debe romper la confirmación
      // del pedido, el toast simplemente cae a wa.me sin destinatario.
      let telefonoEncargado = null
      try {
        telefonoEncargado = await fetchTelefonoPorNombre(pedido.encargado)
      } catch (e) {
        telefonoEncargado = null
      }
      mostrarToastWhatsapp(toastConfirmarPedido(pedido, { obraNombre: obraNombreDe(pedido), telefono: telefonoEncargado }))
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
  // Error propio del modal (no el `error` genérico de arriba, que renderiza
  // en un banner al tope de la vista — con el modal abierto queda tapado y
  // el usuario no lo ve, memory/pending.md hallazgo 2026-09-06).
  const errorCancelacion = ref(null)

  function abrirCancelacion(pedido) {
    pedidoCancelar.value = pedido
    motivoCancelacion.value = ''
    errorCancelacion.value = null
    modalCancelAbierto.value = true
  }

  async function confirmarCancelacion() {
    cancelando.value = true
    errorCancelacion.value = null
    try {
      await cancelarPedidoService(pedidoCancelar.value.id, motivoCancelacion.value, { usuarioLegado: auth.nombre })
      modalCancelAbierto.value = false
      await cargarPedidos()
    } catch (e) {
      errorCancelacion.value = e.message
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
    // Arranca en la semana en curso (aplicarRangoSemana ya llama a
    // aplicarFiltros -> cargarPedidos), no en cargarPedidos() a secas.
    cargarBase().then(aplicarRangoSemana)
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
    pedidosPorTipo,
    cargando,
    filtros,
    conteoEstados,
    totalesPeriodo,
    cargarPedidos,
    aplicarFiltros,
    limpiarFiltros,
    vistaSemana,
    rangoSemanaLabel,
    irASemanaActual,
    verHistoricoCompleto,
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
    errorCancelacion,
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
