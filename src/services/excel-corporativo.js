// Formato corporativo unificado para TODOS los Excel exportados por la app
// (pedido de Federico, 2026-09-03: "encabezados con estilo profesional de
// colores, incluir el logo, pie institucional en todos") — helper
// transversal (memory/conventions.md) para no repetir la misma paleta/logo/
// pie en cada export. Paleta calcada del Excel de referencia que Federico
// compartió para el informe mensual ("ese formato me gusta mucho") — se
// extiende como estándar a Báscula/Stock/Despachos en vez de inventar una
// paleta nueva para cada export.
//
// Librería: `exceljs` (no `xlsx`/SheetJS) — la Community Edition de SheetJS
// no soporta ESCRIBIR estilos (fills/fonts/merges), solo leerlos, así que no
// alcanza para "encabezados con estilo profesional de colores" ni logo
// embebido. Los exports que antes usaban `xlsx` (Báscula, Stock) migran acá.
//
// Import DINÁMICO de exceljs (no estático arriba): pesa ~945kB minificado —
// un import estático lo metería en el bundle de CUALQUIER vista que solo
// referencie este archivo (mismo problema ya resuelto para `xlsx` en
// Báscula/Stock, y para este mismo `exceljs` en excel-informe-mensual.js).
// Solo `exportarPlanillaCorporativa()` (el entry point real) lo necesita —
// el resto de las funciones de acá reciben workbook/worksheet/cell ya
// creados como parámetro, no importan la librería ellas mismas.

import logoVialtec from '@/assets/img/logo-vialtec.png'

export const VIOLETA = 'FF7C3AED'
export const VIOLETA_CLARO = 'FFDDD6FE'
// Variante oscura del mismo violeta (2026-09-07, pedido de Federico —
// Informe Mensual: "cambiá el verde de los títulos por tonos del acento
// oficial de la app"). Reemplaza a VERDE_BANDA/VERDE_TOTAL, que quedaban
// fuera de la identidad visual (verde no forma parte de la paleta de la
// app, ver tailwind.config.js). Solo la usa el Informe Mensual
// (estiloBandaExterna/estiloTotalGeneral) — no toca el violeta de
// encabezado/subtotal que ya usan Stock/Báscula/el resto de los exports,
// para no cambiarles el color sin que lo hayan pedido.
export const VIOLETA_OSCURO = 'FF5D2CB2'
export const GRIS_TEXTO = 'FF374151'
export const GRIS_SUAVE = 'FF9CA3AF'
export const BLANCO = 'FFFFFFFF'

function aplicarFill(cell, argb) {
  cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb } }
}

const BORDE_FINO = { style: 'thin', color: { argb: 'FFE5E7EB' } }
const BORDE_CELDA = { top: BORDE_FINO, bottom: BORDE_FINO, left: BORDE_FINO, right: BORDE_FINO }

export function estiloHeaderTabla(cell) {
  aplicarFill(cell, VIOLETA)
  cell.font = { bold: true, color: { argb: BLANCO }, size: 11 }
  cell.alignment = { horizontal: 'center', vertical: 'middle', wrapText: true }
  cell.border = BORDE_CELDA
}

export function estiloSubtotal(cell) {
  aplicarFill(cell, VIOLETA_CLARO)
  cell.font = { bold: true, color: { argb: VIOLETA }, size: 10 }
}

export function estiloTotalGeneral(cell, size = 10) {
  aplicarFill(cell, VIOLETA_OSCURO)
  cell.font = { bold: true, color: { argb: BLANCO }, size }
}

export function estiloBandaExterna(cell) {
  aplicarFill(cell, VIOLETA)
  cell.font = { bold: true, color: { argb: BLANCO }, size: 11 }
}

export function estiloCuerpo(cell, esPar = false) {
  cell.font = { color: { argb: GRIS_TEXTO }, size: 10 }
  cell.border = BORDE_CELDA
  // Zebra striping (2026-09-03, pedido de Federico: "bien profesionales y
  // estéticos") — filas pares con un gris muy claro, impares blancas; hace
  // mucho más legible una tabla larga sin depender de bordes solos.
  if (esPar) aplicarFill(cell, 'FFF9FAFB')
}

let logoBufferCache = null

/** Bytes del logo — se cachea en memoria, todos los exports de una misma sesión de navegador lo reusan sin re-descargarlo. */
export async function obtenerLogoBuffer() {
  if (!logoBufferCache) {
    const resp = await fetch(logoVialtec)
    logoBufferCache = await resp.arrayBuffer()
  }
  return logoBufferCache
}

/**
 * Encabezado corporativo: logo arriba a la izquierda + título de la
 * planilla + "Fecha de exportación" (pedido explícito de Federico para el
 * Excel de Stock, extendido acá a todos). Devuelve la fila donde puede
 * empezar el contenido de la tabla (después del encabezado + una fila en
 * blanco de separación).
 * @param {ExcelJS.Workbook} workbook
 * @param {ExcelJS.Worksheet} worksheet
 * @param {string} titulo
 * @param {number} columnasAnchoTotal cantidad de columnas a mergear para el título (ancho de la tabla)
 * @returns {Promise<number>} número de fila (1-indexed) donde sigue el contenido
 */
