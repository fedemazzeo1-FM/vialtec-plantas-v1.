// Constructor del workbook "Informe mensual de producción" — Despachos →
// Resumen por obra (roadmap Mobile + pedido de Federico, memory/pending.md
// 2026-09-02). Réplica de la estética del Excel de referencia que compartió
// Federico ("Informe Plantas prod. JULIO 2026.xlsx" — violeta #7C3AED para
// lo interno, verde para ventas externas/total general, logo VIAL-TEC arriba
// a la izquierda) pero 100% dinámico: recibe los datos ya armados por
// informe-mensual.service.js, ningún valor hardcodeado.
//
// Librería: `exceljs`, import DINÁMICO (no estático arriba — pesa ~945kB
// minificado, infla el chunk de Despachos si se importa al tope del
// archivo; ver excel-corporativo.js para el mismo criterio).
//
// Paleta/estilos (2026-09-03: extraídos a src/services/excel-corporativo.js
// como estándar para TODOS los Excel de la app, no solo este informe —
// antes vivían duplicados acá, memory/conventions.md) + pie institucional +
// "Fecha de exportación" en el encabezado.
//
// No incluye macros/VBA — ninguna librería JS puede escribir un
// vbaProject.bin válido (requiere Excel real para compilarlo). El botón de
// mail vive aparte, como macro de Excel instalada una sola vez por Federico
// (ver memory/pending.md — "Informe mensual: macro de mail" para el detalle
// y las instrucciones de instalación).

import logoVialtec from '@/assets/img/logo-vialtec.png'
import {
  GRIS_TEXTO,
  GRIS_SUAVE,
  BLANCO,
  estiloHeaderTabla,
  estiloSubtotal,
  estiloTotalGeneral,
  estiloBandaExterna,
  estiloCuerpo,
  agregarPieInstitucional,
} from '@/services/excel-corporativo'

const TN = (v) => (v ? `${Number(v).toFixed(2)} tn` : '—')
const M3 = (v) => (v ? `${Number(v).toFixed(1)} m³` : '—')
// Mismos valores que GRIS_TEXTO/GRIS_SUAVE de excel-corporativo.js, pero en
// formato #RRGGBB (canvas 2D no entiende ARGB de 8 dígitos) — no vale la
// pena una conversión genérica ARGB->CSS por 2 constantes usadas una vez
// (generarImagenGraficoAnual() más abajo).
const GRIS_TEXTO_HEX = '#374151'
const GRIS_SUAVE_HEX = '#9CA3AF'
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
  // Fix 2026-09-08 (reportado por Federico: "el logo está muy estirado",
  // después "un poco más grande, usando más la fila") — mismo criterio que
  // excel-corporativo.js: logo-vialtec.png mide 1348×583px real (ratio
  // ≈2.31:1). 102×44 mantiene esa proporción, más grande que el primer
  // ajuste (78×34) — la fila 1 de esta hoja también se agranda (ver
  // armarHojaResumenMensual) para que entre sin recortarse.
  worksheet.addImage(imageId, { tl: { col: 0, row: 0 }, ext: { width: 102, height: 44 } })
}

/**
 * Hoja "Resumen mensual": título, despachos por obra (interno + externo +
 * total general), consumo de insumos. Misma estructura que la hoja
 * homónima del Excel de referencia.
 */
function armarHojaResumenMensual(workbook, datos) {
  const ws = workbook.addWorksheet('Resumen mensual')
  ws.columns = [{ width: 5 }, { width: 42 }, { width: 13 }, { width: 20 }, { width: 18 }]
  ws.getRow(1).height = 50 // agrandada junto con el logo, ver agregarLogo()

  ws.mergeCells('A2:E2')
  ws.getCell('A2').value = `Informe mensual de producción — ${datos.mesLabel}`
  ws.getCell('A2').font = { bold: true, size: 14, color: { argb: GRIS_TEXTO } }
  ws.getRow(2).height = 24

  // Fecha de exportación (2026-09-03, pedido de Federico, extendido a todos
  // los Excel — ver excel-corporativo.js).
  ws.mergeCells('A3:E3')
  ws.getCell('A3').value = `Fecha de exportación: ${new Date().toLocaleString('es-AR')}`
  ws.getCell('A3').font = { italic: true, size: 9, color: { argb: GRIS_SUAVE } }

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

  agregarPieInstitucional(ws, fila, 5)

  return ws
}

