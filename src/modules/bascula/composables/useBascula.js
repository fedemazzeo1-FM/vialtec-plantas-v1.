// Composable de Báscula: toda la lógica de negocio y estado de la vista
// (puertas de pesaje en paralelo, historial paginado + filtros, impresión de
// vale/remito) vive acá — BasculaView.vue queda como template puro que solo
// llama a lo que este composable expone. Nada de acceso a Supabase acá
// tampoco: todo pasa por bascula.service.js (memory/conventions.md).
//
// 3 tipos de puerta (memory/relevamiento-sistema-viejo.md §2 — "3 opciones,
// no 4 como asumíamos"): asfalto (con temperatura opcional), ingreso de
// áridos (suma stock vía plantas_ingresos) y egreso de áridos (no
// suma/resta stock todavía — mismo TODO que ya existía para el descuento de
// stock, ver memory/pending.md). No existe un 4° tipo "hormigón": la báscula
// nunca pesa hormigón (memory/business-rules.md).
//
// Fidelidad con el legado (Etapa 3 del relevamiento, sesión 2026-08-28): UNA
// sola puerta se abre con "+ Abrir puerta" y el tipo se elige/cambia con un
// select DENTRO de la card (no 3 botones que fijan el tipo al crear) —
// confirmado en vivo con form_input. Al guardar un vale de asfalto, se abre
// automáticamente el modal de impresión (Logica sis. plantas v1.rtf §2.4,
// paso 5: "se imprime automáticamente").

import { computed, reactive, ref } from 'vue'
import {
  fetchPedidosAsfaltoParaPesada,
  fetchHistorialVales,
  registrarPesada,
  obtenerAcumuladoHastaFecha,
  obtenerProximoNumeroVale,
  calcularDiferencia,
} from '@/modules/bascula/services/bascula.service'
import { fetchObras } from '@/services/flota.service'
import { fetchFormulas } from '@/modules/maestros/services/formulas.service'
import { patentesService, proveedoresService } from '@/modules/maestros/services/maestros.service'

export const ETIQUETA_TIPO_VALE = {
  asfalto: 'Salida asfalto',
  hormigon: 'Hormigón',
  ingreso_arido: 'Ingreso árido',
  egreso_arido: 'Egreso árido',
}
export const VARIANTE_TIPO_VALE = {
  asfalto: 'info',
  hormigon: 'default',
  ingreso_arido: 'warning',
  egreso_arido: 'danger',
}

// Opciones del select de tipo dentro de cada puerta — mismo texto exacto que
// usa el legado ("Vale Asfalto" / "Ingreso Áridos" / "Vale Salida Áridos").
export const OPCIONES_TIPO_PUERTA = [
  { value: 'asfalto', label: 'Vale Asfalto' },
  { value: 'ingreso_arido', label: 'Ingreso Áridos' },
  { value: 'egreso_arido', label: 'Vale Salida Áridos' },
]

// Identificación visual por tipo de puerta (pedido de Federico, 2026-08-28):
// violeta = Vale Asfalto (mismo tono que la marca, #7B2F8E = token `vialtec`),
// verde = Ingreso de Áridos (token `success`), naranja = Egreso de Áridos
// (Tailwind `orange`, no tenemos un token semántico propio para esto todavía).
export const COLOR_PUERTA = {
  asfalto: { borde: 'border-l-vialtec', texto: 'text-vialtec' },
  ingreso_arido: { borde: 'border-l-success', texto: 'text-success' },
  egreso_arido: { borde: 'border-l-orange-500', texto: 'text-orange-600' },
}

const TAMANO_PAGINA_HISTORIAL = 50

