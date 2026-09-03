// Constructor del workbook "Informe mensual de producción" — Despachos →
// Resumen por obra (roadmap Mobile + pedido de Federico, memory/pending.md
// 2026-09-02). Réplica de la estética del Excel de referencia que compartió
// Federico ("Informe Plantas prod. JULIO 2026.xlsx" — violeta #7C3AED para
// lo interno, verde para ventas externas/total general, logo VIAL-TEC arriba
// a la izquierda) pero 100% dinámico: recibe los datos ya armados por
// informe-mensual.service.js, ningún valor hardcodeado.
//
// Librería: `exceljs` (no `xlsx`/SheetJS que ya usa el resto de la app) —
// la Community Edition de SheetJS no soporta ESCRIBIR estilos (fills/fonts/
// merges), solo leerlos; para un informe con este nivel de diseño hacía
// falta una librería que sí lo soporte del lado del cliente. `xlsx` sigue
// siendo la elegida para los exports lisos de Báscula/Stock (no lo
// justifica ahí, evita cargar 2 librerías pesadas para lo mismo).
//
// No incluye macros/VBA — ninguna librería JS puede escribir un
// vbaProject.bin válido (requiere Excel real para compilarlo). El botón de
// mail vive aparte, como macro de Excel instalada una sola vez por Federico
// (ver memory/pending.md — "Informe mensual: macro de mail" para el detalle
// y las instrucciones de instalación).

import ExcelJS from 'exceljs'
import logoVialtec from '@/assets/img/logo-vialtec.png'

// Paleta calcada del Excel de referencia (getComputedStyle-equivalente:
// leído directo de los estilos del .xlsx de julio, no a ojo).
const VIOLETA = 'FF7C3AED'
const VIOLETA_CLARO = 'FFDDD6FE'
const VERDE_BANDA = 'FF92D050'
const VERDE_TOTAL = 'FF00B050'
const GRIS_TEXTO = 'FF374151'
const GRIS_SUAVE = 'FF9CA3AF'
const BLANCO = 'FFFFFFFF'

function aplicarFill(cell, argb) {
  cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb } }
}

function estiloHeaderTabla(cell) {
  aplicarFill(cell, VIOLETA)
  cell.font = { bold: true, color: { argb: BLANCO }, size: 11 }
  cell.alignment = { horizontal: 'center', vertical: 'middle' }
}

function estiloSubtotal(cell) {
  aplicarFill(cell, VIOLETA_CLARO)
  cell.font = { bold: true, color: { argb: VIOLETA }, size: 10 }
}

function estiloTotalGeneral(cell, size = 10) {
  aplicarFill(cell, VERDE_TOTAL)
  cell.font = { bold: true, color: { argb: BLANCO }, size }
}

function estiloBandaExterna(cell) {
  aplicarFill(cell, VERDE_BANDA)
  cell.font = { bold: true, color: { argb: BLANCO }, size: 11 }
}

function estiloCuerpo(cell) {
  cell.font = { color: { argb: GRIS_TEXTO }, size: 10 }
}

const TN = (v) => (v ? `${Number(v).toFixed(2)} tn` : '—')
const M3 = (v) => (v ? `${Number(v).toFixed(1)} m³` : '—')
// 'YYYY-MM-DD' (formato crudo de fecha_programada, columna `date` en
// Supabase) -> 'DD/MM/YYYY' (mismo formato que el Excel de referencia de
// Federico) — sin esto salía la fecha ISO cruda en la hoja de detalle.
const FECHA = (iso) => {
  if (!iso) return ''
  const [anio, mes, dia] = iso.split('-')
  return `${dia}/${mes}/${anio}`
}

function agregarLogo(workbook, worksheet, logoBuffer) {
  const imageId = workbook.addImage({ buffer: logoBuffer, extension: 'png' })
  worksheet.addImage(imageId, { tl: { col: 0, row: 0 }, ext: { width: 180, height: 34 } })
}

/**
 * Hoja "Resumen mensual": título, despachos por obra (interno + externo +
 * total general), consumo de insumos. Misma estructura que la hoja
 * homónima del Excel de referencia.
 */
