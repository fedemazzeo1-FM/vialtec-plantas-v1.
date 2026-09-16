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

import {
  fetchResumenPorObra,
  fetchTotalesMes,
  fetchDespachos,
  rangoDelMes,
  fetchValesDeVariosPedidos,
  fetchCargasHormigonDeVariosPedidos,
} from '@/services/despachos.service'
import { fetchTodosLosMovimientos } from '@/services/stock.service'
import { fetchObras } from '@/services/flota.service'
import { fetchFormulas } from '@/modules/maestros/services/formulas.service'
// Analítica de proveedores del mes (2026-09-03, pedido de Federico: sumarla
// al informe mensual) — reusa la misma función que ya usa Stock → Analítica
// de proveedores (memory/conventions.md, no duplicar la query/agregación).
import { fetchAnaliticaProveedoresDetalle } from '@/modules/analytics/services/analytics.service'
import { PRODUCCION_PRE_MAYO_2026 } from '@/modules/dashboard/services/dashboard.service'

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

  // Fix 2026-09-07 (pedido de Federico: "Resumen Anual no computa ene-abr
  // 2026"): esos meses nunca se cargaron en plantas_pedidos (ver
  // PRODUCCION_PRE_MAYO_2026, dashboard.service.js) — fetchTotalesMes()
  // sola siempre iba a dar 0/casi 0 ahí. Se suma el histórico fijo de ese
  // Excel cuando el mes corresponde (no aplica a ningún otro año/mes, el
  // objeto solo tiene esas 4 claves).
  const filas = meses.map((m, i) => {
    const historico = PRODUCCION_PRE_MAYO_2026[m]
    return {
      mes: nombreMesLargo(m),
      asfaltoTn: totales[i].asfaltoTn + (historico?.asfaltoTn ?? 0),
      hormigonM3: totales[i].hormigonM3 + (historico?.hormigonM3 ?? 0),
    }
  })
  const totalAcumulado = {
    hormigonM3: filas.reduce((acc, f) => acc + f.hormigonM3, 0),
    asfaltoTn: filas.reduce((acc, f) => acc + f.asfaltoTn, 0),
  }
  return { filas, totalAcumulado, anio }
}

/**
 * Detalle de pesadas/cargas individuales (Tabla 2 de la hoja por destino,
 * 2026-09-16, pedido de Federico) — una fila por CAMIÓN/pesada real, a
 * diferencia del resumen por pedido de fetchDetalleDestinoDelMes() (una fila
 * por pedido). Asfalto sale de plantas_vales (Báscula, no anulados): es la
 * única fuente con peso NETO realmente pesado, chofer y N° de vale siempre
 * poblado — plantas_cargas_asfalto (lo que tipea el plantista al despachar)
 * no tiene chofer ni peso real, solo la cantidad declarada, y memory/
 * business-rules.md es explícito en que Báscula y Pedidos no se dedupean
 * entre sí, así que no se mezclan ambas fuentes en una sola fila acá.
 * Hormigón no tiene báscula (se mide por volumen del mixer, no se pesa) —
 * sale de plantas_cargas_hormigon, remito/chofer por carga siempre
 * poblados (ambos obligatorios al despachar).
 * @param {Array<{id: string, tipo: string}>} pedidos crudos (fetchDespachos)
 * @param {Record<string, {nro_remito_global: string|null}>} pedidosPorId
 */
async function fetchDetallePesadasDelMes(pedidos, pedidosPorId) {
  const idsAsfalto = pedidos.filter((p) => p.tipo === 'asfalto').map((p) => p.id)
  const idsHormigon = pedidos.filter((p) => p.tipo === 'hormigon').map((p) => p.id)

  const [vales, cargasHormigon] = await Promise.all([
    fetchValesDeVariosPedidos(idsAsfalto),
    fetchCargasHormigonDeVariosPedidos(idsHormigon),
  ])

  const filasAsfalto = vales.map((v) => ({
    fecha: v.fecha_pesada,
    tipo: 'Asfalto',
    // N° Remito es 1 solo por PEDIDO (compartido por todas sus pesadas,
    // migración 39) — se resuelve acá contra el pedido dueño de cada vale,
    // no contra el vale (que no tiene remito propio).
    nroRemito: pedidosPorId[v.pedido_id]?.nro_remito_global || '',
    nroVale: v.numero_vale != null ? String(v.numero_vale) : '',
    patente: v.patente || '',
    chofer: v.chofer || '',
    cantidad: v.unidad === 'kg' ? Number(v.peso_neto) / 1000 : Number(v.peso_neto),
    unidad: 'tn',
  }))

  const filasHormigon = cargasHormigon.map((c) => ({
    fecha: c.fecha_carga,
    tipo: 'Hormigón',
    nroRemito: c.numero_remito || '', // por carga, no por pedido — "el remito ya es por carga" en hormigón
    nroVale: '', // hormigón no tiene concepto de vale (no se pesa en báscula)
    patente: c.patente_mixer || '',
    chofer: c.chofer || '',
    cantidad: Number(c.volumen_m3) || 0,
    unidad: 'm³',
  }))

  return [...filasAsfalto, ...filasHormigon].sort((a, b) => (a.fecha < b.fecha ? -1 : 1))
}

