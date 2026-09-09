// Composable del modal "Registrar despacho" de asfalto: multi-camión con
// vale por carga (memory/relevamiento-sistema-viejo.md §1 — el sistema
// legado soporta N cargas con N° de vale obligatorio por carga). Cada carga
// se persiste con una llamada independiente a registrarCargaAsfalto (RPC
// atómica con lock de fila) — ver pedidos.service.js. El N° de remito del
// despacho ya NO se tipea acá: desde 2026-09-09 (pedido de Federico) se
// asigna automáticamente y una sola vez, dentro de la RPC, en la primera
// carga del pedido (mismo número para todas las cargas/pesadas).
//
// Cierre del pedido (Logica sis. plantas v1.rtf §2.2, migración 11): al
// terminar de cargar, SIEMPRE se llama a finalizarDespacho() — el pedido
// pasa a despachado con lo cargado hasta ese momento, sea parcial o
// completo. Si queda saldo, se puede activar "dividir pedido" para generar
// automáticamente un pedido residual confirmado en una fecha a elegir.

import { computed, reactive, ref } from 'vue'
import { registrarCargaAsfalto, finalizarDespacho } from '@/modules/pedidos/services/pedidos.service'

function cargaVacia(cantidadSugerida = null) {
  return reactive({ cantidad_tn: cantidadSugerida, numero_vale: '', patente: '' })
}

/**
 * @param {() => Promise<void>|void} onGuardado callback tras cerrar el
 *   despacho con éxito (típicamente refrescar el listado de pedidos).
 */
export function useDespachoAsfalto(onGuardado) {
  const error = ref(null)
  const abierto = ref(false)
  const pedido = ref(null)
  const cargas = ref([])
  const dividirPedido = ref(false)
  const fechaResidual = ref('')
  const guardando = ref(false)

  const saldoPendiente = computed(() => {
    if (!pedido.value) return 0
    return Number(pedido.value.cantidad_solicitada) - Number(pedido.value.cantidad_despachada || 0)
  })

  const totalCargas = computed(() => cargas.value.reduce((acum, c) => acum + (Number(c.cantidad_tn) || 0), 0))

  /** Lo que va a quedar pendiente después de guardar estas cargas — solo tiene sentido si es > 0. */
  const residualEstimado = computed(() => Math.max(0, saldoPendiente.value - totalCargas.value))

  function abrir(pedidoAsfalto) {
    pedido.value = pedidoAsfalto
    cargas.value = [cargaVacia(saldoPendiente.value)]
    dividirPedido.value = false
    fechaResidual.value = ''
    error.value = null
    abierto.value = true
  }

  function agregarCarga() {
    cargas.value.push(cargaVacia())
  }

  function quitarCarga(index) {
    if (cargas.value.length <= 1) return
    cargas.value.splice(index, 1)
  }

  async function guardar() {
    for (const carga of cargas.value) {
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
        })
      }
      // Cierra el pedido con lo cargado (parcial o completo) y, si se pidió,
      // genera el residual — ver migración 11.
      await finalizarDespacho(pedido.value.id, {
        dividir: dividirPedido.value,
        fechaResidual: fechaResidual.value || undefined,
      })
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
    abrir,
    agregarCarga,
    quitarCarga,
    guardar,
  })
}
