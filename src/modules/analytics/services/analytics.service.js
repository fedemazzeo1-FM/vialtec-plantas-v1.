// Service de Analítica/Dashboard — único punto de acceso a Supabase para las
// consultas gerenciales. Ningún componente .vue debe importar `supabase`
// directamente (memory/conventions.md).
//
// Tablas nuevas que este módulo necesita y no existían todavía (ver migración
// 05 y memory/pending.md):
//   - plantas_ingresos: fuente ÚNICA de ingresos de insumos (manual o vía
//     báscula), para que la analítica de proveedores no tenga que mergear dos
//     tablas y arriesgarse a duplicar un mismo ingreso (CAMBIO 7).
//   - plantas_cargas_hormigon: despacho por camión de hormigón con remito
//     real (hormigón no pasa por báscula, así que no está en plantas_vales).
//   - vista plantas_v_despachos_camion: UNION de asfalto (plantas_vales) +
//     hormigón (plantas_cargas_hormigon) con numero_remito siempre presente
//     para los dos materiales (CAMBIO 8), definida en la migración.

import { supabase } from '@/config/supabase'
import { fetchPaginado } from '@/services/fetch-paginado'

function aTn(valor, unidad) {
  const n = Number(valor) || 0
  return unidad === 'kg' ? n / 1000 : n
}

// ---------------------------------------------------------------------------
// Resumen general (KPIs del mes)
// ---------------------------------------------------------------------------

function rangoDelMes(fechaRef = new Date()) {
  const inicio = new Date(fechaRef.getFullYear(), fechaRef.getMonth(), 1)
  const fin = new Date(fechaRef.getFullYear(), fechaRef.getMonth() + 1, 0, 23, 59, 59, 999)
  return { inicio, fin }
}

/**
 * KPIs principales: Total Asfalto (tn), Total Hormigón (m³), Despachos del
 * mes (cantidad) e Ingresos de insumos (tn) — todo acotado al mes de `mes`
 * (por defecto, el actual).
 */
export async function fetchResumenGeneral({ mes } = {}) {
  const { inicio, fin } = rangoDelMes(mes ? new Date(mes) : new Date())
  const desdeISO = inicio.toISOString()
  const hastaISO = fin.toISOString()

  // Fix 2026-09-01 (regla de paginación): acotadas a un mes, hoy muy lejos
  // de 1000 filas — pero se usa fetchPaginado() igual, por consistencia con
  // totalesPorProveedor() (misma tabla `plantas_ingresos`, mismo tipo de
  // query) y para no depender de que el volumen mensual real de la planta
  // se mantenga bajo para siempre.
  const [pedidosDespachados, ingresos] = await Promise.all([
    fetchPaginado(() =>
      supabase
        .from('plantas_pedidos')
        .select('tipo, cantidad_despachada')
        .eq('estado', 'despachado')
        .gte('fecha_programada', desdeISO.slice(0, 10))
        .lte('fecha_programada', hastaISO.slice(0, 10))
    ),
    fetchPaginado(() =>
      supabase.from('plantas_ingresos').select('cantidad, unidad').gte('fecha_ingreso', desdeISO).lte('fecha_ingreso', hastaISO)
    ),
  ])

  let asfaltoTn = 0
  let hormigonM3 = 0
  for (const p of pedidosDespachados) {
    const cantidad = Number(p.cantidad_despachada) || 0
    if (p.tipo === 'hormigon') hormigonM3 += cantidad
    else asfaltoTn += cantidad
  }

  const ingresosInsumosTn = ingresos.reduce((acc, i) => acc + aTn(i.cantidad, i.unidad), 0)

  return {
    rango: { desde: desdeISO.slice(0, 10), hasta: hastaISO.slice(0, 10) },
    asfaltoTn,
    hormigonM3,
    despachosDelMes: pedidosDespachados.length,
    ingresosInsumosTn,
  }
}

// ---------------------------------------------------------------------------
// Analítica de proveedores (CAMBIO 7)
// ---------------------------------------------------------------------------

function normalizarRango({ desde, hasta } = {}) {
  const hoy = new Date()
  const inicioMesActual = new Date(hoy.getFullYear(), hoy.getMonth(), 1)
  return {
    desde: desde ? new Date(desde) : inicioMesActual,
    hasta: hasta ? new Date(`${hasta}T23:59:59`) : hoy,
  }
}

/** Mismo largo de período, inmediatamente anterior al [desde, hasta] dado. */
function periodoAnterior(desde, hasta) {
  const duracionMs = hasta.getTime() - desde.getTime()
  const hastaAnterior = new Date(desde.getTime() - 1)
  const desdeAnterior = new Date(hastaAnterior.getTime() - duracionMs)
  return { desde: desdeAnterior, hasta: hastaAnterior }
}