/**
 * Detalle de despachos (vale/remito/entrega) de una obra puntual en el mes
 * — una hoja del informe por obra, con 2 tablas (2026-09-16, pedido de
 * Federico): `resumen` (una fila por PEDIDO, Tabla 1) y `pesadas` (una fila
 * por camión/carga real, Tabla 2 — ver fetchDetallePesadasDelMes() arriba).
 * Reusa fetchDespachos() (ya existe, paginado) filtrando por obraId + el
 * rango del mes; para ventas externas (sin obra propia) filtra client-side
 * por cliente_externo ya que fetchDespachos() no tiene ese filtro (volumen
 * bajo por cliente, no amerita agregar un filtro server-side nuevo solo
 * para esto).
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

  const resumen = propias
    .map((p) => ({
      id: p.id,
      fecha: p.fecha_programada,
      mezcla: formulasPorId[p.formula_id]?.nombre ?? '—',
      tipo: p.tipo === 'hormigon' ? 'Hormigón' : 'Asfalto',
      unidad: p.tipo === 'hormigon' ? 'm³' : 'tn',
      estado: p.estado,
      pedido: Number(p.cantidad_solicitada),
      real: Number(p.cantidad_despachada) || 0,
      nroRemito: p.nro_remito_global || '',
      nroVale: p.nro_vale_global || '',
      encargado: p.encargado || '',
      notas: p.motivo || '',
    }))
    .sort((a, b) => (a.fecha < b.fecha ? -1 : 1))

  const pedidosPorId = Object.fromEntries(propias.map((p) => [p.id, p]))
  const pesadas = await fetchDetallePesadasDelMes(propias, pedidosPorId)

  return { resumen, pesadas }
}

/**
 * Arma el paquete completo de datos del informe para un mes — un solo
 * punto de entrada para el composable/export a Excel, evita que la vista
 * orqueste 6 llamadas sueltas.
 * @param {string} mes 'YYYY-MM'
 */
export async function fetchDatosInformeMensual(mes) {
  const { desde, hasta } = rangoDelMes(mes)
  // Fix 2026-09-07 (bug real reportado por Federico: "faltan los nombres de
  // las obras" en el informe): fetchObras() por default trae solo obras
  // ACTIVAS (soloActivas=true, flota.service.js) — un despacho de una obra
  // que ya se dio de baja/renombró en flota_obras quedaba sin match acá,
  // mostrando "Obra #N" en vez del nombre real. `soloActivas: false` trae
  // el catálogo completo, mismo criterio que ya usaba fetchFormulas() al
  // lado (esa sí traía inactivas, la asimetría era el bug).
  const [obras, formulas, despachosPorObra, consumoInsumos, resumenAnual, analiticaProveedores] = await Promise.all([
    fetchObras({ soloActivas: false }),
    fetchFormulas({ soloActivas: false }),
    fetchDespachosPorObraDelMes(mes),
    fetchConsumoInsumosDelMes(mes),
    fetchResumenAnual(mes),
    fetchAnaliticaProveedoresDetalle({ desde, hasta }),
  ])
  const obrasPorId = Object.fromEntries(obras.map((o) => [o.id, o]))
  const formulasPorId = Object.fromEntries(formulas.map((f) => [f.id, f]))

  // Fix 2026-09-07 (bug real, segunda causa del mismo síntoma de arriba +
  // "Ventas Externas" sin nombre de cliente): fetchDespachosPorObraDelMes()
  // devuelve filas con `obraId`/`clienteExterno`, pero SIN `nombre` — la
  // hoja "Resumen mensual" y la hoja "Ventas Externas" (excel-informe-
  // mensual.js) leen `r.nombre` directo de `despachosPorObra.internos`/
  // `.externos`, que hasta ahora quedaba `undefined` en las dos tablas (el
  // `nombre` solo se calculaba acá abajo, en un array aparte que ni
  // siquiera se usaba para esas tablas). Se resuelve una sola vez acá y se
  // enriquece `despachosPorObra` in-place — un solo lugar de verdad para el
  // nombre, reusado tanto por las tablas de resumen como por el detalle por
  // destino de abajo (antes duplicaba la resolución del nombre en un
  // array aparte, `destinosInternos`/`destinosExternos`).
  despachosPorObra.internos = despachosPorObra.internos.map((r) => ({
    ...r,
    nombre: obrasPorId[r.obraId]?.nombre ?? `Obra #${r.obraId}`,
  }))
  despachosPorObra.externos = despachosPorObra.externos.map((r) => ({
    ...r,
    nombre: r.clienteExterno,
  }))

  // Detalle por destino (hojas individuales) — en paralelo, uno por obra
  // interna + uno por cada cliente externo distinto.
  const [detalleInternos, detalleExternos] = await Promise.all([
    Promise.all(despachosPorObra.internos.map((d) => fetchDetalleDestinoDelMes(d, mes, formulasPorId))),
    Promise.all(despachosPorObra.externos.map((d) => fetchDetalleDestinoDelMes(d, mes, formulasPorId))),
  ])

  return {
    mes,
    mesLabel: nombreMesLargo(mes),
    despachosPorObra,
    consumoInsumos,
    resumenAnual,
    analiticaProveedores,
    // detalleInternos[i]/detalleExternos[i] = { resumen, pesadas } (ver
    // fetchDetalleDestinoDelMes) — se desparraman acá para que
    // excel-informe-mensual.js reciba las 2 tablas de cada hoja ya
    // resueltas, sin tener que conocer la forma interna del fetch.
    hojasInternas: despachosPorObra.internos.map((d, i) => ({
      ...d,
      detalle: detalleInternos[i].resumen,
      pesadas: detalleInternos[i].pesadas,
    })),
    hojaVentasExternas: {
      destinos: despachosPorObra.externos.map((d, i) => ({
        ...d,
        detalle: detalleExternos[i].resumen,
        pesadas: detalleExternos[i].pesadas,
      })),
      resumen: despachosPorObra.externos,
    },
  }
}
