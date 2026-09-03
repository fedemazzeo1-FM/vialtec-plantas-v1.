// Datos del "Informe mensual de producción" — Despachos → Resumen por obra
// (roadmap Mobile + pedido de Federico, memory/pending.md 2026-09-02).
// Ningún componente .vue debe importar `supabase` directamente (memory/
// conventions.md) — pero este service tampoco lo hace: arma el informe
// combinando servicios YA existentes (despachos/stock), sin duplicar
// queries. Lo único nuevo de verdad acá es fetchResumenAnual() (recorre
// enero..mes elegido del año) y fetchConsumoInsumosDelMes() (agrupa
// movimientos de egreso_despacho ya existentes, no recalcula fórmulas).
//
// El informe es 100% dinámico: todo lo que ve el usuario sale de estas
// queries en el momento del export, según el mes elegido en el selector de
// "Resumen por obra" — nada hardcodeado (pedido explícito de Federico).

import { fetchResumenPorObra, fetchTotalesMes, fetchDespachos, rangoDelMes } from '@/services/despachos.service'
import { fetchTodosLosMovimientos } from '@/services/stock.service'
import { fetchObras } from '@/services/flota.service'
import { fetchFormulas } from '@/modules/maestros/services/formulas.service'

/**
 * Despachos por obra del mes, separados interno (obra real, tipo_pedido
 * 'obra') vs. externo (venta, sin obra_id) — misma distinción que ya usa
 * `plantas_pedidos.tipo_pedido`/`cliente_externo` en todo el resto de la
 * app (memory/business-rules.md).
 * @param {string} mes 'YYYY-MM'
 */
export async function fetchDespachosPorObraDelMes(mes) {
  const resumen = await fetchResumenPorObra(mes)
  const internos = resumen.filter((r) => r.obraId != null).sort((a, b) => b.asfaltoTn + b.hormigonM3 - (a.asfaltoTn + a.hormigonM3))
  const externos = resumen.filter((r) => r.obraId == null).sort((a, b) => b.asfaltoTn + b.hormigonM3 - (a.asfaltoTn + a.hormigonM3))

  const sumar = (lista, campo) => lista.reduce((acc, r) => acc + r[campo], 0)
  const subtotalInterno = {
    despachos: sumar(internos, 'cantidadDespachos'),
    hormigonM3: sumar(internos, 'hormigonM3'),
    asfaltoTn: sumar(internos, 'asfaltoTn'),
  }
  const subtotalExterno = {
    despachos: sumar(externos, 'cantidadDespachos'),
    hormigonM3: sumar(externos, 'hormigonM3'),
    asfaltoTn: sumar(externos, 'asfaltoTn'),
  }

  return {
    internos,
    externos,
    subtotalInterno,
    subtotalExterno,
    totalGeneral: {
      despachos: subtotalInterno.despachos + subtotalExterno.despachos,
      hormigonM3: subtotalInterno.hormigonM3 + subtotalExterno.hormigonM3,
      asfaltoTn: subtotalInterno.asfaltoTn + subtotalExterno.asfaltoTn,
    },
  }
}

/**
 * Consumo de insumos del mes — agrupa por material los movimientos
 * `egreso_despacho` ya registrados por `finalizar_despacho()`/
 * `corregir_despacho()` (memory/business-rules.md: el descuento de stock
 * por despacho es automático al despachar). Reusa fetchTodosLosMovimientos()
 * de stock.service.js (memory/architecture.md, regla de paginación) — no
 * recalcula consumo desde fórmulas, lee lo que YA se descontó de stock, más
 * fiel a lo que realmente se consumió (incluye correcciones manuales).
 * @param {string} mes 'YYYY-MM'
 */
export async function fetchConsumoInsumosDelMes(mes) {
  const { desde, hasta } = rangoDelMes(mes)
  const movimientos = await fetchTodosLosMovimientos({ tipo: 'egreso_despacho', desde, hasta })

  const porMaterial = new Map()
  for (const m of movimientos) {
    const nombre = m.materialNombre || 'Sin especificar'
    porMaterial.set(nombre, (porMaterial.get(nombre) ?? 0) + Math.abs(Number(m.cantidad_kg) || 0))
  }

  const filas = Array.from(porMaterial.entries())
    .map(([material, kg]) => ({ material, toneladas: kg / 1000 }))
    .sort((a, b) => b.toneladas - a.toneladas)

  return { filas, totalTn: filas.reduce((acc, f) => acc + f.toneladas, 0) }
}

const NOMBRES_MES = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
]

/** @param {string} mes 'YYYY-MM' -> 'Marzo 2026' */
export function nombreMesLargo(mes) {
  const [anio, mesNum] = mes.split('-').map(Number)
  return `${NOMBRES_MES[mesNum - 1]} ${anio}`
}

/**
 * Acumulado del año, de enero hasta el mes elegido (inclusive) — "Resumen
 * anual" del informe (memory/relevamiento, formato del Excel de referencia
 * de Federico: una fila por mes + fila de total acumulado). N queries chicas
 * (una por mes, cada una ya paginada por dentro vía fetchTotalesMes) — el
 * export es una acción puntual, no carga de página, el costo es aceptable.
 * @param {string} mesHasta 'YYYY-MM'
 */
