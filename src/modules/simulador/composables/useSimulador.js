// Composable del Simulador de producción: 100% client-side, sin persistencia
// en DB (Logica sis. plantas v1.rtf/v2.rtf: "Calculá despachos sin afectar
// el sistema real"). Reusa calcularConsumoTotalKg() de formulas.service.js y
// fetchStockActual() de stock.service.js — no hay tabla ni migración propia.
//
// Fiel al relevamiento en vivo contra produccion.vialtec.app (2026-08-31):
// mix de fórmulas simultáneo, subtotales por tipo, tabla de impacto con
// estado BINARIO (OK/Insuficiente — a diferencia del semáforo de 3 colores
// de las cards de Stock), sin exportar, sin capacidad máxima calculada (es
// resta simple contra el stock actual, confirmado en vivo).

import { computed, reactive, ref } from 'vue'
import { fetchFormulas, calcularConsumoTotalKg } from '@/modules/maestros/services/formulas.service'
import { fetchStockActual } from '@/services/stock.service'

const MATERIALES_SIN_DESCUENTO = ['agua', 'purgue'] // memory/business-rules.md

function normalizar(nombre) {
  return (nombre || '').trim().toLowerCase()
}

export function useSimulador() {
  const error = ref(null)
  const cargandoBase = ref(false)

  const formulas = ref([])
  const stockActual = ref([])

  async function cargarBase() {
    cargandoBase.value = true
    error.value = null
    try {
      const [listaFormulas, listaStock] = await Promise.all([fetchFormulas({ soloActivas: true }), fetchStockActual()])
      formulas.value = listaFormulas
      stockActual.value = listaStock
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoBase.value = false
    }
  }

  const stockPorNombre = computed(() => {
    const mapa = new Map()
    for (const m of stockActual.value) mapa.set(normalizar(m.nombre), m)
    return mapa
  })

  // -------------------------------------------------------------------------
  // Formulario "Agregar despacho simulado" + lista acumulable
  // -------------------------------------------------------------------------

  const form = reactive({ formulaId: '', cantidad: null, etiqueta: '' })
  const entradas = ref([])
  let contador = 0

  const formulaSeleccionada = computed(() => formulas.value.find((f) => f.id === form.formulaId) ?? null)
  const unidadForm = computed(() => (formulaSeleccionada.value?.tipo === 'hormigon' ? 'm³' : 'tn'))

  function limpiarForm() {
    form.formulaId = ''
    form.cantidad = null
    form.etiqueta = ''
  }

  function agregarEntrada() {
    error.value = null
    if (!form.formulaId) {
      error.value = 'Elegí una fórmula.'
      return
    }
    if (!(Number(form.cantidad) > 0)) {
      error.value = 'La cantidad debe ser mayor a 0.'
      return
    }
    const formula = formulas.value.find((f) => f.id === form.formulaId)
    contador += 1
    entradas.value.push({
      id: contador,
      formulaId: form.formulaId,
      formulaNombre: formula.nombre,
      tipo: formula.tipo,
      cantidad: Number(form.cantidad),
      etiqueta: form.etiqueta.trim() || null,
    })
    limpiarForm()
  }

  function quitarEntrada(id) {
    entradas.value = entradas.value.filter((e) => e.id !== id)
  }

  function limpiarTodo() {
    entradas.value = []
    error.value = null
  }

  // -------------------------------------------------------------------------
  // Subtotales por tipo de mezcla ("Total asfalto" / "Total hormigón") —
  // solo se muestra el que tenga al menos una entrada, igual que producción.
  // -------------------------------------------------------------------------

  const totalAsfaltoTn = computed(() =>
    entradas.value.filter((e) => e.tipo === 'asfalto').reduce((acc, e) => acc + e.cantidad, 0)
  )
  const totalHormigonM3 = computed(() =>
    entradas.value.filter((e) => e.tipo === 'hormigon').reduce((acc, e) => acc + e.cantidad, 0)
  )

  // -------------------------------------------------------------------------
  // Impacto en stock: consumo combinado de TODAS las entradas, por insumo,
  // contra el stock actual. Excluye Agua/Purgue (memory/business-rules.md).
  // Estado binario: proyectado < 0 -> insuficiente (confirmado en vivo, no
  // hay 3er estado acá como en las cards de Stock).
  // -------------------------------------------------------------------------

  const impactoStock = computed(() => {
    const consumoPorMaterial = new Map() // nombre normalizado -> { nombre, kg }

    for (const entrada of entradas.value) {
      const formula = formulas.value.find((f) => f.id === entrada.formulaId)
      if (!formula) continue

      for (const insumo of calcularConsumoTotalKg(formula, entrada.cantidad)) {
        const clave = normalizar(insumo.material)
        if (MATERIALES_SIN_DESCUENTO.includes(clave)) continue

        const previo = consumoPorMaterial.get(clave)
        if (previo) previo.kg += insumo.kg
        else consumoPorMaterial.set(clave, { nombre: insumo.material, kg: insumo.kg })
      }
    }

    return Array.from(consumoPorMaterial.values())
      .map(({ nombre, kg }) => {
        const enStock = stockPorNombre.value.get(normalizar(nombre))
        const stockActualKg = enStock?.cantidadKg ?? 0
        const stockProyectadoKg = stockActualKg - kg
        return {
          insumo: enStock?.nombre ?? nombre,
          stockActualKg,
          consumoTotalKg: kg,
          stockProyectadoKg,
          estado: stockProyectadoKg < 0 ? 'insuficiente' : 'ok',
        }
      })
      .sort((a, b) => a.insumo.localeCompare(b.insumo, 'es'))
  })

  function iniciar() {
    cargarBase()
  }

  return {
    error,
    cargandoBase,
    formulas,
    form,
    unidadForm,
    entradas,
    agregarEntrada,
    quitarEntrada,
    limpiarTodo,
    totalAsfaltoTn,
    totalHormigonM3,
    impactoStock,
    iniciar,
  }
}
