// Service de Despachos — único punto de acceso a Supabase para el historial
// de pedidos despachados. Vive en src/services/ (no en src/modules/) porque
// no es dueño de ninguna tabla propia: lee plantas_pedidos (ya administrada
// por pedidos.service.js) desde otro ángulo, más plantas_cargas_asfalto/
// plantas_cargas_hormigon para el detalle por camión. Ningún componente .vue
// debe importar `supabase` directamente (memory/conventions.md).
//
// Fuente de verdad (memory/business-rules.md, regla fijada por Federico
// 2026-08-31): la cantidad REAL/DIFERENCIA de un despacho es SIEMPRE
// plantas_pedidos.cantidad_despachada (cantidadReal cargada en Pedidos desde
// el remito final consolidado) — nunca una suma sobre plantas_vales ni sobre
// plantas_v_despachos_camion. Esa vista/los vales de Báscula son el detalle
// auditable por camión (fetchCargasDelPedido más abajo), no la fuente de
// ningún total. Ver también supabase/migrations/12_despachos_vista_camion_y_correccion.sql.
//
// Despachos es una vista SOBRE pedidos despachados (Logica sist plantas
// v2.rtf §3.5: "es una vista sobre pedidos, estado = despachado"), no una
// entidad propia — no hay tabla plantas_despachos.

import { supabase } from '@/config/supabase'
import { fetchPaginado, fetchPagina } from '@/services/fetch-paginado'

const TABLA_PEDIDOS = 'plantas_pedidos'
const TABLA_HISTORIAL = 'plantas_pedidos_historial'

// ---------------------------------------------------------------------------
// Listado principal (tabla FECHA/OBRA/MEZCLA/PEDIDO/REAL/DIFERENCIA)
// ---------------------------------------------------------------------------

/**
 * @param {{ tipo?: 'asfalto'|'hormigon', obraId?: number, formulaId?: string,
 *   desde?: string, hasta?: string }} filtros desde/hasta en 'YYYY-MM-DD',
 *   sobre fecha_programada (memory/relevamiento: el legado usa `fecha` como
 *   fecha planificada Y de despacho, no hay una fecha "real" separada).
 * @param {{ pagina?: number, tamanoPagina?: number }} opciones
 */
export async function fetchDespachos(filtros = {}, { pagina = 1, tamanoPagina = 20 } = {}) {
  return fetchPagina(
    () => {
      let query = supabase
        .from(TABLA_PEDIDOS)
        .select('*', { count: 'exact' })
        .eq('estado', 'despachado')
        .order('fecha_programada', { ascending: false })

      if (filtros.tipo) query = query.eq('tipo', filtros.tipo)
      if (filtros.obraId) query = query.eq('obra_id', filtros.obraId)
      if (filtros.formulaId) query = query.eq('formula_id', filtros.formulaId)
      if (filtros.desde) query = query.gte('fecha_programada', filtros.desde)
      if (filtros.hasta) query = query.lte('fecha_programada', filtros.hasta)

      return query
    },
    { pagina, tamanoPagina }
  )
}

// ---------------------------------------------------------------------------
// KPIs: acumulado histórico completo (memory/relevamiento-sistema-viejo.md
// §3 — "Total asfalto acumulado"/"Total hormigón acumulado", sin límite de
// fecha, a diferencia del KPI del mes que ya tiene el Dashboard).
// ---------------------------------------------------------------------------

export async function fetchAcumuladoHistorico() {
  const filas = await fetchPaginado(() =>
    supabase.from(TABLA_PEDIDOS).select('tipo, cantidad_despachada').eq('estado', 'despachado')
  )

  let asfaltoTn = 0
  let hormigonM3 = 0
  for (const p of filas) {
    const cantidad = Number(p.cantidad_despachada) || 0
    if (p.tipo === 'hormigon') hormigonM3 += cantidad
    else asfaltoTn += cantidad
  }
  return { asfaltoTn, hormigonM3 }
}

