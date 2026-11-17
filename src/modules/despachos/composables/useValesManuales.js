// Vales manuales de Despachos (migración 77, 17/11/2026): simulaciones con el formato del vale de balanza.
// No suman a producción ni a despachos y no tocan stock (ver vales-manuales.service.js). Este composable
// maneja la pestaña "Vales manuales": listado, alta, anulación con motivo e impresión del vale y de su
// remito (los mismos componentes que Báscula: ValeImprimible.vue y RemitoImprimible.vue).

import { computed, reactive, ref, watch } from 'vue'
import {
  anularValeManual,
  fetchValesManuales,
  formatearNumeroValeManual,
  generarRemitoValeManual,
  generarValeManual,
} from '@/modules/despachos/services/vales-manuales.service'
import { formatearCantidad } from '@/services/formato-numeros'

/** '38,5' → 38.5; vacío → null. */
function aNumero(valor) {
  const t = String(valor ?? '').trim().replace(/\./g, (m, i, s) => (s.includes(',') ? '' : m)).replace(',', '.')
  return t === '' ? null : Number(t)
}

/** 'YYYY-MM-DDTHH:mm' de ahora, en hora local (para <input type="datetime-local">). */
function ahoraLocal() {
  const d = new Date()
  d.setMinutes(d.getMinutes() - d.getTimezoneOffset())
  return d.toISOString().slice(0, 16)
}

/**
 * @param {{ formulas: import('vue').Ref<any[]>, patentes: import('vue').Ref<any[]> }} catalogos
 */
