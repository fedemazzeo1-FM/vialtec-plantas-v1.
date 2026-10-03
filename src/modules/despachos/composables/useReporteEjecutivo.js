// Composable de "Imágenes para email" (Despachos → Resumen por obra,
// 2026-10-01, pedido de Federico): genera las 3 piezas del reporte ejecutivo
// del mes (ReporteEjecutivoMensual.vue) como PNG de alta resolución, listas
// para copiar al portapapeles (de a una o las 3 juntas) y pegar en el cuerpo
// del mail, descargar una por una o juntas en un PDF.
//
// La vista monta ReporteEjecutivoMensual fuera de pantalla mientras `datos`
// tiene valor y le pasa el elemento por `registrarContenedor`; acá se
// rasteriza cada <section data-pieza> y se desmonta.

import { nextTick, reactive } from 'vue'
import { fetchResumenAnual, nombreMesLargo } from '@/modules/despachos/services/informe-mensual.service'

const TITULOS = {
  obras: 'Despachos por obra',
  anual: 'Resumen anual acumulado',
  grafico: 'Gráfico de producción mensual',
}

export function useReporteEjecutivo() {
  let contenedor = null
  let servicioImagen = null

  // reactive() y no un objeto plano con refs: la vista accede con prefijo
  // (`reporte.abierto`), que no se auto-desenvuelve en el template si fueran
  // refs sueltas (memory/modules-status.md, nota de composables).
  const estado = reactive({
    generando: false,
    abierto: false,
    error: null,
    mes: '',
    mesLabel: '',
    datos: null, // props de ReporteEjecutivoMensual mientras está montado
    piezas: [], // [{ id, titulo, blob, ancho, alto, url, copiada }]
    puedeCopiar: false,
    copiadasTodas: false,
    generandoPdf: false,

    registrarContenedor(el) {
      contenedor = el
    },

    /**
     * @param {string} mes 'YYYY-MM' — el mismo del selector de Resumen por obra.
     * @param {Array<object>} obras filas ya resueltas del Resumen por obra de ese mes (con `nombre`).
     */
    async generar(mes, obras) {
      estado.generando = true
      estado.error = null
      try {
        const [resumenAnual, servicio] = await Promise.all([fetchResumenAnual(mes), import('@/services/imagen-reporte')])
        servicioImagen = servicio
        estado.puedeCopiar = servicio.puedeCopiarImagen()
        estado.mes = mes
        estado.mesLabel = nombreMesLargo(mes)
        estado.datos = { mesLabel: estado.mesLabel, obras, resumenAnual }

        await nextTick()
        // Deja que el navegador resuelva el layout del componente recién montado.
        await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))

        const secciones = Array.from(contenedor?.querySelectorAll('[data-pieza]') ?? [])
        if (!secciones.length) throw new Error('No se pudo armar el reporte.')

        estado.piezas.forEach((p) => URL.revokeObjectURL(p.url))
        const piezas = []
        for (const seccion of secciones) {
          const { blob, ancho, alto } = await servicio.capturarElementoPng(seccion)
          const id = seccion.dataset.pieza
          piezas.push({ id, titulo: TITULOS[id] ?? id, blob, ancho, alto, url: URL.createObjectURL(blob), copiada: false })
        }
        estado.piezas = piezas
        estado.copiadasTodas = false
        estado.abierto = true
      } catch (e) {
        estado.error = e.message
      } finally {
        estado.datos = null
        estado.generando = false
      }
    },

    nombreArchivo(pieza) {
      return `VialTec-${estado.mes}-${pieza.id}.png`
    },

    async copiar(pieza) {
      estado.error = null
      try {
        await servicioImagen.copiarImagenAlPortapapeles(pieza.blob)
        estado.piezas.forEach((p) => {
          p.copiada = p.id === pieza.id
        })
        estado.copiadasTodas = false
      } catch (e) {
        estado.error = `No se pudo copiar la imagen (${e.message}). Usá "Descargar PNG".`
      }
    },

    async copiarTodas() {
      estado.error = null
      try {
        await servicioImagen.copiarImagenesComoHtml(estado.piezas)
        estado.piezas.forEach((p) => {
          p.copiada = false
        })
        estado.copiadasTodas = true
      } catch (e) {
        estado.error = `No se pudieron copiar las imágenes (${e.message}). Copialas de a una o usá "Descargar".`
      }
    },

    descargar(pieza) {
      servicioImagen.descargarBlob(pieza.blob, estado.nombreArchivo(pieza))
    },

    descargarTodas() {
      estado.piezas.forEach((p) => estado.descargar(p))
    },

    async descargarPdf() {
      estado.generandoPdf = true
      estado.error = null
      try {
        await servicioImagen.descargarPdfDeImagenes(estado.piezas, `VialTec-${estado.mes}-reporte-ejecutivo`)
      } catch (e) {
        estado.error = e.message
      } finally {
        estado.generandoPdf = false
      }
    },
  })

  return estado
}
