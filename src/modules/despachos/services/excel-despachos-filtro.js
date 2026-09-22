// Export "Exportar filtro a Excel" de Despachos (2026-09-22, pedido
// explícito de Federico): detalle completo de lo que matchea el filtro
// actual + fila(s) de TOTAL al pie — independiente del "Exportar informe
// mensual" que ya existe (excel-informe-mensual.js, ese arma un informe
// completo de un mes con hojas por obra; esto es un export plano de
// cualquier combinación de filtros, una sola hoja).
//
// Reusa el formato corporativo compartido (src/services/excel-corporativo.js
// — logo, encabezado, header violeta, zebra striping, pie institucional:
// memory/conventions.md, no reinventar el mismo Excel estilizado en cada
// módulo). No usa `exportarPlanillaCorporativa()` genérica porque esa no
// soporta una fila de TOTAL al pie — se arma la hoja a mano con los mismos
// helpers de estilo, mismo patrón que ya usa excel-informe-mensual.js.

import {
  estiloHeaderTabla,
  estiloCuerpo,
  estiloTotalGeneral,
  agregarEncabezadoCorporativo,
  agregarPieInstitucional,
  calcularAnchosAutoFit,
  descargarWorkbook,
  nombreArchivoConFecha,
  GRIS_SUAVE,
} from '@/services/excel-corporativo'

const COLUMNAS = ['Fecha', 'Obra / Cliente', 'Mezcla', 'Tipo', 'Pedido', 'Real', 'Diferencia']

function formatearCantidad(valor, tipo) {
  const unidad = tipo === 'hormigon' ? 'm³' : 'tn'
  return `${Number(valor || 0).toLocaleString('es-AR', { maximumFractionDigits: 2 })} ${unidad}`
}

function etiquetaTipo(tipo) {
  return tipo === 'hormigon' ? 'Hormigón' : 'Asfalto'
}

/**
 * @param {Array<object>} filas ya enriquecidas (destino/formulaNombre/diferencia
 *   ya resueltos, mismo shape que `filas` de useDespachos.js) — TODAS las que
 *   matchean el filtro, no una página.
 * @param {string} [resumenFiltros] línea legible de qué filtros estaban
 *   activos al exportar (ej. "Tipo: Asfalto · Obra: Predio Vialtec · Desde:
 *   2026-09-01"), para que el archivo quede autoexplicativo sin depender de
 *   que quien lo reciba haya visto la pantalla.
 */
export async function exportarDespachosFiltroExcel(filas, resumenFiltros) {
  const { default: ExcelJS } = await import('exceljs')
  const workbook = new ExcelJS.Workbook()
  workbook.creator = 'VialTec Plantas'
  workbook.created = new Date()
  const worksheet = workbook.addWorksheet('Despachos filtrados')

  const filasFormateadas = filas.map((f) => [
    f.fecha_programada,
    f.destino,
    f.formulaNombre,
    etiquetaTipo(f.tipo),
    formatearCantidad(f.cantidad_solicitada, f.tipo),
    formatearCantidad(f.cantidad_despachada, f.tipo),
    formatearCantidad(f.diferencia, f.tipo),
  ])

  const anchos = calcularAnchosAutoFit([COLUMNAS, ...filasFormateadas])
  worksheet.columns = anchos.map((w) => ({ width: w }))
  const ultimaCol = String.fromCharCode(64 + COLUMNAS.length)

  let fila = await agregarEncabezadoCorporativo(workbook, worksheet, 'Despachos — detalle del filtro', COLUMNAS.length)

  if (resumenFiltros) {
    worksheet.mergeCells(`A${fila}:${ultimaCol}${fila}`)
    const cell = worksheet.getCell(`A${fila}`)
    cell.value = `Filtros aplicados: ${resumenFiltros}`
    cell.font = { italic: true, size: 9, color: { argb: GRIS_SUAVE } }
    fila += 2
  }

  const filaHeader = fila
  const headerRow = worksheet.getRow(filaHeader)
  headerRow.values = COLUMNAS
  headerRow.height = 22
  headerRow.eachCell((cell) => estiloHeaderTabla(cell))
  worksheet.views = [{ state: 'frozen', ySplit: filaHeader }]

  fila = filaHeader + 1
  filasFormateadas.forEach((valores, i) => {
    const row = worksheet.getRow(fila)
    row.values = valores
    row.eachCell((cell) => estiloCuerpo(cell, i % 2 === 1))
    fila++
  })

  // Una fila de TOTAL por tipo presente (asfalto en tn, hormigón en m³ —
  // nunca se suman entre sí, mismo criterio que excel-informe-mensual.js).
  const tiposPresentes = [...new Set(filas.map((f) => f.tipo))]
  for (const tipo of tiposPresentes) {
    const subset = filas.filter((f) => f.tipo === tipo)
    const totalPedido = subset.reduce((acc, f) => acc + Number(f.cantidad_solicitada || 0), 0)
    const totalReal = subset.reduce((acc, f) => acc + Number(f.cantidad_despachada || 0), 0)
    const label = tiposPresentes.length > 1 ? `TOTAL ${etiquetaTipo(tipo).toUpperCase()}` : 'TOTAL'
    const row = worksheet.getRow(fila)
    row.values = [
      '',
      '',
      '',
      label,
      formatearCantidad(totalPedido, tipo),
      formatearCantidad(totalReal, tipo),
      formatearCantidad(totalPedido - totalReal, tipo),
    ]
    row.eachCell((cell) => estiloTotalGeneral(cell))
    fila++
  }

  agregarPieInstitucional(worksheet, fila - 1, COLUMNAS.length)
  await descargarWorkbook(workbook, nombreArchivoConFecha('Despachos-filtro'))
}
