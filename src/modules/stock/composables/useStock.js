// Composable de Stock: cards de "Stock actual" con semáforo, ingreso/salida
// manual, relevamiento mensual (ajuste auditable) e historial de movimientos
// paginado. StockView.vue queda como template puro (memory/conventions.md).

import { computed, reactive, ref } from 'vue'
import {
  fetchStockActual,
  fetchMovimientos,
  fetchTodosLosMovimientos,
  registrarMovimientoManual,
  registrarRelevamiento,
  TIPOS_INGRESO,
} from '@/services/stock.service'
import { materialesService } from '@/modules/maestros/services/maestros.service'
import { fetchAnaliticaProveedoresDetalle } from '@/modules/analytics/services/analytics.service'
// Excel con formato corporativo (2026-09-03, pedido de Federico: "Fecha de
// exportación" + logo + estilo de colores + pie institucional) — reemplaza
// a src/services/excel-export.js (SheetJS, no soporta escribir estilos).
import { exportarPlanillaCorporativa, nombreArchivoConFecha } from '@/services/excel-corporativo'

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
          // Fix 2026-09-06 (Federico, prueba de flujo total): esta tab es
          // "Historial de INGRESOS" — si no se eligió un tipo puntual en el
          // filtro, acotar a TIPOS_INGRESO en vez de traer todos los tipos
          // (antes mostraba también egresos por despacho/árido/manual y
          // ajustes, que tienen su propia vista en Despachos/Báscula).
          tipo: filtrosHistorial.tipo || TIPOS_INGRESO,
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
  // Tab "Analítica de proveedores" (2026-09-02, roadmap Mobile — pedido de
  // Federico: réplica del formato del legado, memory/relevamiento-sistema-
  // viejo.md §Stock — card por proveedor con KPIs + tabla insumo/viajes/
  // toneladas). Antes solo vivía en el Dashboard (formato distinto,
  // comparativo mes actual vs. anterior) — acá se agrega como tab propia de
  // Stock sin sacar la del Dashboard, son 2 vistas con propósito distinto
  // del mismo dato (fetchAnaliticaProveedoresDetalle() es la nueva).
  // -------------------------------------------------------------------------

  function mesActualInput() {
    const hoy = new Date()
    return `${hoy.getFullYear()}-${String(hoy.getMonth() + 1).padStart(2, '0')}`
  }

  const mesProveedores = ref(mesActualInput())
  const analiticaProveedores = ref([])
  const cargandoProveedores = ref(false)

  async function cargarAnaliticaProveedores() {
    cargandoProveedores.value = true
    error.value = null
    try {
      const [anio, mes] = mesProveedores.value.split('-').map(Number)
      const desde = `${mesProveedores.value}-01`
      const hasta = new Date(anio, mes, 0).toISOString().slice(0, 10) // último día del mes
      analiticaProveedores.value = await fetchAnaliticaProveedoresDetalle({ desde, hasta })
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoProveedores.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Exportar a Excel — un botón por tab (2026-09-02, pedido de Federico,
  // mismo botón "⬇ Excel" que tenía el legado en Stock). Reusa
  // src/services/excel-export.js (memory/conventions.md, no duplicado).
  // -------------------------------------------------------------------------

  const exportando = ref(false)

  async function exportarStockActualExcel() {
    exportando.value = true
    try {
      await exportarPlanillaCorporativa(nombreArchivoConFecha('stock-actual'), [
        {
          nombre: 'Stock actual',
          titulo: 'Stock actual',
          filas: materiales.value,
          columnas: [
            { key: 'nombre', label: 'Material' },
            { key: 'cantidadKg', label: 'Cantidad (tn)', format: (v) => (v / 1000).toFixed(3) },
            { key: 'stock_minimo_kg', label: 'Mínimo (tn)', format: (v) => (v ? (v / 1000).toFixed(1) : '') },
            { key: 'stock_maximo_kg', label: 'Máximo (tn)', format: (v) => (v ? (v / 1000).toFixed(1) : '') },
            { key: 'estado', label: 'Estado', format: (v) => ({ rojo: 'Insuficiente', amarillo: 'Ajustado', verde: 'OK' })[v] ?? v },
          ],
        },
      ])
    } catch (e) {
      error.value = e.message
    } finally {
      exportando.value = false
    }
  }

  async function exportarMovimientosExcel() {
    exportando.value = true
    error.value = null
    try {
      const filas = await fetchTodosLosMovimientos({
        materialId: filtrosHistorial.materialId || undefined,
        // Mismo criterio que cargarMovimientos() — el Excel de esta tab
        // exporta lo mismo que se ve en pantalla, solo ingresos por defecto.
        tipo: filtrosHistorial.tipo || TIPOS_INGRESO,
        desde: filtrosHistorial.desde || undefined,
        hasta: filtrosHistorial.hasta || undefined,
      })
      await exportarPlanillaCorporativa(nombreArchivoConFecha('stock-historial-ingresos'), [
        {
          nombre: 'Historial',
          titulo: 'Historial de ingresos',
          filas,
          columnas: [
            { key: 'fecha_movimiento', label: 'Fecha', format: (v) => new Date(v).toLocaleString('es-AR') },
            { key: 'tipo', label: 'Tipo', format: (v) => etiquetaTipo(v) },
            { key: 'materialNombre', label: 'Material' },
            { key: 'cantidad_kg', label: 'Cantidad (tn)', format: (v) => (v / 1000).toFixed(3) },
            { key: 'origen', label: 'Proveedor / Motivo' },
            { key: 'numero_remito', label: 'Remito' },
            { key: 'responsableNombre', label: 'Responsable' },
          ],
        },
      ])
    } catch (e) {
      error.value = e.message
    } finally {
      exportando.value = false
    }
  }

  async function exportarProveedoresExcel() {
    exportando.value = true
    try {
      // Aplana proveedor+insumo en una fila por línea (formato tabular
      // estándar de Excel) en vez del formato de cards agrupadas de la UI —
      // una columna PROVEEDOR repetida por cada insumo es más útil para
      // filtrar/pivotear en Excel que replicar la jerarquía visual.
      const filas = analiticaProveedores.value.flatMap((p) =>
        p.insumos.map((i) => ({ proveedor: p.proveedor, ...i }))
      )
      await exportarPlanillaCorporativa(nombreArchivoConFecha('stock-analitica-proveedores'), [
        {
          nombre: 'Proveedores',
          titulo: 'Analítica de proveedores',
          filas,
          columnas: [
            { key: 'proveedor', label: 'Proveedor' },
            { key: 'material', label: 'Insumo' },
            { key: 'viajes', label: 'Viajes' },
            { key: 'toneladas', label: 'Toneladas', format: (v) => v.toFixed(2) },
          ],
        },
      ])
    } catch (e) {
      error.value = e.message
    } finally {
      exportando.value = false
    }
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
    mesProveedores,
    analiticaProveedores,
    cargandoProveedores,
    cargarAnaliticaProveedores,
    exportando,
    exportarStockActualExcel,
    exportarMovimientosExcel,
    exportarProveedoresExcel,
    iniciar,
  }
}