function rangoDelMes(mes) {
  // `mes` en formato 'YYYY-MM' (valor crudo de <input type="month">).
  const [anio, mesNum] = mes.split('-').map(Number)
  const inicio = new Date(anio, mesNum - 1, 1)
  const fin = new Date(anio, mesNum, 0)
  const aISO = (d) => d.toISOString().slice(0, 10)
  return { desde: aISO(inicio), hasta: aISO(fin) }
}

/** KPI del mes en curso — mismo criterio que fetchAcumuladoHistorico pero acotado. */
export async function fetchTotalesMes(mes) {
  const { desde, hasta } = rangoDelMes(mes)
  const filas = await fetchPaginado(() =>
    supabase
      .from(TABLA_PEDIDOS)
      .select('tipo, cantidad_despachada')
      .eq('estado', 'despachado')
      .gte('fecha_programada', desde)
      .lte('fecha_programada', hasta)
  )
  let asfaltoTn = 0
  let hormigonM3 = 0
  for (const p of filas) {
    const cantidad = Number(p.cantidad_despachada) || 0
    if (p.tipo === 'hormigon') hormigonM3 += cantidad
    else asfaltoTn += cantidad
  }
  return { asfaltoTn, hormigonM3 }
}

// ---------------------------------------------------------------------------
// Resumen por obra (selector de mes + grid de cards — memory/relevamiento
// §3 Etapa 3: "<input type='month'>", no rango libre)
// ---------------------------------------------------------------------------

/**
 * @param {string} mes 'YYYY-MM'
 * @returns {Promise<Array<{ obraId: number|null, asfaltoTn: number, hormigonM3: number, cantidadDespachos: number }>>}
 */
export async function fetchResumenPorObra(mes) {
  const { desde, hasta } = rangoDelMes(mes)
  const filas = await fetchPaginado(() =>
    supabase
      .from(TABLA_PEDIDOS)
      .select('obra_id, tipo, cantidad_despachada, tipo_pedido, cliente_externo')
      .eq('estado', 'despachado')
      .gte('fecha_programada', desde)
      .lte('fecha_programada', hasta)
  )

  const porObra = new Map()
  for (const p of filas) {
    // Ventas externas (sin obra_id) se agrupan por nombre de cliente, igual
    // que el criterio ya usado para vales sin pedido (memory/business-rules.md).
    const clave = p.obra_id ?? `venta:${p.cliente_externo || 'sin nombre'}`
    if (!porObra.has(clave)) {
      porObra.set(clave, {
        obraId: p.obra_id,
        clienteExterno: p.obra_id ? null : p.cliente_externo || 'Venta externa',
        asfaltoTn: 0,
        hormigonM3: 0,
        cantidadDespachos: 0,
      })
    }
    const acc = porObra.get(clave)
    const cantidad = Number(p.cantidad_despachada) || 0
    if (p.tipo === 'hormigon') acc.hormigonM3 += cantidad
    else acc.asfaltoTn += cantidad
    acc.cantidadDespachos += 1
  }

  return Array.from(porObra.values()).sort((a, b) => b.asfaltoTn + b.hormigonM3 - (a.asfaltoTn + a.hormigonM3))
}

// ---------------------------------------------------------------------------
// Detalle de cargas de un despacho (modal 🚛 "Ver detalle de cargas") — se
// lee directo de plantas_cargas_asfalto/plantas_cargas_hormigon (lo que
// Pedidos registró al cerrar el despacho), NO de plantas_v_despachos_camion
// ni de plantas_vales: memory/business-rules.md, Pedidos es la fuente de
// verdad del despacho, Báscula es auditoría aparte.
// ---------------------------------------------------------------------------

/**
 * @param {string} pedidoId
 * @param {'asfalto'|'hormigon'} tipo
 * @returns {Promise<Array<{ id, patente, cantidad, numeroRemitoOVale, fecha, fuente: 'cargas'|'bascula' }>>}
 */
