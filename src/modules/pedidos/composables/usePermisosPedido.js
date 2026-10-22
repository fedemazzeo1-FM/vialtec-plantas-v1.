// Permisos de UI sobre las acciones de un pedido — una sola definición para
// Pedidos y Plan semanal (2026-10-22: el Plan semanal también despacha, y
// los botones tienen que aparecer para los mismos roles en las dos
// pantallas). Es solo para no mostrar acciones que el servidor va a
// rechazar: el permiso real vive en las RPC.
//
// RBAC (2026-09-16, pedido de Federico): Confirmar/Despachar solo para
// plantista/admin — "pedidos.aprobar" en la matriz hoy resuelve exactamente
// a ese par de roles (admin por bypass total). Despachar difiere por tipo
// porque las RPC detrás (registrar_carga_asfalto/registrar_carga_hormigon)
// hardcodean roles distintos, no pasan por la matriz: asfalto queda
// admin/plantista únicamente, hormigón además admite plantista_hormigon
// (rol que existe específicamente para despachar hormigón — no se le puede
// sacar esa única acción sin romper su función real). Ver esos 2 archivos
// de migración si esto cambia algún día.

import { computed } from 'vue'
import { useAuthStore } from '@/stores/auth.store'
import { esCircuitoBascula, esCircuitoMixer } from '@/config/tipos-producto'

export function usePermisosPedido() {
  const auth = useAuthStore()

  const puedeConfirmar = computed(() => auth.tienePermiso('pedidos', 'aprobar'))
  const puedeDespacharAsfalto = computed(() => auth.rol === 'admin' || auth.rol === 'plantista')
  const puedeDespacharHormigon = computed(
    () => auth.rol === 'admin' || auth.rol === 'plantista' || auth.rol === 'plantista_hormigon'
  )
  // Editar/Postergar por creador (2026-09-17, migración 41): admin/plantista
  // mantienen alcance global; cualquier otro rol (encargado/supervisor, los
  // únicos que además pueden crear pedidos) solo sobre el pedido que él mismo
  // creó — PedidoCard.vue compara pedido.creado_por contra este email.
  const puedeGestionarPedidosGlobal = computed(() => auth.rol === 'admin' || auth.rol === 'plantista')

  /** ¿Se muestra "Despachar" para este pedido? Mismo criterio que PedidoCard.vue. */
  function puedeDespachar(pedido) {
    if (pedido?.estado !== 'confirmado') return false
    if (esCircuitoBascula(pedido.tipo)) return puedeDespacharAsfalto.value
    if (esCircuitoMixer(pedido.tipo)) return puedeDespacharHormigon.value
    return false
  }

  return { puedeConfirmar, puedeDespacharAsfalto, puedeDespacharHormigon, puedeGestionarPedidosGlobal, puedeDespachar }
}