function armarHojaResumenMensual(workbook, datos) {
  const ws = workbook.addWorksheet('Resumen mensual')
  ws.columns = [{ width: 5 }, { width: 42 }, { width: 13 }, { width: 20 }, { width: 18 }]
  ws.getRow(1).height = 40

  ws.mergeCells('A2:E2')
  ws.getCell('A2').value = `Informe mensual de producción — ${datos.mesLabel}`
  ws.getCell('A2').font = { bold: true, size: 14, color: { argb: GRIS_TEXTO } }
  ws.getRow(2).height = 24

  let fila = 4
  ws.mergeCells(`A${fila}:E${fila}`)
  ws.getCell(`A${fila}`).value = '  Despachos por obra'
  ;['A', 'B', 'C', 'D', 'E'].forEach((c) => estiloSubtotal(ws.getCell(`${c}${fila}`)))
  fila++

  const headerRow = ws.getRow(fila)
  headerRow.values = ['N°', 'Obra', 'Despachos', 'Hormigón (m³)', 'Asfalto (tn)']
  headerRow.eachCell((cell) => estiloHeaderTabla(cell))
  fila++

  datos.despachosPorObra.internos.forEach((r, i) => {
    const row = ws.getRow(fila)
    row.values = [i + 1, r.nombre, r.cantidadDespachos, M3(r.hormigonM3), TN(r.asfaltoTn)]
    row.eachCell((cell) => estiloCuerpo(cell))
    fila++
  })

  const subInt = ws.getRow(fila)
  subInt.values = [
    null,
    'Subtotal interno',
    datos.despachosPorObra.subtotalInterno.despachos,
    M3(datos.despachosPorObra.subtotalInterno.hormigonM3),
    TN(datos.despachosPorObra.subtotalInterno.asfaltoTn),
  ]
  subInt.eachCell((cell) => estiloSubtotal(cell))
  fila++

  const bandaExt = ws.getRow(fila)
  bandaExt.values = ['  Ventas externas', null, null, 'Hormigón (m³)', 'Asfalto (tn)']
  bandaExt.eachCell((cell) => estiloBandaExterna(cell))
  fila++

  const nInternos = datos.despachosPorObra.internos.length
  datos.despachosPorObra.externos.forEach((r, i) => {
    const row = ws.getRow(fila)
    row.values = [nInternos + i + 1, r.nombre, r.cantidadDespachos, M3(r.hormigonM3), TN(r.asfaltoTn)]
    row.eachCell((cell) => estiloCuerpo(cell))
    fila++
  })

  const subExt = ws.getRow(fila)
  subExt.values = [
    null,
    'Subtotal externo',
    datos.despachosPorObra.subtotalExterno.despachos,
    M3(datos.despachosPorObra.subtotalExterno.hormigonM3),
    TN(datos.despachosPorObra.subtotalExterno.asfaltoTn),
  ]
  subExt.eachCell((cell) => estiloSubtotal(cell))
  fila++

  const total = ws.getRow(fila)
  total.values = [
    null,
    'TOTAL GENERAL',
    datos.despachosPorObra.totalGeneral.despachos,
    M3(datos.despachosPorObra.totalGeneral.hormigonM3),
    TN(datos.despachosPorObra.totalGeneral.asfaltoTn),
  ]
  total.eachCell((cell) => estiloTotalGeneral(cell, 12))
  fila += 2

  ws.mergeCells(`A${fila}:E${fila}`)
  ws.getCell(`A${fila}`).value = '  Consumo de insumos'
  ;['A', 'B', 'C', 'D', 'E'].forEach((c) => estiloSubtotal(ws.getCell(`${c}${fila}`)))
  fila++

  const headerInsumos = ws.getRow(fila)
  headerInsumos.getCell(1).value = 'N°'
  headerInsumos.getCell(2).value = 'Insumo'
  headerInsumos.getCell(3).value = 'Consumo (tn)'
  ;[1, 2, 3].forEach((c) => estiloHeaderTabla(headerInsumos.getCell(c)))
  fila++

  datos.consumoInsumos.filas.forEach((f, i) => {
    const row = ws.getRow(fila)
    row.getCell(1).value = i + 1
    row.getCell(2).value = f.material
    row.getCell(3).value = TN(f.toneladas)
    ;[1, 2, 3].forEach((c) => estiloCuerpo(row.getCell(c)))
    fila++
  })

  const totalInsumos = ws.getRow(fila)
  totalInsumos.getCell(2).value = 'TOTAL'
  totalInsumos.getCell(3).value = TN(datos.consumoInsumos.totalTn)
  ;[1, 2, 3].forEach((c) => estiloSubtotal(totalInsumos.getCell(c)))

  return ws
}

