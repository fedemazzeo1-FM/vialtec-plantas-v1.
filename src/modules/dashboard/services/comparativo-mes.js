// Comparativo del mes en Home (2026-10-15, pedido de Federico): lo producido
// en el mes en curso contra el mismo tramo del mes anterior, por tipo de
// producto (config/tipos-producto.js). Funciones puras — sin Supabase: los
// totales los trae useComparativoMes.js con fetchTotalesRango(), el mismo
// criterio que los totales mensuales de Home (pedidos `despachado`, por
// fecha_programada, cantidad_despachada).

import { LISTA_TIPOS_PRODUCTO } from '@/config/tipos-producto'

const NOMBRES_MES = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
]

const aISO = (anio, mes0, dia) => `${anio}-${String(mes0 + 1).padStart(2, '0')}-${String(dia).padStart(2, '0')}`
const diasDelMes = (anio, mes0) => new Date(anio, mes0 + 1, 0).getDate()

/**
 * Los dos tramos a comparar, en fechas locales.
 * - Actual: del 1 hasta ayer (días completos). El día 1 no hay días
 *   completos: se toma el mes anterior cerrado.
 * - Anterior: los mismos días del mes previo; si ese día no existe (31 vs
 *   30, 30 vs 28), el mes previo completo.
 * @param {Date} hoy
 */
export function periodosComparativo(hoy = new Date()) {
  const ayer = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate() - 1)
  const mesCerrado = hoy.getDate() === 1

  const anio = ayer.getFullYear()
  const mes0 = ayer.getMonth()
  const diaHasta = ayer.getDate()

  const previo = new Date(anio, mes0 - 1, 1)
  const anioPrevio = previo.getFullYear()
  const mes0Previo = previo.getMonth()
  const diaHastaPrevio = Math.min(diaHasta, diasDelMes(anioPrevio, mes0Previo))

  return {
    mesCerrado,
    actual: { anio, mes0, diaHasta, desde: aISO(anio, mes0, 1), hasta: aISO(anio, mes0, diaHasta) },
    anterior: {
      anio: anioPrevio,
      mes0: mes0Previo,
      diaHasta: diaHastaPrevio,
      desde: aISO(anioPrevio, mes0Previo, 1),
      hasta: aISO(anioPrevio, mes0Previo, diaHastaPrevio),
    },
  }
}

function tramo({ anio, mes0, diaHasta }, conAnio) {
  const mes = `${NOMBRES_MES[mes0]}${conAnio ? ` de ${anio}` : ''}`
  return diaHasta === 1 ? `1 de ${mes}` : `1 al ${diaHasta} de ${mes}`
}

/** "Del 1 al 14 de octubre vs. 1 al 14 de septiembre" (con año solo si cambia). */
export function subtituloComparativo({ actual, anterior }) {
  const conAnio = actual.anio !== anterior.anio
  const texto = `${tramo(actual, conAnio)} vs. ${tramo(anterior, conAnio)}`
  return actual.diaHasta === 1 ? `El ${texto.replace(' vs. ', ' vs. el ')}` : `Del ${texto}`
}

const formatear = (n) => n.toLocaleString('es-AR', { maximumFractionDigits: 1 })

function formatearPorcentaje(pct) {
  const abs = Math.abs(pct)
  const decimales = abs > 0 && abs < 1 ? 1 : 0
  return `${abs.toLocaleString('es-AR', { maximumFractionDigits: decimales, minimumFractionDigits: decimales })}%`
}

/**
 * Una fila por tipo con producción en alguno de los dos tramos.
 * @param {Record<string, number>} totalesActual  ({ asfaltoTn, hormigonM3, … })
 * @param {Record<string, number>} totalesAnterior
 */
export function filasComparativo(periodos, totalesActual, totalesAnterior) {
  const mesActual = NOMBRES_MES[periodos.actual.mes0]
  const mesAnterior = NOMBRES_MES[periodos.anterior.mes0]

  return LISTA_TIPOS_PRODUCTO.map((tipo) => {
    const actual = Number(totalesActual?.[tipo.total]) || 0
    const anterior = Number(totalesAnterior?.[tipo.total]) || 0
    if (actual === 0 && anterior === 0) return null

    const cantidad = (n) => `${formatear(n)} ${tipo.unidadLabel}`
    const producto = tipo.nombre.toLowerCase()
    const diferencia = actual - anterior
    const sinAnterior = anterior === 0
    const pct = sinAnterior ? null : (diferencia / anterior) * 100
    const tendencia = diferencia > 0 ? 'sube' : diferencia < 0 ? 'baja' : 'igual'

    // Frase: el mes cerrado (día 1) se cuenta en pasado y sin "a esta altura".
    const inicio = periodos.mesCerrado
      ? `En ${mesActual} se despacharon ${cantidad(actual)} de ${producto}`
      : `En lo que va de ${mesActual} llevamos ${cantidad(actual)} de ${producto}`
    const referencia = periodos.mesCerrado ? `en ${mesAnterior}` : `a esta altura de ${mesAnterior}`
    let frase
    if (actual === 0) {
      frase = periodos.mesCerrado
        ? `En ${mesActual} no hubo despachos de ${producto}; ${referencia} fueron ${cantidad(anterior)}.`
        : `En lo que va de ${mesActual} no hay despachos de ${producto}; ${referencia} llevábamos ${cantidad(anterior)}.`
    } else if (sinAnterior) {
      frase = `${inicio}; ${referencia} no hubo producción.`
    } else if (tendencia === 'igual') {
      frase = `${inicio}, lo mismo que ${referencia}.`
    } else {
      frase = `${inicio}, ${formatearPorcentaje(pct)} ${tendencia === 'sube' ? 'más' : 'menos'} que ${referencia} (${cantidad(anterior)}).`
    }

    const signo = diferencia > 0 ? '+' : diferencia < 0 ? '−' : ''
    return {
      tipo,
      actual,
      anterior,
      tendencia,
      frase,
      badge: sinAnterior
        ? 'sin producción el mes anterior'
        : `${tendencia === 'sube' ? '▲' : tendencia === 'baja' ? '▼' : '='} ${formatearPorcentaje(pct)} · ${signo}${cantidad(Math.abs(diferencia))}`,
    }
  }).filter(Boolean)
}