export async function agregarEncabezadoCorporativo(workbook, worksheet, titulo, columnasAnchoTotal) {
  const logoBuffer = await obtenerLogoBuffer()
  const imageId = workbook.addImage({ buffer: logoBuffer, extension: 'png' })
  // Fix 2026-09-08 (reportado por Federico: "el logo está muy estirado" en
  // todos los excel): src/assets/img/logo-vialtec.png mide 1348×583px real
  // (ratio ≈2.31:1) — el width:160/height:30 de antes (ratio 5.33:1) lo
  // aplastaba verticalmente bien distinto a como se ve en la app. 70×30
  // mantiene el mismo alto de fila que ya usaba el resto del layout, con la
  // proporción real del archivo (ratio 2.33:1, indistinguible a ojo de la
  // real). Como esta función es EL único lugar donde se inserta el logo
  // (agregarEncabezadoCorporativo, usado por todos los exports), corrige
  // el problema en todos los excel de una sola vez.
  worksheet.addImage(imageId, { tl: { col: 0, row: 0 }, ext: { width: 70, height: 30 } })
  worksheet.getRow(1).height = 34

  const ultimaCol = String.fromCharCode(64 + columnasAnchoTotal) // 1->A, 2->B...
  worksheet.mergeCells(`A2:${ultimaCol}2`)
  worksheet.getCell('A2').value = titulo
  worksheet.getCell('A2').font = { bold: true, size: 14, color: { argb: GRIS_TEXTO } }
  worksheet.getRow(2).height = 22

  worksheet.mergeCells(`A3:${ultimaCol}3`)
  worksheet.getCell('A3').value = `Fecha de exportación: ${new Date().toLocaleString('es-AR')}`
  worksheet.getCell('A3').font = { italic: true, size: 9, color: { argb: GRIS_SUAVE } }

  return 5 // fila 4 queda en blanco de separación, el contenido sigue en la 5
}

/**
 * Pie institucional (pedido explícito de Federico, en todos los Excel):
 * "Sistema de gestión de plantas de producción" + fecha, mergeado al ancho
 * de la tabla, 2 filas después de la última fila de contenido.
 * @param {ExcelJS.Worksheet} worksheet
 * @param {number} filaContenido última fila con datos de la tabla
 * @param {number} columnasAnchoTotal
 */
export function agregarPieInstitucional(worksheet, filaContenido, columnasAnchoTotal) {
  const fila = filaContenido + 2
  const ultimaCol = String.fromCharCode(64 + columnasAnchoTotal)
  worksheet.mergeCells(`A${fila}:${ultimaCol}${fila}`)
  const cell = worksheet.getCell(`A${fila}`)
  cell.value = 'VialTec Plantas — Sistema de gestión de plantas de producción'
  cell.font = { italic: true, size: 8, color: { argb: GRIS_SUAVE } }
  cell.alignment = { horizontal: 'center' }
}

/** Dispara la descarga del workbook en el navegador — mismo mecanismo en todos los exports, no duplicado. */
export async function descargarWorkbook(workbook, nombreArchivo) {
  const buffer = await workbook.xlsx.writeBuffer()
  const blob = new Blob([buffer], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = nombreArchivo
  document.body.appendChild(a)
  a.click()
  a.remove()
  URL.revokeObjectURL(url)
}

/** 'YYYY-MM-DD' de hoy, para nombres de archivo consistentes entre exports. */
export function nombreArchivoConFecha(base) {
  const hoy = new Date().toISOString().slice(0, 10)
  return `${base}-${hoy}.xlsx`
}

/**
 * Export genérico de una o más hojas tabulares con el formato corporativo
 * completo (logo + título + fecha de exportación + header violeta + pie
 * institucional) — reemplaza a exportarExcel() de src/services/excel-export.js
 * (SheetJS, sin soporte de estilos) para cualquier export nuevo. Mismo
 * shape de columnas `{key, label, format?}` que ya usan VTable.vue y el
 * export viejo, para no tener que reaprender una convención nueva por
 * pantalla.
 * @param {string} nombreArchivo
 * @param {Array<{ nombre: string, titulo?: string, columnas: Array<{key,label,format?}>, filas: Array<object> }>} hojas
 */
export async function exportarPlanillaCorporativa(nombreArchivo, hojas) {
  const { default: ExcelJS } = await import('exceljs')
  const workbook = new ExcelJS.Workbook()
  workbook.creator = 'VialTec Plantas'
  workbook.created = new Date()

  for (const hoja of hojas) {
    const worksheet = workbook.addWorksheet(hoja.nombre.slice(0, 31))

    // Filas formateadas primero (se necesitan para calcular el ancho de
    // columna por contenido real, no solo por el largo del label — evita
    // columnas angostas con texto cortado, que se ve poco prolijo).
    const filasFormateadas = hoja.filas.map((f) =>
      hoja.columnas.map((c) => (c.format ? c.format(f[c.key], f) : (f[c.key] ?? '')))
    )
    worksheet.columns = hoja.columnas.map((c, i) => ({
      width: Math.min(
        40,
        Math.max(c.label.length, 10, ...filasFormateadas.slice(0, 300).map((r) => String(r[i] ?? '').length)) + 2
      ),
    }))

    const filaHeader = await agregarEncabezadoCorporativo(
      workbook,
      worksheet,
      hoja.titulo || hoja.nombre,
      hoja.columnas.length
    )

    const headerRow = worksheet.getRow(filaHeader)
    headerRow.values = hoja.columnas.map((c) => c.label)
    headerRow.height = 22
    headerRow.eachCell((cell) => estiloHeaderTabla(cell))
    // Encabezado congelado (2026-09-03, "bien profesional") — al scrollear
    // una tabla larga en Excel, el título de columna sigue visible.
    worksheet.views = [{ state: 'frozen', ySplit: filaHeader }]

    let fila = filaHeader + 1
    filasFormateadas.forEach((valores, i) => {
      const row = worksheet.getRow(fila)
      row.values = valores
      row.eachCell((cell) => estiloCuerpo(cell, i % 2 === 1))
      fila++
    })

    agregarPieInstitucional(worksheet, fila - 1, hoja.columnas.length)
  }

  await descargarWorkbook(workbook, nombreArchivo)
}
