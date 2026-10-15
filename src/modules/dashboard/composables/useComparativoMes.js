// Comparativo del mes en Home (2026-10-15, pedido de Federico): mes en curso
// (del 1 a ayer) contra los mismos días del mes anterior, por tipo de
// producto. Cálculo de tramos y textos en services/comparativo-mes.js.

import { computed, ref } from 'vue'
import { fetchTotalesRango } from '@/services/despachos.service'
import { filasComparativo, periodosComparativo, subtituloComparativo } from '@/modules/dashboard/services/comparativo-mes'

export function useComparativoMes() {
  const cargando = ref(false)
  const error = ref(null)
  const periodos = periodosComparativo(new Date())
  const totalesActual = ref(null)
  const totalesAnterior = ref(null)

  const subtitulo = subtituloComparativo(periodos)
  const filas = computed(() =>
    totalesActual.value ? filasComparativo(periodos, totalesActual.value, totalesAnterior.value) : []
  )

  async function cargar() {
    cargando.value = true
    error.value = null
    try {
      const [actual, anterior] = await Promise.all([
        fetchTotalesRango(periodos.actual.desde, periodos.actual.hasta),
        fetchTotalesRango(periodos.anterior.desde, periodos.anterior.hasta),
      ])
      totalesActual.value = actual
      totalesAnterior.value = anterior
    } catch (e) {
      error.value = e.message
    } finally {
      cargando.value = false
    }
  }

  return { cargando, error, subtitulo, filas, cargar }
}
