// Resumen acumulado del año para mobile (2026-10-02, pedido de Federico):
// total de asfalto (con el desglose por planta) y de hormigón, solo para
// admin y gerencia. Reusa los mismos cálculos que las cards de Home
// (dashboard.service.js) — los números son siempre los mismos en las dos
// pantallas.
//
// En mobile no hay Home (MobileLayout: Pedidos, Calendario, Stock, Báscula);
// admin y gerencia aterrizan en Pedidos, que es donde se muestra.

import { computed, reactive, ref, watch } from 'vue'
import { useAuthStore } from '@/stores/auth.store'
import { useBreakpoint } from '@/composables/useBreakpoint'
import {
  fetchProduccionAnualAsfalto,
  fetchProduccionAnualHormigon,
} from '@/modules/dashboard/services/dashboard.service'

const ROLES_CON_RESUMEN = ['admin', 'gerencia']

export function useResumenAnualMobile() {
  const auth = useAuthStore()
  const { esMobile } = useBreakpoint()

  const visible = computed(() => esMobile.value && ROLES_CON_RESUMEN.includes(auth.rol))
  const cargando = ref(false)
  const error = ref(null)
  const asfalto = reactive({ ammannTn: 0, mariniTn: 0, totalTn: 0 })
  const hormigonM3 = ref(0)
  let cargado = false

  async function cargar() {
    cargando.value = true
    error.value = null
    try {
      const [datosAsfalto, datosHormigon] = await Promise.all([
        fetchProduccionAnualAsfalto(),
        fetchProduccionAnualHormigon(),
      ])
      Object.assign(asfalto, datosAsfalto)
      hormigonM3.value = datosHormigon.totalM3
      cargado = true
    } catch (e) {
      error.value = e.message
    } finally {
      cargando.value = false
    }
  }

  // Solo consulta cuando corresponde mostrarlo (y una vez): otros roles, o
  // admin/gerencia en desktop, no disparan ninguna query.
  watch(
    visible,
    (v) => {
      if (v && !cargado && !cargando.value) cargar()
    },
    { immediate: true }
  )

  return reactive({ visible, cargando, error, asfalto, hormigonM3 })
}