/**
 * Gráfico de barras de producción mensual — imagen PNG dibujada en un
 * `<canvas>` del navegador (2026-09-07, pedido de Federico: "un gráfico de
 * barras... indicador de producción por mes" en Resumen Anual). `exceljs`
 * (4.4.0, confirmado contra la librería instalada) NO tiene API para crear
 * gráficos NATIVOS de Excel — la única forma de meter algo parecido a un
 * gráfico es como imagen, mismo mecanismo que ya usa el logo
 * (`workbook.addImage()`). Federico eligió esta opción sabiendo el
 * trade-off: es una FOTO fija, no editable/interactiva en Excel — si los
 * datos cambian hay que re-exportar el informe, mismo criterio que el resto
 * del reporte (100% dinámico en el momento del export).
 *
 * Depende de `document`/`canvas`, solo existe en el navegador — a
 * diferencia del resto de este archivo, esta función NO se puede probar
 * desde Node/vite-node (sin DOM). Se verificó con un test en un navegador
 * real en vez del harness de Node que se usa para el resto del informe.
 *
 * Orden CRONOLÓGICO (enero primero, izquierda a derecha) — a propósito
 * DISTINTO del orden de la tabla de arriba (más reciente primero, mismo
 * pedido de Federico): un gráfico de tendencia en el tiempo se lee de
 * izquierda a derecha, invertirlo confundiría la lectura. Por eso recibe
 * `datos.resumenAnual.filas` tal cual (ya viene ene->mes elegido de
 * fetchResumenAnual()), no la versión invertida que arma la tabla.
 *
 * @param {Array<{ mes: string, hormigonM3: number, asfaltoTn: number }>} filas
 * @returns {Promise<ArrayBuffer>} PNG listo para workbook.addImage()
 */
function generarImagenGraficoAnual(filas) {
  const ESCALA = 2 // resolución 2x — que no se vea pixelado al embeberlo más grande en la hoja
  const ANCHO = 900
  const ALTO = 380
  const MARGEN = { top: 55, right: 30, bottom: 55, left: 70 }
  const anchoGrafico = ANCHO - MARGEN.left - MARGEN.right
  const altoGrafico = ALTO - MARGEN.top - MARGEN.bottom

  const canvas = document.createElement('canvas')
  canvas.width = ANCHO * ESCALA
  canvas.height = ALTO * ESCALA
  const ctx = canvas.getContext('2d')
  ctx.scale(ESCALA, ESCALA)

  ctx.fillStyle = '#FFFFFF'
  ctx.fillRect(0, 0, ANCHO, ALTO)

  ctx.fillStyle = GRIS_TEXTO_HEX
  ctx.font = 'bold 15px Arial, sans-serif'
  ctx.fillText('Producción mensual', MARGEN.left, 24)

  // Leyenda (colores del acento oficial de la app — mismo criterio que el
  // resto del informe desde el fix de colores de esta sesión, no verde).
  const COLOR_HORMIGON = '#DDD6FE' // violeta claro (VIOLETA_CLARO)
  const COLOR_ASFALTO = '#7C3AED' // violeta (VIOLETA)
  const leyenda = [
    { color: COLOR_HORMIGON, texto: 'Hormigón (m³)' },
    { color: COLOR_ASFALTO, texto: 'Asfalto (tn)' },
  ]
  let xLeyenda = ANCHO - MARGEN.right - 220
  leyenda.forEach((l) => {
    ctx.fillStyle = l.color
    ctx.fillRect(xLeyenda, 12, 12, 12)
    ctx.fillStyle = GRIS_TEXTO_HEX
    ctx.font = '11px Arial, sans-serif'
    ctx.fillText(l.texto, xLeyenda + 16, 22)
    xLeyenda += 110
  })

  const maxValor = Math.max(1, ...filas.map((f) => Math.max(f.hormigonM3, f.asfaltoTn))) * 1.15
  const escalaY = altoGrafico / maxValor
  const baseY = MARGEN.top + altoGrafico

  // Gridlines horizontales + eje de valores.
  const pasos = 4
  ctx.strokeStyle = '#E5E7EB'
  ctx.fillStyle = GRIS_SUAVE_HEX
  ctx.font = '10px Arial, sans-serif'
  ctx.textAlign = 'right'
  for (let i = 0; i <= pasos; i++) {
    const valor = (maxValor * i) / pasos
    const y = baseY - valor * escalaY
    ctx.beginPath()
    ctx.moveTo(MARGEN.left, y)
    ctx.lineTo(MARGEN.left + anchoGrafico, y)
    ctx.stroke()
    ctx.fillText(Math.round(valor).toLocaleString('es-AR'), MARGEN.left - 8, y + 3)
  }

  // Barras (hormigón + asfalto, agrupadas por mes).
  const anchoGrupo = anchoGrafico / filas.length
  const anchoBarra = Math.min(22, anchoGrupo * 0.32)
  ctx.textAlign = 'center'
  filas.forEach((f, i) => {
    const xGrupo = MARGEN.left + i * anchoGrupo + anchoGrupo / 2
    const altoHormigon = f.hormigonM3 * escalaY
    const altoAsfalto = f.asfaltoTn * escalaY

    ctx.fillStyle = COLOR_HORMIGON
    ctx.fillRect(xGrupo - anchoBarra - 3, baseY - altoHormigon, anchoBarra, altoHormigon)
    ctx.fillStyle = COLOR_ASFALTO
    ctx.fillRect(xGrupo + 3, baseY - altoAsfalto, anchoBarra, altoAsfalto)

    // Mes abreviado (eje X) — "Enero 2026" -> "Ene".
    ctx.fillStyle = GRIS_TEXTO_HEX
    ctx.font = '11px Arial, sans-serif'
    ctx.fillText(f.mes.slice(0, 3), xGrupo, baseY + 18)
  })

  // Eje base.
  ctx.strokeStyle = GRIS_TEXTO_HEX
  ctx.beginPath()
  ctx.moveTo(MARGEN.left, baseY)
  ctx.lineTo(MARGEN.left + anchoGrafico, baseY)
  ctx.stroke()

  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (!blob) {
        reject(new Error('No se pudo generar la imagen del gráfico.'))
        return
      }
      blob.arrayBuffer().then(resolve, reject)
    }, 'image/png')
  })
}

