// Descarga de PDF para los documentos imprimibles del sistema (Vale de
// pesaje, Remito de Báscula/Despachos, Remito Manual) — 2026-09-14, pedido
// de Federico: "Descargar PDF" al lado de "Imprimir" en los 3 modales de
// vista previa, con EXACTAMENTE el mismo diseño/orientación/hojas que la
// impresión (memory/conventions.md: helper transversal, no duplicado en
// cada vista).
//
// Enfoque: en vez de reimplementar el layout en la librería de PDF (jsPDF no
// entiende Tailwind/flex/grid), se rasteriza con html2canvas el mismo DOM
// que ya arma cada componente *Imprimible.vue — así el PDF es un espejo
// pixel-a-pixel de lo que se ve al imprimir, sin mantener el diseño en dos
// lugares. Cada "hoja" (Original/Duplicado del remito, o el único folio
// landscape del vale) se captura por separado, clonada en un contenedor
// FUERA de pantalla forzado a las dimensiones A4 reales — el modal en
// pantalla no tiene el tamaño mm fijo que sí aplica `.imprimible` bajo
// `@media print` (ver src/assets/main.css), así que sin este forzado el
// PDF saldría con la proporción "de pantalla", no la de la hoja impresa.
//
// No depende de leer los estilos de impresión de main.css (que solo aplican
// dentro de `@media print`, y el navegador no evalúa media queries de
// impresión para un render fuera de pantalla) — repite acá los mismos 2
// valores que ese archivo ya usa (padding 5mm, box-sizing border-box) para
// que el resultado sea el mismo. Si el día de mañana cambia el padding del
// `.imprimible` real, hay que actualizarlo también acá.

import html2canvas from 'html2canvas'
// Named export, NO default (verificado: en esta versión `export default` de
// jspdf no es el constructor usable — `new (await import('jspdf')).default(...)`
// tira "is not a constructor"; `jsPDF` con nombre sí es la clase real).
import { jsPDF } from 'jspdf'

const MM_POR_PULGADA = 25.4
const PX_POR_MM = 96 / MM_POR_PULGADA // 96dpi, misma referencia que usa el CSS de impresión para mm->px

const A4 = {
  landscape: { anchoMm: 297, altoMm: 210 },
  portrait: { anchoMm: 210, altoMm: 297 },
}

// Mismo padding que `.imprimible` en @media print (main.css) — se repite acá
// porque ese padding vive dentro de una media query que no se evalúa al
// clonar el nodo fuera de pantalla.
const PADDING_IMPRIMIBLE_MM = 5

/**
 * Encuentra las "hojas" (páginas) a exportar dentro del contenedor con la
 * clase "imprimible" ya renderizado en el modal. Mismo criterio para los 3
 * documentos del sistema, sin que el caller necesite conocer la estructura
 * interna de cada *Imprimible.vue:
 * - 'vale' (ValeImprimible.vue): 1 sola hoja landscape con las 2 copias
 *   lado a lado — su root template ES la hoja completa.
 * - 'remito' (RemitoImprimible.vue, Báscula/Despachos/Remito Manual): 2
 *   hojas portrait separadas (Original/Duplicado, cada una con su propio
 *   `break-after-page`) — son los hijos del root `<div>` del componente.
 */
function obtenerHojas(elementoImprimible, tipo) {
  const raizComponente = elementoImprimible?.firstElementChild
  if (!raizComponente) return []
  return tipo === 'vale' ? [raizComponente] : Array.from(raizComponente.children)
}

/** Espera a que las <img> (el logo) del clon terminen de cargar antes de rasterizar. */
function esperarImagenes(el) {
  const imgs = Array.from(el.querySelectorAll('img'))
  return Promise.all(
    imgs.map(
      (img) =>
        img.complete ||
        new Promise((resolve) => {
          img.addEventListener('load', resolve, { once: true })
          img.addEventListener('error', resolve, { once: true })
        })
    )
  )
}

/** Clona una hoja en un contenedor fuera de pantalla, a tamaño A4 real, y la rasteriza. */
async function capturarHoja(hojaEl, { anchoMm, altoMm }) {
  const anchoPx = Math.round(anchoMm * PX_POR_MM)
  const altoPx = Math.round(altoMm * PX_POR_MM)

  const clon = hojaEl.cloneNode(true)
  const contenedor = document.createElement('div')
  Object.assign(contenedor.style, {
    position: 'fixed',
    top: '0',
    left: '-99999px', // fuera de pantalla, no del layout (necesita renderizarse para que html2canvas lo mida)
    width: `${anchoPx}px`,
    height: `${altoPx}px`,
    boxSizing: 'border-box',
    padding: `${PADDING_IMPRIMIBLE_MM}mm`,
    background: '#ffffff',
    overflow: 'hidden',
  })
  contenedor.appendChild(clon)
  document.body.appendChild(contenedor)

  try {
    await esperarImagenes(clon)
    // Deja que el navegador aplique layout al clon recién insertado antes
    // de rasterizarlo (evita capturas con el layout todavía sin resolver).
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))
    return await html2canvas(contenedor, { scale: 3, backgroundColor: '#ffffff', useCORS: true })
  } finally {
    contenedor.remove()
  }
}

/**
 * Genera y descarga un PDF a partir de un elemento ".imprimible" ya
 * renderizado en un modal de vista previa — mismo diseño, orientación y
 * cantidad de hojas que el botón "Imprimir".
 * @param {HTMLElement} elementoImprimible el div con la clase "imprimible" (template ref)
 * @param {{ tipo: 'vale'|'remito', nombreArchivo: string }} opciones nombreArchivo SIN extensión
 */
export async function descargarPdfImprimible(elementoImprimible, { tipo, nombreArchivo }) {
  const hojas = obtenerHojas(elementoImprimible, tipo)
  if (!hojas.length) throw new Error('No hay nada para exportar todavía.')

  const { anchoMm, altoMm } = tipo === 'vale' ? A4.landscape : A4.portrait
  const orientacion = tipo === 'vale' ? 'landscape' : 'portrait'
  const pdf = new jsPDF({ orientation: orientacion, unit: 'mm', format: 'a4' })

  for (let i = 0; i < hojas.length; i++) {
    const canvas = await capturarHoja(hojas[i], { anchoMm, altoMm })
    if (i > 0) pdf.addPage('a4', orientacion)
    pdf.addImage(canvas.toDataURL('image/jpeg', 0.95), 'JPEG', 0, 0, anchoMm, altoMm)
  }

  pdf.save(`${nombreArchivo}.pdf`)
}