/** Hoja "Resumen anual": acumulado mes a mes del año hasta el mes elegido. */
function armarHojaResumenAnual(workbook, datos) {
  const ws = workbook.addWorksheet('Resumen anual')
  ws.columns = [{ width: 20 }, { width: 18 }, { width: 18 }]

  ws.mergeCells('A1:C1')
  ws.getCell('A1').value = `Informe Anual Enero–${datos.mesLabel}`
  ws.getCell('A1').font = { bold: true, size: 12, color: { argb: GRIS_TEXTO } }

  const header = ws.getRow(2)
  header.values = ['Mes', 'Hormigón (m³)', 'Asfalto (tn)']
  header.eachCell((cell) => estiloHeaderTabla(cell))

  let fila = 3
  datos.resumenAnual.filas.forEach((f) => {
    const row = ws.getRow(fila)
    row.values = [f.mes, M3(f.hormigonM3), TN(f.asfaltoTn)]
    row.getCell(1).font = { color: { argb: GRIS_SUAVE }, size: 10 }
    row.getCell(2).font = { color: { argb: GRIS_TEXTO }, size: 10 }
    row.getCell(3).font = { color: { argb: GRIS_TEXTO }, size: 10 }
    fila++
  })

  const total = ws.getRow(fila)
  total.values = ['TOTAL ACUMULADO', M3(datos.resumenAnual.totalAcumulado.hormigonM3), TN(datos.resumenAnual.totalAcumulado.asfaltoTn)]
  total.eachCell((cell) => estiloHeaderTabla(cell))

  return ws
}

/** Una hoja por destino (obra interna o cliente externo) con el detalle de vales/remitos/entregas. */
function armarHojaDestino(workbook, nombre, mesLabel, filasDetalle) {
  // Nombre de hoja: Excel limita a 31 caracteres y prohíbe : \ / ? * [ ].
  const nombreHoja = nombre.replace(/[:\\/?*[\]]/g, ' ').slice(0, 31)
  const ws = workbook.addWorksheet(nombreHoja)
  ws.columns = [
    { width: 12 }, { width: 24 }, { width: 10 }, { width: 10 }, { width: 10 },
    { width: 8 }, { width: 14 }, { width: 16 }, { width: 18 }, { width: 30 },
  ]

  ws.mergeCells('A1:J1')
  ws.getCell('A1').value = nombre
  ws.getCell('A1').font = { bold: true, size: 13, color: { argb: GRIS_TEXTO } }
  ws.mergeCells('A2:J2')
  ws.getCell('A2').value = `Despachos — ${mesLabel}`
  ws.getCell('A2').font = { italic: true, size: 10, color: { argb: GRIS_SUAVE } }

  const header = ws.getRow(3)
  header.values = ['Fecha', 'Mezcla', 'Tipo', 'Pedido', 'Real', 'Unidad', 'N° Remito', 'N° Vale', 'Encargado', 'Notas']
  header.eachCell((cell) => estiloHeaderTabla(cell))

  let fila = 4
  let totalReal = 0
  let unidad = 'tn'
  filasDetalle.forEach((d) => {
    const row = ws.getRow(fila)
    row.values = [FECHA(d.fecha), d.mezcla, d.tipo, d.pedido, d.real, d.unidad, d.nroRemito, d.nroVale, d.encargado, d.notas]
    row.eachCell((cell) => estiloCuerpo(cell))
    totalReal += d.real
    unidad = d.unidad
    fila++
  })

  const total = ws.getRow(fila)
  total.getCell(1).value = 'TOTAL'
  total.getCell(3).value = `${filasDetalle.length} desp.`
  total.getCell(5).value = Number(totalReal.toFixed(2))
  total.getCell(6).value = unidad
  ;[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].forEach((c) => estiloSubtotal(total.getCell(c)))

  return ws
}

