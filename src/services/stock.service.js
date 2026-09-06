// Service de Stock — único punto de acceso a Supabase para plantas_stock y
// plantas_stock_movimientos (migración 13). El catálogo de materiales
// (plantas_materiales) vive en maestros.service.js — este service lo LEE,
// no lo duplica (memory/conventions.md: lógica compartida en un solo lugar).
//
// Todo el stock se maneja en kg internamente (memory/business-rules.md); la
// UI convierte a tn dividiendo por 1000. Escribir SIEMPRE vía las RPC
// (registrar_movimiento_manual / registrar_relevamiento_stock) o, para
// ingreso/egreso de áridos y descuento por despacho, vía las RPC de
// Báscula/Pedidos (registrar_pesada_bascula / finalizar_despacho /
// corregir_despacho) — nunca un UPDATE directo sobre plantas_stock, se
// perdería el registro en plantas_stock_movimientos.

import { supabase } from '@/config/supabase'
import { fetchPagina, fetchPaginado } from '@/services/fetch-paginado'
import { fetchNombresPorEmail } from '@/services/flota.service'
import { limiteInicioDiaLocal, limiteFinDiaLocalExclusivo } from '@/services/fecha'

/**
 * Semáforo 3 colores contra stock_minimo_kg/stock_maximo_kg del material.
 * Umbral "amarillo" confirmado contra producción real (relevamiento en vivo,
 * 2026-08-31): ARENA 0/3 — actual 66,38t, mín 50t, máx 150t → "Ajustado".
 * Eso encaja con `mínimo + 20% del rango (máx-mín)` = 50+20=70t (66,38<70),
 * NO con el 20% sobre el mínimo que se había asumido antes (mín×1,2=60,
 * 66,38>60 hubiera dado "OK", incorrecto). El estado NO depende de máximoKg
 * salvo para calcular ese rango — un stock muy por encima del máximo
 * confirmado sigue dando "OK" en producción (el máximo es solo referencia
 * visual de la barra, no dispara alerta). Si no hay máximoKg configurado, no
 * se puede calcular el rango — cae a un margen del 20% sobre el mínimo como
 * aproximación razonable.
 */
export function calcularEstadoSemaforo(cantidadKg, minimoKg, maximoKg) {
  if (minimoKg == null) return 'verde'
  if (cantidadKg <= 0 || cantidadKg < minimoKg) return 'rojo'
  const umbralAjustado = maximoKg != null ? minimoKg + 0.2 * (maximoKg - minimoKg) : minimoKg * 1.2
  if (cantidadKg < umbralAjustado) return 'amarillo'
  return 'verde'
}

/**
 * Cards de "Stock actual": un material por fila (solo controla_stock=true,
 * activo=true), con su saldo actual (0 si todavía no tiene ningún
 * movimiento) y el estado del semáforo ya calculado.
 */
export async function fetchStockActual() {
  const [materiales, stock] = await Promise.all([
    supabase.from('plantas_materiales').select('*').eq('activo', true).eq('controla_stock', true).order('nombre', { ascending: true }),
    supabase.from('plantas_stock').select('*'),
  ])
  if (materiales.error) throw materiales.error
  if (stock.error) throw stock.error

  const stockPorMaterial = new Map((stock.data ?? []).map((s) => [s.material_id, s]))

  return (materiales.data ?? []).map((material) => {
    const fila = stockPorMaterial.get(material.id)
    const cantidadKg = Number(fila?.cantidad_kg ?? 0)
    return {
      ...material,
      cantidadKg,
      actualizadoEn: fila?.actualizado_en ?? null,
      estado: calcularEstadoSemaforo(cantidadKg, material.stock_minimo_kg, material.stock_maximo_kg),
    }
  })
}

// ---------------------------------------------------------------------------
// Historial de movimientos (paginado — memory/architecture.md, tabla que
// crece sin límite)
// ---------------------------------------------------------------------------

// Exportado: useStock.js lo reusa para acotar la tab "Historial de ingresos"
// a solo estos 2 tipos (memory/conventions.md, no duplicar la lista) — ver
// comentario 2026-09-06 en queryMovimientos() más abajo.
export const TIPOS_INGRESO = ['ingreso_proveedor', 'ingreso_manual']

// Vista puente (2026-09-04, memory/pending.md): UNION de plantas_stock_movimientos
// real + lo que el legado sigue cargando en paralelo en kv_store (todavía sin
// fila real acá). Solo el HISTORIAL lee de acá — las RPC de escritura
// (registrar_movimiento_manual, registrar_relevamiento_stock, etc.) siguen
// contra la tabla real, sin cambios. NO cubre movimientos tipo 'relevamiento'
// del legado (ver supabase/scripts/vistas_puente_legado_bascula_stock.sql).
const VISTA_STOCK_MOVIMIENTOS_VIVA = 'plantas_v_stock_movimientos_viva'

/**
 * Query base compartida entre fetchMovimientos() (paginada, UI) y
 * fetchTodosLosMovimientos() (sin paginar, export a Excel — memory/
 * conventions.md, un solo lugar para el filtro).
 */