/**
 * Totales por proveedor en un rango. Lee ÚNICAMENTE plantas_ingresos: como es
 * la fuente única (manual + báscula, sin registrar el mismo ingreso dos
 * veces — ver registrarPesada en bascula.service.js), sumar acá no duplica
 * nada por construcción. Esto es lo que corrige CAMBIO 7.
 */
async function totalesPorProveedor(desde, hasta) {
  const filas = await fetchPaginado(() =>
    supabase
      .from('plantas_ingresos')
      .select('proveedor, cantidad, unidad')
      .gte('fecha_ingreso', desde.toISOString())
      .lte('fecha_ingreso', hasta.toISOString())
  )

  const totales = new Map()
  for (const fila of filas) {
    const tn = aTn(fila.cantidad, fila.unidad)
    totales.set(fila.proveedor, (totales.get(fila.proveedor) ?? 0) + tn)
  }
  return totales
}

/**
 * @param {{ desde?: string, hasta?: string }} rangoFechas — 'YYYY-MM-DD'. Por
 *   defecto, el mes en curso.
 */
export async function fetchAnaliticaProveedores(rangoFechas = {}) {
  const { desde, hasta } = normalizarRango(rangoFechas)
  const { desde: desdeAnterior, hasta: hastaAnterior } = periodoAnterior(desde, hasta)

  const [actual, anterior] = await Promise.all([
    totalesPorProveedor(desde, hasta),
    totalesPorProveedor(desdeAnterior, hastaAnterior),
  ])

  const proveedores = new Set([...actual.keys(), ...anterior.keys()])

  return Array.from(proveedores)
    .map((proveedor) => {
      const cantidadActualTn = actual.get(proveedor) ?? 0
      const cantidadAnteriorTn = anterior.get(proveedor) ?? 0
      const variacionPct =
        cantidadAnteriorTn > 0 ? ((cantidadActualTn - cantidadAnteriorTn) / cantidadAnteriorTn) * 100 : null

      return { proveedor, cantidadActualTn, cantidadAnteriorTn, variacionPct }
    })
    .sort((a, b) => b.cantidadActualTn - a.cantidadActualTn)
}

// ---------------------------------------------------------------------------
// Detalle de despachos por camión (CAMBIO 8)
// ---------------------------------------------------------------------------

/**
 * @param {{ material?: 'asfalto'|'hormigon', obraId?: number, desde?: string, hasta?: string }} filtros
 */
export async function fetchDetalleDespachosCamion(filtros = {}) {
  // La vista plantas_v_despachos_camion (migración 05) garantiza por
  // construcción que numero_remito está presente para asfalto (numero_vale)
  // y para hormigón (numero_remito real) — no hay forma de que falte en
  // ninguno de los dos materiales.
  const filas = await fetchPaginado(() => {
    let query = supabase.from('plantas_v_despachos_camion').select('*').order('fecha', { ascending: false })

    if (filtros.material) query = query.eq('material', filtros.material)
    if (filtros.obraId) query = query.eq('obra_id', filtros.obraId)
    if (filtros.desde) query = query.gte('fecha', filtros.desde)
    if (filtros.hasta) query = query.lte('fecha', filtros.hasta)

    return query
  })

  // La vista no trae formula_id (viene del pedido, no es parte del union de
  // columnas comunes) — se resuelve con una query chica aparte en vez de un
  // embed de PostgREST, que no funciona a través de una vista con UNION.
  //
  // Fix 2026-09-01 (regla de paginación): `filas` ya viene de fetchPaginado()
  // arriba, así que sin fecha/filtro puede ser TODO el historial de
  // despachos — `pedidoIds` podía superar largamente 1000 ids únicos y esta
  // query, aunque el .in() acote por pedido, seguía sujeta al mismo corte
  // silencioso de PostgREST en la respuesta (formulaId quedaba null para los
  // pedidos que no entraban en las primeras 1000 filas). Se trocea en lotes
  // de 500 ids — evita el corte Y una URL de .in() demasiado larga.
  const TAMANO_LOTE_IN = 500
  const pedidoIds = [...new Set(filas.map((f) => f.pedido_id).filter(Boolean))]
  let formulaIdPorPedido = new Map()
  if (pedidoIds.length) {
    const lotes = []
    for (let i = 0; i < pedidoIds.length; i += TAMANO_LOTE_IN) {
      lotes.push(pedidoIds.slice(i, i + TAMANO_LOTE_IN))
    }
    const resultados = await Promise.all(
      lotes.map((lote) => supabase.from('plantas_pedidos').select('id, formula_id').in('id', lote))
    )
    for (const { data, error } of resultados) {
      if (error) throw error
      for (const p of data ?? []) formulaIdPorPedido.set(p.id, p.formula_id)
    }
  }

  return filas.map((f) => ({
    ...f,
    formulaId: f.pedido_id ? formulaIdPorPedido.get(f.pedido_id) ?? null : null,
  }))
}
