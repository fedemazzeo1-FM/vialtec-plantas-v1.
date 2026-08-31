// Composable de Stock: cards de "Stock actual" con semáforo, ingreso/salida
// manual, relevamiento mensual (ajuste auditable) e historial de movimientos
// paginado. StockView.vue queda como template puro (memory/conventions.md).

import { computed, reactive, ref } from 'vue'
import { fetchStockActual, fetchMovimientos, registrarMovimientoManual, registrarRelevamiento } from '@/services/stock.service'
import { materialesService } from '@/modules/maestros/services/maestros.service'

const TAMANO_PAGINA_HISTORIAL = 30

const ETIQUETA_TIPO_MOVIMIENTO = {
  ingreso_proveedor: 'Ingreso proveedor',
  egreso_despacho: 'Egreso por despacho',
  egreso_arido: 'Egreso árido (báscula)',
  ingreso_manual: 'Ingreso manual',
  egreso_manual: 'Egreso manual',
  ajuste: 'Ajuste (relevamiento)',
  recalculo_despacho: 'Recálculo de despacho',
}

export function useStock() {
  const error = ref(null)

  // -------------------------------------------------------------------------
  // Unidad de visualización (toggle global tn/kg — memory/relevamiento §6)
  // -------------------------------------------------------------------------

  const unidadVista = ref('tn') // 'tn' | 'kg'

  function formatearCantidad(cantidadKg) {
    const valor = unidadVista.value === 'kg' ? cantidadKg : cantidadKg / 1000
    return valor.toLocaleString('es-AR', { maximumFractionDigits: unidadVista.value === 'kg' ? 0 : 2 })
  }

  // -------------------------------------------------------------------------
  // Cards de Stock actual
  // -------------------------------------------------------------------------

  const materiales = ref([])
  const cargandoStock = ref(false)

  async function cargarStock() {
    cargandoStock.value = true
    error.value = null
    try {
      materiales.value = await fetchStockActual()
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoStock.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Catálogo completo de materiales (para selects de los modales — incluye
  // los que no controlan stock queda afuera, no tiene sentido ingresarles
  // movimientos)
  // -------------------------------------------------------------------------

  const catalogoMateriales = ref([])

  async function cargarCatalogo() {
    try {
      catalogoMateriales.value = (await materialesService.fetch({ soloActivos: true })).filter((m) => m.controla_stock)
    } catch (e) {
      error.value = e.message
    }
  }

  // -------------------------------------------------------------------------
  // Modal ingreso / salida manual (Logica sis. plantas v1.rtf §4.4)
  // -------------------------------------------------------------------------

  const modalMovimientoAbierto = ref(false)
  const formMovimiento = reactive({
    material_id: '',
    tipo: 'ingreso_manual',
    cantidad: null,
    unidad: 'tn',
    origen: '',
    numero_remito: '',
    observaciones: '',
  })
  const guardandoMovimiento = ref(false)

  function abrirMovimiento(tipo = 'ingreso_manual') {
    Object.assign(formMovimiento, {
      material_id: '',
      tipo,
      cantidad: null,
      unidad: 'tn',
      origen: '',
      numero_remito: '',
      observaciones: '',
    })
    error.value = null
    modalMovimientoAbierto.value = true
  }

  async function guardarMovimiento() {
    if (!formMovimiento.material_id) {
      error.value = 'Elegí un material.'
      return
    }
    if (!(Number(formMovimiento.cantidad) > 0)) {
      error.value = 'La cantidad debe ser mayor a 0.'
      return
    }

    guardandoMovimiento.value = true
    error.value = null
    try {
      const cantidadKg = formMovimiento.unidad === 'kg' ? Number(formMovimiento.cantidad) : Number(formMovimiento.cantidad) * 1000
      await registrarMovimientoManual({
        materialId: formMovimiento.material_id,
        tipo: formMovimiento.tipo,
        cantidadKg,
        origen: formMovimiento.origen.trim() || null,
        numeroRemito: formMovimiento.numero_remito.trim() || null,
        observaciones: formMovimiento.observaciones.trim() || null,
      })
      modalMovimientoAbierto.value = false
      await Promise.all([cargarStock(), cargarMovimientos()])
    } catch (e) {
      error.value = e.message
    } finally {
      guardandoMovimiento.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Modal Relevamiento mensual — prellenado con el valor actual en tn, 3
  // decimales (memory/relevamiento-sistema-viejo.md Etapa 3). NO pisa el
  // stock directo: registrarRelevamiento() calcula la diferencia server-side.
  // -------------------------------------------------------------------------

  const modalRelevamientoAbierto = ref(false)
  const conteosRelevamiento = ref([])
  const motivoRelevamiento = ref('Relevamiento mensual')
  const guardandoRelevamiento = ref(false)

  function abrirRelevamiento() {
    conteosRelevamiento.value = materiales.value.map((m) => ({
      materialId: m.id,
      nombre: m.nombre,
      cantidadTn: Number((m.cantidadKg / 1000).toFixed(3)),
    }))
    motivoRelevamiento.value = 'Relevamiento mensual'
    error.value = null
    modalRelevamientoAbierto.value = true
  }

  async function guardarRelevamiento() {
    guardandoRelevamiento.value = true
    error.value = null
    try {
      await registrarRelevamiento(
        conteosRelevamiento.value.map((c) => ({ materialId: c.materialId, cantidadKg: Number(c.cantidadTn) * 1000 })),
        motivoRelevamiento.value.trim() || undefined
      )
      modalRelevamientoAbierto.value = false
      await Promise.all([cargarStock(), cargarMovimientos()])
    } catch (e) {
      error.value = e.message
    } finally {
      guardandoRelevamiento.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Historial de movimientos (paginado)
  // -------------------------------------------------------------------------

  const movimientos = ref([])
  const totalMovimientos = ref(0)
  const paginaHistorial = ref(1)
  const cargandoHistorial = ref(false)
  const filtrosHistorial = reactive({ materialId: '', tipo: '', desde: '', hasta: '' })

  async function cargarMovimientos() {
    cargandoHistorial.value = true
    error.value = null
    try {
      const resultado = await fetchMovimientos(
        {
          materialId: filtrosHistorial.materialId || undefined,
          tipo: filtrosHistorial.tipo || undefined,
          desde: filtrosHistorial.desde || undefined,
          hasta: filtrosHistorial.hasta || undefined,
        },
        { pagina: paginaHistorial.value, tamanoPagina: TAMANO_PAGINA_HISTORIAL }
      )
      movimientos.value = resultado.filas
      totalMovimientos.value = resultado.total
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoHistorial.value = false
    }
  }

  function aplicarFiltrosHistorial() {
    paginaHistorial.value = 1
    cargarMovimientos()
  }

  function limpiarFiltrosHistorial() {
    filtrosHistorial.materialId = ''
    filtrosHistorial.tipo = ''
    filtrosHistorial.desde = ''
    filtrosHistorial.hasta = ''
    aplicarFiltrosHistorial()
  }

  function cambiarPaginaHistorial(pagina) {
    paginaHistorial.value = pagina
    cargarMovimientos()
  }

  function etiquetaTipo(tipo) {
    return ETIQUETA_TIPO_MOVIMIENTO[tipo] ?? tipo
  }

  // -------------------------------------------------------------------------
  // Arranque
  // -------------------------------------------------------------------------

  function iniciar() {
    cargarCatalogo().then(cargarStock)
    cargarMovimientos()
  }

  return {
    error,
    unidadVista,
    formatearCantidad,
    materiales,
    cargandoStock,
    cargarStock,
    catalogoMateriales,
    modalMovimientoAbierto,
    formMovimiento,
    guardandoMovimiento,
    abrirMovimiento,
    guardarMovimiento,
    modalRelevamientoAbierto,
    conteosRelevamiento,
    motivoRelevamiento,
    guardandoRelevamiento,
    abrirRelevamiento,
    guardarRelevamiento,
    movimientos,
    totalMovimientos,
    paginaHistorial,
    cargandoHistorial,
    filtrosHistorial,
    TAMANO_PAGINA_HISTORIAL,
    aplicarFiltrosHistorial,
    limpiarFiltrosHistorial,
    cambiarPaginaHistorial,
    etiquetaTipo,
    iniciar,
  }
}