/** Hoja "Resumen anual": acumulado mes a mes del año hasta el mes elegido. */
async function armarHojaResumenAnual(workbook, datos) {
  const ws = workbook.addWorksheet('Resumen anual')
  ws.columns = [{ width: 20 }, { width: 18 }, { width: 18 }]

  ws.mergeCells('A1:C1')
  ws.getCell('A1').value = `Informe Anual Enero–${datos.mesLabel}`
  ws.getCell('A1').font = { bold: true, size: 12, color: { argb: GRIS_TEXTO } }

  const header = ws.getRow(2)
  header.values = ['Mes', 'Hormigón (m³)', 'Asfalto (tn)']
  header.eachCell((cell) => estiloHeaderTabla(cell))

  // Orden 2026-09-07 (pedido de Federico): más reciente arriba, enero al
  // final — al revés del orden cronológico en que arma las filas
  // fetchResumenAnual() (ene->mes elegido, necesario ahí para que el
  // acumulado corrido tenga sentido). Se invierte solo para mostrar, no
  // afecta el cálculo de datos.resumenAnual.totalAcumulado (ya viene sumado
  // de antes, no depende del orden de iteración).
  let fila = 3
  ;[...datos.resumenAnual.filas].reverse().forEach((f) => {
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

  // Gráfico de barras (2026-09-07, pedido de Federico) — 2 filas de aire
  // después del total, mismo criterio de espaciado que "Consumo de
  // insumos" en armarHojaResumenMensual(). Si por lo que sea el navegador
  // no puede generar la imagen (ej. `canvas.toBlob` sin soporte), el resto
  // del informe se sigue generando igual, solo sin el gráfico — no vale la
  // pena que un problema puramente visual tire abajo todo el export.
  try {
    const imagenGrafico = await generarImagenGraficoAnual(datos.resumenAnual.filas)
    const imageId = workbook.addImage({ buffer: imagenGrafico, extension: 'png' })
    ws.addImage(imageId, { tl: { col: 0, row: fila + 1 }, ext: { width: 630, height: 266 } })
  } catch (e) {
    // sin gráfico, sin romper el resto del informe (ver comentario de arriba)
  }

  return ws
}

/**
 * Hoja "Analítica de Proveedores" (2026-09-03, pedido de Federico — sumarla
 * al informe mensual). Formato tabular plano (proveedor+insumo por fila,
 * no las cards agrupadas de la UI de Stock) — más útil para filtrar/
 * pivotear en Excel, mismo criterio que ya usa exportarProveedoresExcel()
 * en useStock.js.
 */
function armarHojaProveedores(workbook, datos) {
  const ws = workbook.addWorksheet('Analítica de Proveedores')
  ws.columns = [{ width: 30 }, { width: 24 }, { width: 10 }, { width: 14 }]

  ws.mergeCells('A1:D1')
  ws.getCell('A1').value = `Analítica de proveedores — ${datos.mesLabel}`
  ws.getCell('A1').font = { bold: true, size: 13, color: { argb: GRIS_TEXTO } }

  const header = ws.getRow(2)
  header.values = ['Proveedor', 'Insumo', 'Viajes', 'Toneladas']
  header.eachCell((cell) => estiloHeaderTabla(cell))

  let fila = 3
  let totalViajes = 0
  let totalTn = 0
  datos.analiticaProveedores.forEach((p) => {
    p.insumos.forEach((i) => {
      const row = ws.getRow(fila)
      row.values = [p.proveedor, i.material, i.viajes, Number(i.toneladas.toFixed(2))]
      row.eachCell((cell) => estiloCuerpo(cell))
      totalViajes += i.viajes
      totalTn += i.toneladas
      fila++
    })
  })

  if (!datos.analiticaProveedores.length) {
    ws.mergeCells(`A${fila}:D${fila}`)
    ws.getCell(`A${fila}`).value = 'Sin ingresos de proveedores registrados en el mes.'
    ws.getCell(`A${fila}`).font = { italic: true, size: 10, color: { argb: GRIS_SUAVE } }
    fila++
  } else {
    const total = ws.getRow(fila)
    total.values = ['TOTAL', '', totalViajes, Number(totalTn.toFixed(2))]
    total.eachCell((cell) => estiloSubtotal(cell))
    fila++
  }

  agregarPieInstitucional(ws, fila - 1, 4)

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
  filasDetalle.forEach((d) => {
    const row = ws.getRow(fila)
    row.values = [FECHA(d.fecha), d.mezcla, d.tipo, d.pedido, d.real, d.unidad, d.nroRemito, d.nroVale, d.encargado, d.notas]
    row.eachCell((cell) => estiloCuerpo(cell))
    fila++
  })

  // Fix 2026-09-07 (revisión general pedida por Federico): un mismo destino
  // (obra o cliente externo) puede recibir asfalto Y hormigón en el mismo
  // mes — antes se sumaban `real` de las dos en una sola variable, mezclando
  // tn con m³ en un solo "TOTAL" sin sentido (y la unidad mostrada era la de
  // la ÚLTIMA fila nomás, no la de la suma). Ahora se totaliza por tipo —
  // una fila "TOTAL ASFALTO"/"TOTAL HORMIGÓN" por cada uno que tenga al
  // menos un despacho ese mes (el caso más común, un solo tipo, sigue
  // viéndose como una sola fila de total, igual que antes).
  const tipos = [...new Set(filasDetalle.map((d) => d.tipo))]
  tipos.forEach((tipo) => {
    const delTipo = filasDetalle.filter((d) => d.tipo === tipo)
    const totalReal = delTipo.reduce((acc, d) => acc + d.real, 0)
    const total = ws.getRow(fila)
    total.getCell(1).value = tipos.length > 1 ? `TOTAL ${tipo.toUpperCase()}` : 'TOTAL'
    total.getCell(3).value = `${delTipo.length} desp.`
    total.getCell(5).value = Number(totalReal.toFixed(2))
    total.getCell(6).value = delTipo[0]?.unidad ?? ''
    ;[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].forEach((c) => estiloSubtotal(total.getCell(c)))
    fila++
  })

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
export async function construirWorkbookInformeMensual(datos, logoBuffer) {
  const { default: ExcelJS } = await import('exceljs')
  const workbook = new ExcelJS.Workbook()
  workbook.creator = 'VialTec Plantas'
  workbook.created = new Date()

  const hojaResumen = armarHojaResumenMensual(workbook, datos)
  agregarLogo(workbook, hojaResumen, logoBuffer)
  await armarHojaResumenAnual(workbook, datos)
  armarHojaProveedores(workbook, datos)

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
  const workbook = await construirWorkbookInformeMensual(datos, logoBuffer)

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
