// Aviso "stock insuficiente" después de despachar o corregir un despacho
// (2026-10-28, pedido de Federico tras el caso AM3): cuando el piso en 0
// recorta un descuento, hasta ahora solo quedaba escrito en las observaciones
// del movimiento y nadie se enteraba. El modal de despacho se cierra al
// guardar, así que el aviso vive fuera de la vista: estado compartido a nivel
// módulo, que muestra AvisoPisoStock.vue en los dos layouts.
//
// Nunca bloquea ni cambia el despacho: si la consulta falla (por ejemplo, un
// rol sin lectura de movimientos de stock), no se muestra nada.

import { ref } from 'vue'
import { fetchRecortesPorPiso } from '@/services/stock.service'
import { formatearNumeroPedido } from '@/services/formato-numeros'

const avisos = ref([])

/**
 * @param {{ id: string, numero?: number }} pedido
 * @param {string} desde ISO tomado ANTES de llamar a la RPC
 */
async function revisarRecortesPorPiso(pedido, desde) {
  if (!pedido?.id || !desde) return
  try {
    const recortes = await fetchRecortesPorPiso(pedido.id, desde)
    if (!recortes.length) return
    avisos.value = [
      ...avisos.value.filter((a) => a.pedidoId !== pedido.id),
      { pedidoId: pedido.id, pedido: formatearNumeroPedido(pedido.numero), recortes },
    ]
  } catch {
    // El aviso es informativo: sin lectura de movimientos, no hay aviso.
  }
}

function cerrarAviso(pedidoId) {
  avisos.value = avisos.value.filter((a) => a.pedidoId !== pedidoId)
}

export function useAvisoPisoStock() {
  return { avisos, revisarRecortesPorPiso, cerrarAviso }
}

// Desde cuándo buscar recortes: un poco antes de llamar a la RPC, por si el
// reloj de la PC no coincide con el del servidor.
export function inicioVentanaRecortes() {
  return new Date(Date.now() - 2 * 60 * 1000).toISOString()
}
