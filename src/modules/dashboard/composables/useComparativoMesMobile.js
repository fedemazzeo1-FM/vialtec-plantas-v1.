// Comparativo del mes para mobile (2026-10-22, pedido de Federico): la misma
// tarjeta de Home (mes en curso del 1 a ayer vs. los mismos días del mes
// anterior), en Pedidos —donde aterrizan admin y gerencia en mobile, que no
// tiene Home—. Mismos datos y misma lógica: envuelve useComparativoMes.js
// (fetchTotalesRango + services/comparativo-mes.js); acá solo se decide
// cuándo mostrarlo, con el mismo criterio que el "Acumulado del año".

import { computed, reactive, watch } from 'vue'
import { useAuthStore } from '@/stores/auth.store'
import { useBreakpoint } from '@/composables/useBreakpoint'
import { useComparativoMes } from '@/modules/dashboard/composables/useComparativoMes'
import { ROLES_CON_RESUMEN } from '@/modules/dashboard/composables/useResumenAnualMobile'

export function useComparativoMesMobile() {
  const auth = useAuthStore()
  const { esMobile } = useBreakpoint()
  const comparativo = useComparativoMes()

  const visible = computed(() => esMobile.value && ROLES_CON_RESUMEN.includes(auth.rol))
  let cargado = false

  // Solo consulta cuando corresponde mostrarlo (y una vez): otros roles, o
  // admin/gerencia en desktop, no disparan ninguna query.
  watch(
    visible,
    (v) => {
      if (v && !cargado) {
        cargado = true
        comparativo.cargar()
      }
    },
    { immediate: true }
  )

  return reactive({ visible, ...comparativo })
}
