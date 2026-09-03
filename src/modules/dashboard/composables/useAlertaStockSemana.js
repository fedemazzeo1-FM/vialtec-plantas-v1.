// Banner de alerta "stock proyectado no alcanza" del Dashboard
// (memory/business-rules.md, sección "Alerta de stock sin bloqueo duro" +
// memory/modules-status.md fila #1: la dependencia de datos ya estaba
// resuelta desde el módulo Stock, solo faltaba este cálculo/banner).
//
// Mismo patrón que useSimulador.js#impactoStock (consumo combinado de
// fórmulas contra stock, excluyendo Agua/Purgue) pero con la fuente de
// "entradas" fija: los pedidos `confirmado` de la semana en curso (no
// `solicitado` — todavía no comprometido, mismo criterio que ya usa
// fetchTotalesSemana() — ni `despachado`, cuyo stock ya se descontó al
// cerrar el pedido vía finalizar_despacho(), memory/business-rules.md).
// Reusa calcularEstadoSemaforo() de stock.service.js (mismo semáforo 3
// colores que las cards de Stock actual, UMBRAL=0.2) para no inventar una
// segunda regla de "cuándo alertar" — la única diferencia es que acá se le
// pasa el stock PROYECTADO (actual − consumo de la semana) en vez del
// actual.
//
// Sin bloqueo duro (regla explícita): esto es solo un banner informativo en
// el Dashboard, no impide confirmar pedidos con stock insuficiente en
// ningún otro lado del sistema.

import { computed, ref } from 'vue'
import { fetchPedidosSemana } from '@/modules/pedidos/services/pedidos.service'
import { fetchStockActual, calcularEstadoSemaforo } from '@/services/stock.service'
import { fetchFormulas, calcularConsumoTotalKg } from '@/modules/maestros/services/formulas.service'

const MATERIALES_SIN_DESCUENTO = ['agua', 'purgue'] // memory/business-rules.md

function normalizar(nombre) {
  return (nombre || '').trim().toLowerCase()
}

export function useAlertaStockSemana() {
  const cargando = ref(false)
  const error = ref(null)

  const pedidosConfirmados = ref([])
  const stockActual = ref([])
  const formulasPorId = ref({})

  async function cargar() {
    cargando.value = true
    error.value = null
    try {
      // soloActivas: false — un pedido ya confirmado puede referenciar una
      // fórmula que se desactivó después (no debería impedir la proyección).
      const [pedidos, stock, formulas] = await Promise.all([
        fetchPedidosSemana(),
        fetchStockActual(),
        fetchFormulas({ soloActivas: false }),
      ])
      pedidosConfirmados.value = pedidos.filter((p) => p.estado === 'confirmado')
      stockActual.value = stock
      formulasPorId.value = Object.fromEntries(formulas.map((f) => [f.id, f]))
    } catch (e) {
      error.value = e.message
    } finally {
      cargando.value = false
    }
  }

  /**
   * Un ítem por material cuyo estado PROYECTADO (stock actual − consumo
   * comprometido de la semana) sea amarillo o rojo — los que se proyectan
   * en verde no se muestran, el banner es solo para lo que necesita
   * atención (memory/business-rules.md: "alerta, no bloquea").
   */
  const alertas = computed(() => {
    const stockPorNombre = new Map(stockActual.value.map((m) => [normalizar(m.nombre), m]))
    const consumoPorMaterial = new Map() // nombre normalizado -> { nombre, kg }

    for (const pedido of pedidosConfirmados.value) {
      const formula = pedido.formula_id ? formulasPorId.value[pedido.formula_id] : null
      const cantidad = Number(pedido.cantidad_solicitada) || 0
      if (!formula || cantidad <= 0) continue

      for (const insumo of calcularConsumoTotalKg(formula, cantidad)) {
        const clave = normalizar(insumo.material)
        if (MATERIALES_SIN_DESCUENTO.includes(clave)) continue

        const previo = consumoPorMaterial.get(clave)
        if (previo) previo.kg += insumo.kg
        else consumoPorMaterial.set(clave, { nombre: insumo.material, kg: insumo.kg })
      }
    }

    const resultado = []
    for (const [clave, { nombre, kg }] of consumoPorMaterial) {
      const material = stockPorNombre.get(clave)
      if (!material) continue // insumo sin material catalogado todavía — mismo criterio que Simulador, se salta sin bloquear

      const stockProyectadoKg = material.cantidadKg - kg
      const estadoProyectado = calcularEstadoSemaforo(stockProyectadoKg, material.stock_minimo_kg, material.stock_maximo_kg)
      if (estadoProyectado === 'verde') continue

      resultado.push({
        nombre: material.nombre,
        stockActualTn: material.cantidadKg / 1000,
        consumoSemanaTn: kg / 1000,
        stockProyectadoTn: stockProyectadoKg / 1000,
        estadoProyectado, // 'rojo' | 'amarillo'
      })
    }

    return resultado.sort((a, b) =>
      a.estadoProyectado === b.estadoProyectado
        ? a.nombre.localeCompare(b.nombre, 'es')
        : a.estadoProyectado === 'rojo'
          ? -1
          : 1
    )
  })

  return { cargando, error, alertas, cargar }
}