export function useBascula() {
  const error = ref(null)

  // -------------------------------------------------------------------------
  // Datos base (pedidos para pesar, obras, patentes/proveedores conocidos,
  // fórmulas — estas últimas solo para resolver el nombre de mezcla al
  // imprimir un vale, ver abrirImpresion()).
  // -------------------------------------------------------------------------

  const cargandoBase = ref(false)
  const pedidosParaPesada = ref([])
  const obras = ref([])
  const patentes = ref([])
  const proveedores = ref([])
  const formulas = ref([])

  const obrasPorId = computed(() => Object.fromEntries(obras.value.map((o) => [o.id, o])))
  const pedidosPorId = computed(() => Object.fromEntries(pedidosParaPesada.value.map((p) => [p.id, p])))
  const formulasPorId = computed(() => Object.fromEntries(formulas.value.map((f) => [f.id, f])))

  async function cargarBase() {
    cargandoBase.value = true
    try {
      const [listaPedidos, listaObras, listaPatentes, listaProveedores, listaFormulas] = await Promise.all([
        fetchPedidosAsfaltoParaPesada(),
        fetchObras(),
        patentesService.fetch({ soloActivos: true }),
        proveedoresService.fetch({ soloActivos: true }),
        fetchFormulas({ soloActivas: true }),
      ])
      pedidosParaPesada.value = listaPedidos
      obras.value = listaObras
      patentes.value = listaPatentes
      proveedores.value = listaProveedores
      formulas.value = listaFormulas
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoBase.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Próximo N° de vale (header operativo — "X puertas abiertas · Próximo N°
  // 00009580", memory/relevamiento-sistema-viejo.md Etapa 3).
  // -------------------------------------------------------------------------

  const proximoNumeroVale = ref(null)

  async function cargarProximoNumero() {
    try {
      proximoNumeroVale.value = await obtenerProximoNumeroVale()
    } catch (e) {
      error.value = e.message
    }
  }

  // -------------------------------------------------------------------------
  // Puertas de pesaje en paralelo
  // -------------------------------------------------------------------------

  // Sin "puerta activa": el legado muestra todas las puertas abiertas como
  // cards apiladas simultáneamente, cada una colapsable de forma
  // independiente (memory/relevamiento-sistema-viejo.md Etapa 1 §2) — no es
  // un tab-bar de una sola visible a la vez, por eso no hay slotActivoId acá.
  let contadorSlot = 0
  const slots = ref([])

  const puertasAbiertas = computed(() => slots.value.length)

  function formularioVacio(tipo) {
    if (tipo === 'asfalto') {
      return reactive({
        pedido_id: '',
        patente: '',
        chofer: '',
        peso_bruto: null,
        tara: null,
        temperatura: null,
        observaciones: '',
      })
    }
    if (tipo === 'ingreso_arido') {
      // Sin chofer: el legado no lo pide para ingreso de áridos, solo para
      // Vale Asfalto (memory/relevamiento-sistema-viejo.md Etapa 3).
      return reactive({
        material: '',
        proveedor: '',
        numero_remito: '',
        cantidad_remito: null,
        patente: '',
        peso_bruto: null,
        tara: null,
        observaciones: '',
      })
    }
    // egreso_arido — obra_id (select), no destino de texto libre (migración 10).
    return reactive({
      material: '',
      obra_id: '',
      patente: '',
      peso_bruto: null,
      tara: null,
      observaciones: '',
    })
  }

  /** "+ Abrir puerta" único (ya no 3 botones por tipo) — arranca en Vale Asfalto, cambiable con el select interno. */
  function crearSlot(tipoInicial = 'asfalto') {
    contadorSlot += 1
    const slot = { id: contadorSlot, tipo: tipoInicial, form: formularioVacio(tipoInicial), guardando: false, colapsado: false }
    slots.value.push(slot)
  }

  /** Cambia el tipo de una puerta ya abierta y reinicia su formulario (los campos no son compatibles entre tipos). */
  function cambiarTipoSlot(slot, nuevoTipo) {
    if (slot.tipo === nuevoTipo) return
    slot.tipo = nuevoTipo
    slot.form = formularioVacio(nuevoTipo)
  }

  function toggleColapso(slot) {
    slot.colapsado = !slot.colapsado
  }

  function cerrarSlot(id) {
    const idx = slots.value.findIndex((s) => s.id === id)
    if (idx === -1) return
    slots.value.splice(idx, 1)
  }

  function netoSlot(slot) {
    const bruto = Number(slot.form.peso_bruto) || 0
    const tara = Number(slot.form.tara) || 0
    return (bruto - tara).toFixed(2)
  }

  function alCambiarPatente(slot) {
    const encontrada = patentes.value.find((p) => p.patente === slot.form.patente)
    if (encontrada) {
      if (encontrada.tara != null) slot.form.tara = encontrada.tara
      if (encontrada.chofer_habitual && 'chofer' in slot.form) slot.form.chofer = encontrada.chofer_habitual
    }
  }

  async function guardarPesada(slot) {
    const form = slot.form
    if (!(Number(form.peso_bruto) > 0) || form.tara == null || Number(form.tara) < 0) {
      error.value = 'Completá peso bruto y tara.'
      return
    }
    if (slot.tipo === 'asfalto' && !form.pedido_id) {
      error.value = 'Elegí un pedido de asfalto.'
      return
    }
    if (slot.tipo === 'ingreso_arido') {
      if (!form.material || !form.proveedor) {
        error.value = 'Completá material y proveedor del ingreso.'
        return
      }
      if (!form.numero_remito || !form.numero_remito.trim()) {
        error.value = 'El N° de remito es obligatorio en un ingreso de áridos.'
        return
      }
    }
    if (slot.tipo === 'egreso_arido') {
      if (!form.material) {
        error.value = 'Completá el material del egreso.'
        return
      }
      if (!form.obra_id) {
        error.value = 'Elegí la obra de destino del egreso.'
        return
      }
    }

    const pedido = slot.tipo === 'asfalto' ? pedidosParaPesada.value.find((p) => p.id === form.pedido_id) : null

    slot.guardando = true
    error.value = null
    try {
      const valeGuardado = await registrarPesada({
        tipo_vale: slot.tipo,
        pedido_id: slot.tipo === 'asfalto' ? form.pedido_id : null,
        obra_id: slot.tipo === 'egreso_arido' ? form.obra_id : (pedido?.obra_id ?? null),
        patente: form.patente || null,
        chofer: 'chofer' in form ? form.chofer || null : null,
        peso_bruto: form.peso_bruto,
        tara: form.tara,
        observaciones: form.observaciones || null,
        ...(slot.tipo === 'asfalto' ? { temperatura: form.temperatura || null } : {}),
        ...(slot.tipo === 'ingreso_arido'
          ? {
              material: form.material,
              proveedor: form.proveedor,
              numero_remito: form.numero_remito.trim(),
              cantidad_remito: form.cantidad_remito,
            }
          : {}),
        ...(slot.tipo === 'egreso_arido' ? { material: form.material } : {}),
      })
      // Al confirmar, la puerta se cierra (misma semántica que el sistema legado).
      cerrarSlot(slot.id)
      await Promise.all([cargarHistorial(), cargarBase(), cargarProximoNumero()])
      // "Se guarda el vale → se imprime automáticamente" — solo aplica a
      // asfalto: es el único tipo con impresión (memory/business-rules.md).
      if (slot.tipo === 'asfalto') {
        await abrirImpresionVale(valeGuardado)
      }
    } catch (e) {
      error.value = e.message
    } finally {
      slot.guardando = false
    }
  }

  // -------------------------------------------------------------------------
  // Historial de vales (paginado server-side) + diferencia peso/remito
  // -------------------------------------------------------------------------

  const historial = ref([])
  const totalHistorial = ref(0)
  const paginaHistorial = ref(1)
  const cargandoHistorial = ref(false)
  const filtros = reactive({ tipoVale: '', obraId: '', patente: '', desde: '', hasta: '' })

  const filasHistorial = computed(() =>
    historial.value.map((v) => {
      const diferencia = calcularDiferencia(v)
      return {
        ...v,
        obraNombre: v.obra_id ? obrasPorId.value[v.obra_id]?.nombre ?? `Obra #${v.obra_id}` : '—',
        pesoNetoLabel: `${v.peso_neto} ${v.unidad}`,
        fechaLabel: new Date(v.fecha_pesada).toLocaleString('es-AR'),
        diferenciaLabel: diferencia == null ? '—' : `${diferencia > 0 ? '+' : ''}${diferencia.toFixed(2)} tn`,
      }
    })
  )

  async function cargarHistorial() {
    cargandoHistorial.value = true
    error.value = null
    try {
      const resultado = await fetchHistorialVales(
        {
          tipoVale: filtros.tipoVale || undefined,
          obraId: filtros.obraId || undefined,
          patente: filtros.patente || undefined,
          desde: filtros.desde || undefined,
          hasta: filtros.hasta || undefined,
        },
        { pagina: paginaHistorial.value, tamanoPagina: TAMANO_PAGINA_HISTORIAL }
      )
      historial.value = resultado.filas
      totalHistorial.value = resultado.total
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoHistorial.value = false
    }
  }

  /** Cualquier cambio de filtro vuelve a la página 1 (si no, se puede quedar en una página que ya no existe). */
  function aplicarFiltrosHistorial() {
    paginaHistorial.value = 1
    cargarHistorial()
  }

  function limpiarFiltrosHistorial() {
    filtros.tipoVale = ''
    filtros.obraId = ''
    filtros.patente = ''
    filtros.desde = ''
    filtros.hasta = ''
    aplicarFiltrosHistorial()
  }

  function cambiarPaginaHistorial(pagina) {
    paginaHistorial.value = pagina
    cargarHistorial()
  }

  // -------------------------------------------------------------------------
  // Impresión (vale individual / remito con acumulado dinámico)
  // -------------------------------------------------------------------------
  // REGLA: no existe impresión para ingreso/egreso de áridos, solo asfalto
  // (memory/business-rules.md). El acumulado SIEMPRE se recalcula en vivo acá
  // (nunca se lee vale.acumulado_obra_tn como fuente de verdad) — mismo
  // criterio para modo "vale" y modo "remito" (Logica sis. plantas v1.rtf
  // §2.4: "Tanto el imprimible como el historial recalculan dinámicamente").

  const modalImpresionAbierto = ref(false)
  const modoImpresion = ref('vale')
  const valeParaImprimir = ref(null)
  const obraNombreParaImprimir = ref('')
  const mezclaNombreParaImprimir = ref('')
  const acumuladoParaImprimir = ref(null)
  // Sección "remito" (2026-09-01, contra foto real de un remito de VialTec —
  // ver ValeImprimible.vue): pedido completo (nro_remito_global, ubicacion,
  // cliente_externo) + rango de vales correlativos del acumulado del día.
  const pedidoParaImprimir = ref(null)
  const rangoValesParaImprimir = ref({ valeDesde: null, valeHasta: null, cantidadVales: 0 })

  async function abrirImpresion(vale, modo) {
    valeParaImprimir.value = vale
    const pedido = vale.pedido_id ? pedidosPorId.value[vale.pedido_id] : null
    pedidoParaImprimir.value = pedido
    // Destino: obra si la tiene; si no, venta externa -> cliente_externo del
    // pedido (una pesada de venta externa no trae obra_id, memory/business-rules.md).
    obraNombreParaImprimir.value = vale.obra_id
      ? obrasPorId.value[vale.obra_id]?.nombre ?? ''
      : pedido?.cliente_externo ?? ''
    mezclaNombreParaImprimir.value = pedido ? formulasPorId.value[pedido.formula_id]?.nombre ?? '' : ''
    modoImpresion.value = modo
    modalImpresionAbierto.value = true
    error.value = null
    try {
      const { acumuladoTn, valeDesde, valeHasta, cantidadVales } = await obtenerAcumuladoHastaFecha({
        pedidoId: vale.pedido_id,
        obraId: vale.obra_id,
        fechaCorte: vale.fecha_pesada,
      })
      acumuladoParaImprimir.value = acumuladoTn
      rangoValesParaImprimir.value = { valeDesde, valeHasta, cantidadVales }
    } catch (e) {
      error.value = e.message
    }
  }

  function abrirImpresionVale(vale) {
    return abrirImpresion(vale, 'vale')
  }

  function abrirImpresionRemito(vale) {
    return abrirImpresion(vale, 'remito')
  }

  function imprimir() {
    window.print()
  }

  // -------------------------------------------------------------------------
  // Arranque: base + próximo número + primera página de historial + una
  // puerta de asfalto abierta por default (mismo comportamiento del legado).
  // -------------------------------------------------------------------------

  function iniciar() {
    cargarBase()
    cargarHistorial()
    cargarProximoNumero()
    crearSlot('asfalto')
  }

  return {
    error,
    cargandoBase,
    obras,
    patentes,
    proveedores,
    pedidosParaPesada,
    proximoNumeroVale,
    puertasAbiertas,
    slots,
    crearSlot,
    cambiarTipoSlot,
    toggleColapso,
    cerrarSlot,
    netoSlot,
    alCambiarPatente,
    guardarPesada,
    filasHistorial,
    totalHistorial,
    paginaHistorial,
    cargandoHistorial,
    filtros,
    cargarHistorial,
    aplicarFiltrosHistorial,
    limpiarFiltrosHistorial,
    cambiarPaginaHistorial,
    TAMANO_PAGINA_HISTORIAL,
    modalImpresionAbierto,
    modoImpresion,
    valeParaImprimir,
    obraNombreParaImprimir,
    mezclaNombreParaImprimir,
    acumuladoParaImprimir,
    pedidoParaImprimir,
    rangoValesParaImprimir,
    abrirImpresionVale,
    abrirImpresionRemito,
    imprimir,
    iniciar,
  }
}
