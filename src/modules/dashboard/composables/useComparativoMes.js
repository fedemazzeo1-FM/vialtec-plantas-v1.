// Comparativo del mes en Home (2026-10-15, pedido de Federico): mes en curso
// (del 1 a ayer) contra los mismos días del mes anterior, por tipo de
// producto. Cálculo de tramos y textos en services/comparativo-mes.js.

import { computed, ref } from 'vue'
import { fetchTotalesRango } from '@/services/despachos.service'
import {
  anteriorEsMesCompleto,
  filasComparativo,
  periodosComparativo,
  subtituloComparativo,
} from '@/modules/dashboard/services/comparativo-mes'

export function useComparativoMes() {
  const cargando = ref(false)
  const error = ref(null)
  const periodos = periodosComparativo(new Date())
  const totalesActual = ref(null)
  const totalesAnterior = ref(null)
  // Mes anterior entero: para decir cómo cerró cuando sus primeros días dan 0.
  const totalesMesAnterior = ref(null)

  const subtitulo = subtituloComparativo(periodos)
  const filas = computed(() =>
    totalesActual.value
      ? filasComparativo(periodos, totalesActual.value, totalesAnterior.value, totalesMesAnterior.value)
      : []
  )

  async function cargar() {
    cargando.value = true
    error.value = null
    try {
      const { anterior: tramoAnterior } = periodos
      const finMesAnterior = new Date(tramoAnterior.anio, tramoAnterior.mes0 + 1, 0).getDate()
      const [actual, anterior, mesAnterior] = await Promise.all([
        fetchTotalesRango(periodos.actual.desde, periodos.actual.hasta),
        fetchTotalesRango(tramoAnterior.desde, tramoAnterior.hasta),
        // Si el tramo ya es el mes entero, no hace falta otra consulta.
        anteriorEsMesCompleto(periodos)
          ? null
          : fetchTotalesRango(tramoAnterior.desde, tramoAnterior.desde.slice(0, 8) + String(finMesAnterior).padStart(2, '0')),
      ])
      totalesActual.value = actual
      totalesAnterior.value = anterior
      totalesMesAnterior.value = mesAnterior
    } catch (e) {
      error.value = e.message
    } finally {
      cargando.value = false
    }
  }

  return { cargando, error, subtitulo, filas, cargar }
}