export function useValesManuales({ formulas, patentes }) {
  const vales = ref([])
  const cargando = ref(false)
  const error = ref(null)

  async function cargar() {
    cargando.value = true
    error.value = null
    try {
      vales.value = await fetchValesManuales()
    } catch (e) {
      error.value = e.message
    } finally {
      cargando.value = false
    }
  }

  const destinoDe = (v) => v?.obra?.nombre ?? v?.cliente_externo ?? '—'
  const mezclaDe = (v) => formulas.value.find((f) => f.id === v?.formula_id)?.nombre ?? '—'
  const formulasAsfalto = computed(() =>
    formulas.value.filter((f) => f.tipo === 'asfalto' && f.activo !== false).sort((a, b) => a.nombre.localeCompare(b.nombre))
  )

  // ---------------------------------------------------------------------------
  // Alta
  // ---------------------------------------------------------------------------

  function formVacio() {
    return {
      fecha: ahoraLocal(),
      destinoTipo: 'obra',
      obraId: '',
      cliente: '',
      formulaId: '',
      pesoBruto: '',
      tara: '',
      patente: '',
      chofer: '',
      temperatura: '',
      observaciones: '',
    }
  }

  const modalNuevoAbierto = ref(false)
  const form = reactive(formVacio())
  const guardando = ref(false)
  const errorForm = ref(null)

  const netoForm = computed(() => {
    const bruto = aNumero(form.pesoBruto)
    const tara = aNumero(form.tara)
    if (bruto == null || tara == null || Number.isNaN(bruto) || Number.isNaN(tara)) return null
    return Math.round((bruto - tara) * 1000) / 1000
  })

  // Igual que Báscula (useBascula.js#completarDesdePatente): al elegir una patente del catálogo se completan
  // solos la tara y el chofer habitual; después se pueden cambiar a mano.
  function alCambiarPatente() {
    const encontrada = patentes.value.find((p) => p.patente === form.patente.trim())
    if (!encontrada) return
    if (encontrada.tara != null) form.tara = String(encontrada.tara).replace('.', ',')
    if (encontrada.chofer_habitual) form.chofer = encontrada.chofer_habitual
  }
  // Al tipear o al elegir de la lista: se completa en cuanto coincide exacto con una patente del catálogo.
  watch(() => form.patente, alCambiarPatente)

  function abrirNuevo() {
    Object.assign(form, formVacio())
    errorForm.value = null
    modalNuevoAbierto.value = true
  }

  function validar() {
    if (!form.fecha) return 'Elegí la fecha y hora.'
    if (form.destinoTipo === 'obra' && !form.obraId) return 'Elegí la obra.'
    if (form.destinoTipo === 'cliente' && !form.cliente.trim()) return 'Elegí o escribí el cliente.'
    if (!form.formulaId) return 'Elegí la mezcla.'
    const bruto = aNumero(form.pesoBruto)
    const tara = aNumero(form.tara)
    if (bruto == null || Number.isNaN(bruto) || bruto <= 0) return 'Cargá el peso bruto (mayor a 0).'
    if (tara == null || Number.isNaN(tara) || tara < 0) return 'Cargá la tara (0 o más).'
    if (bruto <= tara) return 'El peso bruto tiene que ser mayor que la tara.'
    const temp = aNumero(form.temperatura)
    if (temp != null && Number.isNaN(temp)) return 'La temperatura tiene que ser un número.'
    return null
  }

  async function guardar() {
    errorForm.value = validar()
    if (errorForm.value) return
    guardando.value = true
    try {
      const vale = await generarValeManual({
        fechaPesada: new Date(form.fecha),
        formulaId: form.formulaId,
        pesoBruto: aNumero(form.pesoBruto),
        tara: aNumero(form.tara),
        obraId: form.destinoTipo === 'obra' ? Number(form.obraId) : null,
        clienteExterno: form.destinoTipo === 'cliente' ? form.cliente.trim() : null,
        patente: form.patente,
        chofer: form.chofer,
        temperatura: aNumero(form.temperatura),
        observaciones: form.observaciones,
      })
      modalNuevoAbierto.value = false
      await cargar()
      verVale(vales.value.find((v) => v.id === vale.id) ?? vale)
    } catch (e) {
      errorForm.value = e.message
    } finally {
      guardando.value = false
    }
  }

  // ---------------------------------------------------------------------------
  // Impresión: vale (A4 apaisado, 2 copias) y remito (A4 vertical)
  // ---------------------------------------------------------------------------

  const valeParaImprimir = ref(null)
  const modalValeAbierto = ref(false)
  const modalRemitoAbierto = ref(false)
  const generandoRemito = ref(null) // id del vale

  /** El vale con la forma que espera ValeImprimible.vue (la misma fila de Báscula). */
  const valeImprimible = computed(() => {
    const v = valeParaImprimir.value
    if (!v) return null
    return {
      numero_vale_manual: v.numero,
      tipo_vale: 'asfalto',
      fecha_pesada: v.fecha_pesada,
      patente: v.patente,
      chofer: v.chofer,
      peso_bruto: v.peso_bruto,
      tara: v.tara,
      peso_neto: v.peso_neto,
      unidad: 'tn',
      temperatura: v.temperatura,
    }
  })

  function verVale(v) {
    valeParaImprimir.value = v
    modalValeAbierto.value = true
  }

  /** Props de RemitoImprimible.vue, mismo armado que el remito de Báscula (MEZCLA ASFÁLTICA + leyenda del vale). */
  const remitoProps = computed(() => {
    const v = valeParaImprimir.value
    if (!v || v.numero_remito == null) return null
    const patenteCatalogo = patentes.value.find((p) => p.patente === v.patente)
    return {
      numeroRemito: v.numero_remito,
      fecha: v.fecha_pesada,
      destino: destinoDe(v),
      items: [
        {
          cantidad: `${formatearCantidad(Number(v.peso_neto), 2)} tn`,
          detalle: 'MEZCLA ASFÁLTICA',
          subtexto: `S/Vale manual N° ${formatearNumeroValeManual(v.numero)}`,
        },
      ],
      transporte: patenteCatalogo ? (patenteCatalogo.es_externa ? 'Tercero' : 'Propio') : null,
      patente: v.patente || '',
      transportista: v.chofer || '',
      lugarEntrega: '',
    }
  })

  async function verRemito(v) {
    error.value = null
    generandoRemito.value = v.id
    try {
      const actualizado = v.numero_remito != null ? v : { ...v, ...(await generarRemitoValeManual(v.id)) }
      const i = vales.value.findIndex((x) => x.id === v.id)
      if (i >= 0) vales.value[i] = { ...vales.value[i], ...actualizado }
      valeParaImprimir.value = i >= 0 ? vales.value[i] : actualizado
      modalValeAbierto.value = false
      modalRemitoAbierto.value = true
    } catch (e) {
      error.value = e.message
    } finally {
      generandoRemito.value = null
    }
  }

  // Mismo mecanismo que useDespachos.js#imprimir(): el remito necesita A4 vertical y la regla @page
  // global es apaisada, así que se inyecta una @page vertical solo mientras se imprime.
  function imprimir() {
    let estilo = null
    if (modalRemitoAbierto.value) {
      estilo = document.createElement('style')
      estilo.textContent = '@page { size: A4 portrait; margin: 0; }'
      document.head.appendChild(estilo)
    }
    window.print()
    estilo?.remove()
  }

  const descargandoPdf = ref(false)
  async function descargarPdf(elemento) {
    const v = valeParaImprimir.value
    if (!elemento || !v) return
    descargandoPdf.value = true
    try {
      const { descargarPdfImprimible } = await import('@/services/pdf-imprimible')
      const esRemito = modalRemitoAbierto.value
      const nombreArchivo = esRemito
        ? `Remito-${String(v.numero_remito).padStart(5, '0')}`
        : `Vale-${formatearNumeroValeManual(v.numero)}`
      await descargarPdfImprimible(elemento, { tipo: esRemito ? 'remito' : 'vale', nombreArchivo })
    } catch (e) {
      error.value = e.message
    } finally {
      descargandoPdf.value = false
    }
  }

  // ---------------------------------------------------------------------------
  // Anulación (con motivo; nunca se borra)
  // ---------------------------------------------------------------------------

  const valeParaAnular = ref(null)
  const motivoAnulacion = ref('')
  const anulando = ref(false)
  const errorAnular = ref(null)

  function abrirAnular(v) {
    valeParaAnular.value = v
    motivoAnulacion.value = ''
    errorAnular.value = null
  }

  async function confirmarAnular() {
    if (!motivoAnulacion.value.trim()) {
      errorAnular.value = 'El motivo es obligatorio.'
      return
    }
    anulando.value = true
    try {
      await anularValeManual(valeParaAnular.value.id, motivoAnulacion.value.trim())
      valeParaAnular.value = null
      await cargar()
    } catch (e) {
      errorAnular.value = e.message
    } finally {
      anulando.value = false
    }
  }

  return {
    vales,
    cargando,
    error,
    cargar,
    destinoDe,
    mezclaDe,
    formulasAsfalto,
    formatearNumeroValeManual,
    modalNuevoAbierto,
    form,
    netoForm,
    guardando,
    errorForm,
    abrirNuevo,
    alCambiarPatente,
    guardar,
    valeParaImprimir,
    valeImprimible,
    modalValeAbierto,
    modalRemitoAbierto,
    generandoRemito,
    verVale,
    remitoProps,
    verRemito,
    imprimir,
    descargandoPdf,
    descargarPdf,
    valeParaAnular,
    motivoAnulacion,
    anulando,
    errorAnular,
    abrirAnular,
    confirmarAnular,
  }
}
