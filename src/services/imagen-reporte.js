// Rasteriza un elemento del DOM a PNG y lo copia/descarga (2026-10-01, reporte
// ejecutivo para el cuerpo del mail — ReporteEjecutivoMensual.vue). Mismo
// html2canvas/jspdf que pdf-imprimible.js. Se importa de forma dinámica desde
// el composable que lo usa, para no sumar estas librerías al chunk de la vista.

import html2canvas from 'html2canvas'
import { jsPDF } from 'jspdf'

/** Espera a que las <img> (el logo) terminen de cargar antes de rasterizar. */
function esperarImagenes(el) {
  return Promise.all(
    Array.from(el.querySelectorAll('img')).map(
      (img) =>
        img.complete ||
        new Promise((resolve) => {
          img.addEventListener('load', resolve, { once: true })
          img.addEventListener('error', resolve, { once: true })
        })
    )
  )
}

/**
 * @param {HTMLElement} el ya renderizado (puede estar fuera de pantalla, no `display: none`).
 * @param {{ escala?: number }} opciones escala 3 = alta resolución, nítido en pantallas retina y al imprimir.
 * @returns {Promise<{ blob: Blob, ancho: number, alto: number }>} tamaño en px de la imagen.
 */
export async function capturarElementoPng(el, { escala = 3 } = {}) {
  await esperarImagenes(el)
  if (document.fonts?.ready) await document.fonts.ready
  // El reset de Tailwind (`img { display: block }`) hace que html2canvas
  // dibuje TODO el texto unos píxeles más abajo de su lugar. Se neutraliza
  // solo durante la captura.
  const ajuste = document.createElement('style')
  ajuste.textContent = 'img { display: inline-block !important; }'
  document.head.appendChild(ajuste)
  let canvas
  try {
    canvas = await html2canvas(el, { scale: escala, backgroundColor: '#ffffff', useCORS: true })
  } finally {
    ajuste.remove()
  }
  const blob = await new Promise((resolve, reject) => {
    canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('No se pudo generar la imagen.'))), 'image/png')
  })
  return { blob, ancho: canvas.width, alto: canvas.height }
}

/** El navegador puede copiar imágenes al portapapeles (Chrome/Edge/Safari; Firefox no). */
export function puedeCopiarImagen() {
  return typeof window !== 'undefined' && 'ClipboardItem' in window && !!navigator.clipboard?.write
}

export async function copiarImagenAlPortapapeles(blob) {
  await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })])
}

/**
 * Copia las imágenes juntas, una debajo de la otra, como HTML con cada PNG
 * embebido: Gmail/Outlook las pegan de una sola vez en el cuerpo del mail (el
 * portapapeles guarda una sola imagen suelta por vez).
 * @param {Array<{ blob: Blob, ancho: number, titulo: string }>} imagenes
 * @param {number} escala la misma de capturarElementoPng, para mostrarlas a su tamaño de pantalla.
 */
export async function copiarImagenesComoHtml(imagenes, { escala = 3 } = {}) {
  const partes = []
  for (const img of imagenes) {
    const ancho = Math.round(img.ancho / escala)
    partes.push(`<p><img src="${await blobADataUrl(img.blob)}" alt="${img.titulo}" width="${ancho}" style="max-width:100%;height:auto"></p>`)
  }
  const html = partes.join('')
  await navigator.clipboard.write([
    new ClipboardItem({
      'text/html': new Blob([html], { type: 'text/html' }),
      'text/plain': new Blob([imagenes.map((i) => i.titulo).join('\n')], { type: 'text/plain' }),
    }),
  ])
}

export function descargarBlob(blob, nombreArchivo) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = nombreArchivo
  document.body.appendChild(a)
  a.click()
  a.remove()
  URL.revokeObjectURL(url)
}

function blobADataUrl(blob) {
  return new Promise((resolve, reject) => {
    const lector = new FileReader()
    lector.onload = () => resolve(lector.result)
    lector.onerror = () => reject(lector.error)
    lector.readAsDataURL(blob)
  })
}

/**
 * Un PDF A4 vertical con las imágenes una debajo de la otra, a todo el ancho
 * útil; pasa a una hoja nueva cuando la siguiente no entra.
 * @param {Array<{ blob: Blob, ancho: number, alto: number }>} imagenes
 * @param {string} nombreArchivo SIN extensión
 */
export async function descargarPdfDeImagenes(imagenes, nombreArchivo) {
  const MARGEN = 10
  const SEPARACION = 6
  const pdf = new jsPDF({ orientation: 'portrait', unit: 'mm', format: 'a4' })
  const anchoUtil = pdf.internal.pageSize.getWidth() - MARGEN * 2
  const altoUtil = pdf.internal.pageSize.getHeight() - MARGEN * 2

  let y = MARGEN
  for (const img of imagenes) {
    let ancho = anchoUtil
    let alto = (img.alto / img.ancho) * ancho
    if (alto > altoUtil) {
      alto = altoUtil
      ancho = (img.ancho / img.alto) * alto
    }
    if (y > MARGEN && y + alto > MARGEN + altoUtil) {
      pdf.addPage()
      y = MARGEN
    }
    pdf.addImage(await blobADataUrl(img.blob), 'PNG', MARGEN, y, ancho, alto, undefined, 'FAST')
    y += alto + SEPARACION
  }
  pdf.save(`${nombreArchivo}.pdf`)
}