export async function fetchResumenAnual(mesHasta) {
  const [anio, mesNum] = mesHasta.split('-').map(Number)
  const meses = Array.from({ length: mesNum }, (_, i) => `${anio}-${String(i + 1).padStart(2, '0')}`)
  const totales = await Promise.all(meses.map((m) => fetchTotalesMes(m)))

  const filas = meses.map((m, i) => ({ mes: nombreMesLargo(m), ...totales[i] }))
  const totalAcumulado = {
    hormigonM3: filas.reduce((acc, f) => acc + f.hormigonM3, 0),
    asfaltoTn: filas.reduce((acc, f) => acc + f.asfaltoTn, 0),
  }
  return { filas, totalAcumulado, anio }
}

/**
 * Detalle de despachos (vale/remito/entrega) de una obra puntual en el mes
 * — una hoja del informe por obra. Reusa fetchDespachos() (ya existe,
 * paginado) filtrando por obraId + el rango del mes; para ventas externas
 * (sin obra propia) filtra client-side por cliente_externo ya que
 * fetchDespachos() no tiene ese filtro (volumen bajo por cliente, no
 * amerita agregar un filtro server-side nuevo solo para esto).
 * @param {{ obraId?: number, clienteExterno?: string }} destino
 * @param {string} mes 'YYYY-MM'
 * @param {Record<string, {nombre: string}>} formulasPorId para resolver el nombre de mezcla (columna "Mezcla" de la hoja)
 */
export async function fetchDetalleDestinoDelMes(destino, mes, formulasPorId) {
  const { desde, hasta } = rangoDelMes(mes)
  const { filas } = await fetchDespachos(
    { obraId: destino.obraId || undefined, desde, hasta },
    { pagina: 1, tamanoPagina: 1000 } // tope generoso: un solo destino en un mes no supera esto (memory/architecture.md, no es un listado sin acotar)
  )
  // Mismo fallback que fetchResumenPorObra() (despachos.service.js) al
  // agrupar: una venta externa sin cliente_externo cargado se agrupa bajo
  // "Venta externa" — el filtro de acá tiene que usar el mismo fallback o
  // esos despachos quedan fuera del detalle aunque sí sumen en el resumen.
  const propias = destino.obraId
    ? filas
    : filas.filter((f) => (f.cliente_externo || 'Venta externa') === destino.clienteExterno)

  return propias
    .map((p) => ({
      fecha: p.fecha_programada,
      mezcla: formulasPorId[p.formula_id]?.nombre ?? '—',
      tipo: p.tipo === 'hormigon' ? 'Hormigón' : 'Asfalto',
      unidad: p.tipo === 'hormigon' ? 'm³' : 'tn',
      pedido: Number(p.cantidad_solicitada),
      real: Number(p.cantidad_despachada) || 0,
      nroRemito: p.nro_remito_global || '',
      nroVale: p.nro_vale_global || '',
      encargado: p.encargado || '',
      notas: p.motivo || '',
    }))
    .sort((a, b) => (a.fecha < b.fecha ? -1 : 1))
}

/**
 * Arma el paquete completo de datos del informe para un mes — un solo
 * punto de entrada para el composable/export a Excel, evita que la vista
 * orqueste 6 llamadas sueltas.
 * @param {string} mes 'YYYY-MM'
 */
export async function fetchDatosInformeMensual(mes) {
  const [obras, formulas, despachosPorObra, consumoInsumos, resumenAnual] = await Promise.all([
    fetchObras(),
    fetchFormulas({ soloActivas: false }),
    fetchDespachosPorObraDelMes(mes),
    fetchConsumoInsumosDelMes(mes),
    fetchResumenAnual(mes),
  ])
  const obrasPorId = Object.fromEntries(obras.map((o) => [o.id, o]))
  const formulasPorId = Object.fromEntries(formulas.map((f) => [f.id, f]))

  // Detalle por destino (hojas individuales) — en paralelo, uno por obra
  // interna + uno por cada cliente externo distinto.
  const destinosInternos = despachosPorObra.internos.map((r) => ({
    nombre: obrasPorId[r.obraId]?.nombre ?? `Obra #${r.obraId}`,
    obraId: r.obraId,
  }))
  const destinosExternos = despachosPorObra.externos.map((r) => ({
    nombre: r.clienteExterno,
    clienteExterno: r.clienteExterno,
  }))

  const [detalleInternos, detalleExternos] = await Promise.all([
    Promise.all(destinosInternos.map((d) => fetchDetalleDestinoDelMes(d, mes, formulasPorId))),
    Promise.all(destinosExternos.map((d) => fetchDetalleDestinoDelMes(d, mes, formulasPorId))),
  ])

  return {
    mes,
    mesLabel: nombreMesLargo(mes),
    despachosPorObra,
    consumoInsumos,
    resumenAnual,
    hojasInternas: destinosInternos.map((d, i) => ({ ...d, detalle: detalleInternos[i] })),
    hojaVentasExternas: {
      destinos: destinosExternos.map((d, i) => ({ ...d, detalle: detalleExternos[i] })),
      resumen: despachosPorObra.externos,
    },
  }
}
