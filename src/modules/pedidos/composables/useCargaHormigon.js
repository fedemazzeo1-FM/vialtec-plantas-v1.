// Composable del modal "Registrar despacho" de hormigón: multi-camión con
// remito por carga (mismo patrón que useDespachoAsfalto.js — confirmado en
// vivo, memory/relevamiento-sistema-viejo.md Etapa 3: el legado usa el
// MISMO modal "Registrar despacho" para los dos materiales, con "+ Agregar
// carga"). Hormigón nunca pasa por báscula (memory/business-rules.md), y el
// modal real solo pide Cantidad/N° Remito/Patente por carga — sin Chofer ni
// fecha/hora (esos dos campos estaban de más en la versión anterior de este
// composable, se sacaron acá).
//
// Cierre del pedido: igual que asfalto, SIEMPRE se llama a
// finalizarDespacho() al terminar de cargar (parcial o completo, con
// opción de dividir pedido) — Logica sis. plantas v1.rtf §2.2, migración 11.

import { computed, reactive, ref } from 'vue'
import { registrarCargaHormigon, finalizarDespacho } from '@/modules/pedidos/services/pedidos.service'

function cargaVacia(cantidadSugerida = null) {
  return reactive({ volumen_m3: cantidadSugerida, numero_remito: '', patente_mixer: '' })
}

/**
 * @param {() => Promise<void>|void} onGuardado callback tras cerrar el despacho con éxito.
 */
export function useCargaHormigon(onGuardado) {
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

  const totalCargas = computed(() => cargas.value.reduce((acum, c) => acum + (Number(c.volumen_m3) || 0), 0))
  const residualEstimado = computed(() => Math.max(0, saldoPendiente.value - totalCargas.value))

  function abrir(pedidoHormigon) {
    pedido.value = pedidoHormigon
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
      if (!(Number(carga.volumen_m3) > 0)) {
        error.value = 'Cada carga necesita un volumen mayor a 0.'
        return
      }
      if (!carga.numero_remito.trim()) {
        error.value = 'El N° de remito es obligatorio en cada carga.'
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
      // Secuencial — mismo motivo que useDespachoAsfalto.js: cada carga
      // depende del lock de fila del pedido en la RPC.
      for (const carga of cargas.value) {
        await registrarCargaHormigon({
          pedido_id: pedido.value.id,
          numero_remito: carga.numero_remito.trim(),
          volumen_m3: carga.volumen_m3,
          patente_mixer: carga.patente_mixer || null,
        })
      }
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

  // reactive() (no objeto plano) — mismo motivo que en useDespachoAsfalto.js:
  // permite `cargaHormigon.error`/`cargaHormigon.abierto` sin `.value` en el
  // template, porque el proxy de reactive() desenvuelve refs anidados.
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