/**
 * Arma el workbook completo (sin efectos de lado: no toca `document` ni
 * `fetch`) — separado de generarInformeMensualExcel() de más abajo para
 * poder testearlo desde Node/CLI sin navegador (ver scripts/test-informe-
 * mensual.mjs, usado durante el desarrollo de esta función).
 * @param {Awaited<ReturnType<import('./informe-mensual.service').fetchDatosInformeMensual>>} datos
 * @param {ArrayBuffer} logoBuffer bytes del logo (PNG) ya leídos
 */
export function construirWorkbookInformeMensual(datos, logoBuffer) {
  const workbook = new ExcelJS.Workbook()
  workbook.creator = 'VialTec Plantas'
  workbook.created = new Date()

  const hojaResumen = armarHojaResumenMensual(workbook, datos)
  agregarLogo(workbook, hojaResumen, logoBuffer)
  armarHojaResumenAnual(workbook, datos)

  for (const destino of datos.hojasInternas) {
    const filas = destino.detalle.map((d) => ({ ...d, mezcla: d.mezcla ?? '—' }))
    armarHojaDestino(workbook, destino.nombre, datos.mesLabel, filas)
  }

  if (datos.hojaVentasExternas.destinos.length) {
    const wsVentas = workbook.addWorksheet('Ventas Externas')
    wsVentas.columns = [{ width: 5 }, { width: 40 }, { width: 12 }, { width: 20 }, { width: 18 }]
    wsVentas.mergeCells('A1:E1')
    wsVentas.getCell('A1').value = `Ventas Externas — ${datos.mesLabel}`
    wsVentas.getCell('A1').font = { bold: true, size: 13, color: { argb: GRIS_TEXTO } }
    wsVentas.mergeCells('A2:E2')
    const nClientes = datos.hojaVentasExternas.destinos.length
    const nDespachos = datos.despachosPorObra.subtotalExterno.despachos
    wsVentas.getCell('A2').value = `${nDespachos} despacho${nDespachos === 1 ? '' : 's'} — ${nClientes} cliente${nClientes === 1 ? '' : 's'}`
    wsVentas.getCell('A2').font = { italic: true, size: 10, color: { argb: GRIS_SUAVE } }

    const header = wsVentas.getRow(3)
    header.values = ['N°', 'Cliente', 'Despachos', 'Hormigón (m³)', 'Asfalto (tn)']
    header.eachCell((cell) => estiloHeaderTabla(cell))

    let fila = 4
    datos.despachosPorObra.externos.forEach((r, i) => {
      const row = wsVentas.getRow(fila)
      row.values = [i + 1, r.nombre, r.cantidadDespachos, M3(r.hormigonM3), TN(r.asfaltoTn)]
      row.eachCell((cell) => estiloCuerpo(cell))
      fila++
    })
    const total = wsVentas.getRow(fila)
    total.values = [
      null,
      'TOTAL',
      datos.despachosPorObra.subtotalExterno.despachos,
      M3(datos.despachosPorObra.subtotalExterno.hormigonM3),
      TN(datos.despachosPorObra.subtotalExterno.asfaltoTn),
    ]
    total.eachCell((cell) => estiloSubtotal(cell))

    // Una hoja por cliente externo, mismo formato que las obras internas.
    for (const destino of datos.hojaVentasExternas.destinos) {
      const filas = destino.detalle.map((d) => ({ ...d, mezcla: d.mezcla ?? '—' }))
      armarHojaDestino(workbook, destino.nombre, datos.mesLabel, filas)
    }
  }

  return workbook
}

/**
 * Punto de entrada real usado por la vista: arma el workbook (arriba) y
 * dispara la descarga en el navegador.
 * @param {Awaited<ReturnType<import('./informe-mensual.service').fetchDatosInformeMensual>>} datos
 */
export async function generarInformeMensualExcel(datos) {
  const resp = await fetch(logoVialtec)
  const logoBuffer = await resp.arrayBuffer()
  const workbook = construirWorkbookInformeMensual(datos, logoBuffer)

  const buffer = await workbook.xlsx.writeBuffer()
  const blob = new Blob([buffer], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `Informe Plantas prod. ${datos.mesLabel.toUpperCase()}.xlsx`
  document.body.appendChild(a)
  a.click()
  a.remove()
  URL.revokeObjectURL(url)
}