function queryMovimientos(filtros) {
  let query = supabase
    .from(VISTA_STOCK_MOVIMIENTOS_VIVA)
    .select('*', { count: 'exact' })
    .order('fecha_movimiento', { ascending: false })

  if (filtros.materialId) query = query.eq('material_id', filtros.materialId)
  // filtros.tipo acepta un string (un tipo puntual, .eq) o un array (ej.
  // TIPOS_INGRESO — memory/pending.md 2026-09-06: la tab "Historial de
  // ingresos" de Stock mostraba TODOS los tipos de movimiento por defecto
  // (incluidos egresos por despacho), cuando la idea es que ahí solo
  // aparezcan ingresos de materiales — useStock.js pasa el array cuando el
  // usuario no eligió un tipo puntual en el filtro).
  if (Array.isArray(filtros.tipo)) query = query.in('tipo', filtros.tipo)
  else if (filtros.tipo) query = query.eq('tipo', filtros.tipo)
  // Fix 2026-09-04 (mismo bug de Báscula, memory/pending.md): fecha_movimiento
  // es timestamptz — la fecha "pelada"/`T23:59:59` sin offset se casteaba
  // contra UTC en vez de hora local (Argentina, UTC-3), perdiendo en
  // silencio los movimientos cargados entre las 21:00 y las 23:59 locales
  // del día `hasta`. Ver src/services/fecha.js.
  if (filtros.desde) query = query.gte('fecha_movimiento', limiteInicioDiaLocal(filtros.desde))
  if (filtros.hasta) query = query.lt('fecha_movimiento', limiteFinDiaLocalExclusivo(filtros.hasta))

  return query
}

/** Enriquece con materialNombre/responsableNombre/esIngreso — reusado por las dos funciones de abajo. */
async function enriquecerMovimientos(filas) {
  // Responsable (migración 15): plantas_stock_movimientos solo guarda
  // responsable_email (auth.email(), server-side) — acá se resuelve el
  // nombre a mostrar contra flota_usuarios_email, mismo patrón que
  // auth.store.js usa para el usuario logueado. Si no hay match (usuario sin
  // fila en flota_usuarios_email), se muestra el email tal cual.
  const nombresPorEmail = await fetchNombresPorEmail(filas.map((m) => m.responsable_email))
  return filas.map((m) => ({
    ...m,
    // 2026-09-04: material_nombre ya viene aplanado por VISTA_STOCK_MOVIMIENTOS_VIVA
    // (antes embed `plantas_materiales(nombre)`, que no funciona sobre una vista).
    materialNombre: m.material_nombre ?? '—',
    // Fix 2026-09-03 (Federico: "falta el campo Responsable" en el
    // historial): los movimientos migrados del histórico legado (memory/
    // pending.md) nunca tuvieron responsable_email — no existía ese dato en
    // el legado, solo un nombre de operador en texto libre. La vista ya
    // resuelve ese fallback en `responsable_texto_legado` (tanto para filas
    // migradas como para las que todavía solo viven en el legado).
    responsableNombre: m.responsable_email
      ? nombresPorEmail[m.responsable_email] ?? m.responsable_email
      : m.responsable_texto_legado
        ? `${m.responsable_texto_legado} (histórico)`
        : '—',
    esIngreso: TIPOS_INGRESO.includes(m.tipo) || m.cantidad_kg > 0,
  }))
}

/**
 * @param {{ materialId?: string, tipo?: string, desde?: string, hasta?: string }} filtros
 */
export async function fetchMovimientos(filtros = {}, { pagina = 1, tamanoPagina = 30 } = {}) {
  const resultado = await fetchPagina(() => queryMovimientos(filtros), { pagina, tamanoPagina })
  return { ...resultado, filas: await enriquecerMovimientos(resultado.filas) }
}

/**
 * Todos los movimientos que matchean el filtro, sin paginar — usado por el
 * botón "Excel" de la tab "Historial de ingresos" de Stock (memory/
 * architecture.md, regla de paginación: fetchPaginado(), no un .select()
 * sin límite).
 */
export async function fetchTodosLosMovimientos(filtros = {}) {
  const filas = await fetchPaginado(() => queryMovimientos(filtros))
  return enriquecerMovimientos(filas)
}

// ---------------------------------------------------------------------------
// Movimientos manuales + relevamiento (RPC, migración 13)
// ---------------------------------------------------------------------------

/**
 * @param {{ materialId: string, tipo: 'ingreso_manual'|'egreso_manual', cantidadKg: number,
 *   origen?: string, numeroRemito?: string, observaciones?: string }} datos
 */
export async function registrarMovimientoManual({ materialId, tipo, cantidadKg, origen, numeroRemito, observaciones }) {
  const { data, error } = await supabase.rpc('registrar_movimiento_manual', {
    p_material_id: materialId,
    p_tipo: tipo,
    p_cantidad_kg: Number(cantidadKg),
    p_origen: origen || null,
    p_numero_remito: numeroRemito || null,
    p_observaciones: observaciones || null,
  })
  if (error) throw error
  return data
}

/**
 * Relevamiento mensual — NO pisa el stock directo (decisión de Federico,
 * 2026-08-31): la RPC calcula la diferencia contra plantas_stock e inserta
 * un movimiento 'ajuste' por cada material que cambió. Puede rechazar el
 * guardado completo (saveStockGuard) si el resultado parece anómalo.
 *
 * @param {Array<{ materialId: string, cantidadKg: number }>} conteos
 * @param {string} [motivo]
 */
export async function registrarRelevamiento(conteos, motivo) {
  const payload = conteos.map((c) => ({ material_id: c.materialId, cantidad_kg: Number(c.cantidadKg) }))
  const { data, error } = await supabase.rpc('registrar_relevamiento_stock', {
    p_conteos: payload,
    p_motivo: motivo || 'Relevamiento mensual',
  })
  if (error) throw error
  return data ?? []
}
