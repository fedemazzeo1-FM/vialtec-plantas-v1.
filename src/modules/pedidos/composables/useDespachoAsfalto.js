// Composable del modal "Registrar despacho" de asfalto: multi-camión con
// vale por carga (memory/relevamiento-sistema-viejo.md §1 — el sistema
// legado soporta N cargas con N° de vale obligatorio por carga). Cada carga
// se persiste con una llamada independiente a registrarCargaAsfalto (RPC
// atómica con lock de fila) — ver pedidos.service.js. El N° de remito del
// despacho ya NO se tipea (ni se genera) acá: desde la migración 39
// (2026-09-16, pedido de Federico) se origina en BÁSCULA cuando el
// balancero procesa la primera pesada del pedido — el plantista ya lo
// recibe impreso en papel al momento de concretar el despacho acá.
//
// Cierre del pedido (Logica sis. plantas v1.rtf §2.2, migración 11): al
// terminar de cargar, SIEMPRE se llama a finalizarDespacho() — el pedido
// pasa a despachado con lo cargado hasta ese momento, sea parcial o
// completo. Si queda saldo, se puede activar "dividir pedido" para generar
// automáticamente un pedido residual confirmado en una fecha a elegir.
//
// Cargas desde balanza (2026-10-28, migración 73, pedido de Federico tras
// P-0264/P-0273 cargados con el peso bruto): al abrir, las cargas salen de
// los vales de balanza del pedido (N° de vale, neto, patente) y no se
// editan. "Carga sin vale de balanza" queda para cuando no se pesó: se
// tipea, pide motivo y la base la audita con ese motivo.

import { computed, reactive, ref } from 'vue'
import { registrarCargaAsfalto, finalizarDespacho, fetchValesAsfaltoDelPedido } from '@/modules/pedidos/services/pedidos.service'
import { useAvisoPisoStock, inicioVentanaRecortes } from '@/modules/stock/composables/useAvisoPisoStock'

function cargaDesdeVale(vale) {
  return reactive({ cantidad_tn: Number(vale.peso_neto), numero_vale: String(vale.numero_vale), patente: vale.patente || '', desdeBalanza: true, motivo: '' })
}

function cargaSinBalanza() {
  return reactive({ cantidad_tn: null, numero_vale: '', patente: '', desdeBalanza: false, motivo: '' })
}

/**
 * @param {() => Promise<void>|void} onGuardado callback tras cerrar el
 *   despacho con éxito (típicamente refrescar el listado de pedidos).
 */
export function useDespachoAsfalto(onGuardado) {
  const { revisarRecortesPorPiso } = useAvisoPisoStock()
  const error = ref(null)
  const abierto = ref(false)
  const pedido = ref(null)
  const cargas = ref([])
  const dividirPedido = ref(false)
  const fechaResidual = ref('')
  const guardando = ref(false)
  const cargandoVales = ref(false)
  // Pesaje todavía abierto en Báscula: puede faltar pesar algún camión.
  const pesajeAbierto = computed(() => Boolean(pedido.value) && !pedido.value.pesaje_cerrado_en)
  const sinValesEnBalanza = computed(() => !cargandoVales.value && !cargas.value.some((c) => c.desdeBalanza))

  const saldoPendiente = computed(() => {
    if (!pedido.value) return 0
    return Number(pedido.value.cantidad_solicitada) - Number(pedido.value.cantidad_despachada || 0)
  })

  const totalCargas = computed(() => cargas.value.reduce((acum, c) => acum + (Number(c.cantidad_tn) || 0), 0))

  /** Lo que va a quedar pendiente después de guardar estas cargas — solo tiene sentido si es > 0. */
  const residualEstimado = computed(() => Math.max(0, saldoPendiente.value - totalCargas.value))

  async function abrir(pedidoAsfalto) {
    pedido.value = pedidoAsfalto
    cargas.value = []
    dividirPedido.value = false
    fechaResidual.value = ''
    error.value = null
    abierto.value = true
    cargandoVales.value = true
    try {
      const vales = await fetchValesAsfaltoDelPedido(pedidoAsfalto.id)
      cargas.value = vales.map(cargaDesdeVale)
    } catch (e) {
      error.value = `No se pudieron leer los vales de balanza: ${e.message}`
    } finally {
      cargandoVales.value = false
    }
  }

  function agregarCargaSinBalanza() {
    cargas.value.push(cargaSinBalanza())
  }

  function quitarCarga(index) {
    cargas.value.splice(index, 1)
  }

  async function guardar() {
    if (!cargas.value.length) {
      error.value = 'No hay cargas: el pedido no tiene vales de balanza. Si no se pesó, usá "Carga sin vale de balanza".'
      return
    }
    for (const carga of cargas.value) {
      if (!carga.desdeBalanza && !carga.motivo.trim()) {
        error.value = 'Cada carga sin vale de balanza necesita un motivo.'
        return
      }
      if (!(Number(carga.cantidad_tn) > 0)) {
        error.value = 'Cada carga necesita una cantidad mayor a 0.'
        return
      }
      if (!carga.numero_vale.trim()) {
        error.value = 'El N° de vale es obligatorio en cada carga.'
        return
      }
    }
    if (dividirPedido.value && residualEstimado.value > 0 && !fechaResidual.value) {
      error.value = 'Elegí una fecha para el pedido residual.'
      return
    }

    guardando.value = true
    error.value = null
    try {
      // Secuencial (no Promise.all): cada carga depende del lock de fila del
      // pedido en la RPC — encolarlas evita pisarse entre sí innecesariamente
      // y deja el error de una carga puntual claro (cuál falló, no cuál de N
      // en simultáneo).
      for (const carga of cargas.value) {
        await registrarCargaAsfalto({
          pedido_id: pedido.value.id,
          numero_vale: carga.numero_vale.trim(),
          cantidad_tn: carga.cantidad_tn,
          patente: carga.patente || null,
          // Sin vale de balanza: la base exige el motivo y lo audita.
          observaciones: carga.desdeBalanza ? null : carga.motivo.trim(),
        })
      }
      // Cierra el pedido con lo cargado (parcial o completo) y, si se pidió,
      // genera el residual — ver migración 11.
      const desde = inicioVentanaRecortes()
      await finalizarDespacho(pedido.value.id, {
        dividir: dividirPedido.value,
        fechaResidual: fechaResidual.value || undefined,
      })
      // Aviso si el piso en 0 recortó algún descuento (no espera ni bloquea).
      revisarRecortesPorPiso(pedido.value, desde)
      abierto.value = false
      await onGuardado?.()
    } catch (e) {
      error.value = e.message
    } finally {
      guardando.value = false
    }
  }

  // reactive() (no un objeto plano) para que las vistas puedan usar
  // `despacho.error`, `despacho.abierto`, etc. en el template sin `.value`:
  // el proxy de reactive() desenvuelve refs anidados al leer/escribir una
  // propiedad, algo que un objeto plano con refs adentro NO hace (ese sí
  // necesitaría `.value` explícito en cada acceso).
  return reactive({
    error,
    abierto,
    pedido,
    cargas,
    dividirPedido,
    fechaResidual,
    guardando,
    saldoPendiente,
    totalCargas,
    residualEstimado,
    cargandoVales,
    pesajeAbierto,
    sinValesEnBalanza,
    abrir,
    agregarCargaSinBalanza,
    quitarCarga,
    guardar,
  })
}