export async function fetchCargasDelPedido(pedidoId, tipo) {
  const tabla = tipo === 'hormigon' ? 'plantas_cargas_hormigon' : 'plantas_cargas_asfalto'
  const { data, error } = await supabase
    .from(tabla)
    .select('*')
    .eq('pedido_id', pedidoId)
    .order('fecha_carga', { ascending: true })
  if (error) throw error

  // Normaliza a una forma común (cantidad + numeroRemitoOVale) para que el
  // modal no tenga que conocer las columnas específicas de cada tabla.
  const cargas = (data ?? []).map((c) => ({
    id: c.id,
    patente: tipo === 'hormigon' ? c.patente_mixer : c.patente,
    cantidad: tipo === 'hormigon' ? c.volumen_m3 : c.cantidad_tn,
    numeroRemitoOVale: tipo === 'hormigon' ? c.numero_remito : c.numero_vale,
    fecha: c.fecha_carga,
    fuente: 'cargas',
  }))
  if (cargas.length || tipo === 'hormigon') return cargas

  // Fallback a Báscula (2026-09-02, roadmap Mobile — gap real encontrado al
  // auditar la comparativa "Real vs. Pedido" del legado): los despachos de
  // asfalto migrados del histórico legado (memory/pending.md, migración
  // 2026-09-01) NO tienen filas en plantas_cargas_asfalto — ese detalle por
  // camión nunca se guardó ahí en el legado, no fue un dato perdido en la
  // migración. `plantas_vales` SÍ se migró completo (885 vales) y tiene el
  // mismo patrón camión-por-fila — es exactamente el "detalle auditable por
  // camión" que memory/business-rules.md ya documenta para Báscula. Se usa
  // como fallback, nunca como fuente de la cantidad oficial (esa sigue
  // siendo siempre `cantidad_despachada`, ver comentario de archivo).
  return fetchValesDelPedido(pedidoId).then((vales) =>
    vales.map((v) => ({
      id: v.id,
      patente: v.patente,
      cantidad: v.pesoNetoTn,
      numeroRemitoOVale: v.numeroVale,
      fecha: v.fechaPesada,
      fuente: 'bascula',
    }))
  )
}

/**
 * Vales de báscula (asfalto) asociados a un pedido — usado por el fallback
 * de fetchCargasDelPedido() de arriba y por el selector "Imprimir vale" de
 * Despachos (reusa el mismo dato, no se duplica la query).
 * @param {string} pedidoId
 */
/**
 * Vale completo por id (todas las columnas de plantas_vales) — para el
 * selector "Imprimir vale" de Despachos, que reusa ValeImprimible.vue tal
 * cual lo arma useBascula.js (mismas props, mismo componente, memory/
 * conventions.md: no duplicar el imprimible).
 * @param {string} valeId
 */
export async function fetchValeCompleto(valeId) {
  const { data, error } = await supabase.from('plantas_vales').select('*').eq('id', valeId).single()
  if (error) throw error
  return data
}

export async function fetchValesDelPedido(pedidoId) {
  const { data, error } = await supabase
    .from('plantas_vales')
    .select('id, numero_vale, patente, peso_neto, unidad, fecha_pesada')
    .eq('pedido_id', pedidoId)
    .eq('tipo_vale', 'asfalto')
    .order('fecha_pesada', { ascending: true })
  if (error) throw error
  return (data ?? []).map((v) => ({
    id: v.id,
    numeroVale: v.numero_vale,
    patente: v.patente,
    pesoNetoTn: v.unidad === 'kg' ? Number(v.peso_neto) / 1000 : Number(v.peso_neto),
    fechaPesada: v.fecha_pesada,
  }))
}

// ---------------------------------------------------------------------------
// Corrección post-despacho (Logica sis. plantas v1.rtf §5, RPC atómica —
// supabase/migrations/12_despachos_vista_camion_y_correccion.sql)
// ---------------------------------------------------------------------------

/**
 * @param {string} pedidoId
 * @param {{ cantidadDespachada?: number, nroRemitoGlobal?: string, nroValeGlobal?: string, notas?: string }} cambios
 */
export async function corregirDespacho(pedidoId, cambios) {
  const { data, error } = await supabase.rpc('corregir_despacho', {
    p_pedido_id: pedidoId,
    p_cantidad_despachada: cambios.cantidadDespachada ?? null,
    p_nro_remito_global: cambios.nroRemitoGlobal ?? null,
    p_nro_vale_global: cambios.nroValeGlobal ?? null,
    p_notas: cambios.notas || null,
  })
  if (error) throw error
  return data
}
