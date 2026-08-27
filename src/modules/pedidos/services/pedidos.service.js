// Service de Pedidos — único punto de acceso a Supabase para plantas_pedidos.
// Ningún componente .vue debe importar `supabase` directamente: pasa por acá.
//
// fetchPedidos() usa fetchPagina() (paginación server-side): trae solo la
// página que se muestra en UI, no todo el historial a memoria (memory/
// architecture.md, regla de paginación — acá además evita renderizar miles de
// filas de golpe cuando se migre el historial legado). Las consultas
// acotadas a una semana (fetchPedidosSemana/fetchTotalesSemana) no lo
// necesitan (7 días de pedidos no va a superar 1000 filas).
//
// registrarCargaHormigon() llama a la RPC registrar_carga_hormigon (ver
// supabase/migrations/07_roles_y_rpc_atomicas.sql): la lectura/validación del
// pedido, el insert de la carga y el update de cantidad_despachada corren
// atómicos del lado del servidor (con lock de fila) — memory/pending.md.

import { supabase } from '@/config/supabase'
import { fetchPagina } from '@/services/fetch-paginado'

const TABLA = 'plantas_pedidos'
const ESTADOS_COMPROMETIDOS = ['confirmado', 'despachado']

// ---------------------------------------------------------------------------
// Listado / lectura
// ---------------------------------------------------------------------------

/**
 * @param {{ estado?: string, obraId?: number, tipo?: string, desde?: string, hasta?: string, incluirArchivados?: boolean }} filtros
 *   desde/hasta en formato 'YYYY-MM-DD', sobre fecha_programada. Por defecto
 *   excluye archivados (mismo criterio que el sistema legado: la vista
 *   normal no los muestra salvo que se active el toggle).
 * @param {{ pagina?: number, tamanoPagina?: number }} opciones
 * @returns {Promise<{ filas: any[], total: number, pagina: number, tamanoPagina: number }>}
 */
export async function fetchPedidos(filtros = {}, { pagina = 1, tamanoPagina = 50 } = {}) {
  return fetchPagina(
    () => {
      let query = supabase.from(TABLA).select('*', { count: 'exact' }).order('fecha_programada', { ascending: false })

      if (filtros.estado) query = query.eq('estado', filtros.estado)
      if (filtros.obraId) query = query.eq('obra_id', filtros.obraId)
      if (filtros.tipo) query = query.eq('tipo', filtros.tipo)
      if (filtros.desde) query = query.gte('fecha_programada', filtros.desde)
      if (filtros.hasta) query = query.lte('fecha_programada', filtros.hasta)
      if (!filtros.incluirArchivados) query = query.eq('archivado', false)

      return query
    },
    { pagina, tamanoPagina }
  )
}

export async function getPedido(id) {
  const { data, error } = await supabase.from(TABLA).select('*').eq('id', id).single()
  if (error) throw error
  return data
}

// ---------------------------------------------------------------------------
// Plan semanal (lunes a domingo — memory/business-rules.md)
// ---------------------------------------------------------------------------

/** Rango [lunes 00:00, domingo 23:59] de la semana que contiene `fecha`. */
export function obtenerRangoSemana(fecha = new Date()) {
  const d = new Date(fecha)
  const dia = d.getDay() // 0 = domingo … 6 = sábado
  const diffALunes = dia === 0 ? -6 : 1 - dia

  const lunes = new Date(d)
  lunes.setDate(d.getDate() + diffALunes)
  lunes.setHours(0, 0, 0, 0)

  const domingo = new Date(lunes)
  domingo.setDate(lunes.getDate() + 6)
  domingo.setHours(23, 59, 59, 999)

  return { lunes, domingo }
}

function aFechaISO(date) {
  return date.toISOString().slice(0, 10)
}

/**
 * Pedidos de la semana para la matriz del Plan Semanal. Incluye `solicitado`
 * (a diferencia del dashboard) porque esta vista permite confirmarlos ahí
 * mismo. Excluye `cancelado`.
 */
export async function fetchPedidosSemana(fechaReferencia = new Date()) {
  const { lunes, domingo } = obtenerRangoSemana(fechaReferencia)

  const { data, error } = await supabase
    .from(TABLA)
    .select('*')
    .in('estado', ['solicitado', 'confirmado', 'despachado'])
    .gte('fecha_programada', aFechaISO(lunes))
    .lte('fecha_programada', aFechaISO(domingo))
    .order('fecha_programada', { ascending: true })

  if (error) throw error
  return data
}

/**
 * Totales acumulados de la semana, agrupados por obra, en dos métricas
 * paralelas (asfalto en tn, hormigón en m³). Solo cuenta `confirmado` y
 * `despachado` — un pedido `solicitado` todavía no está comprometido (misma
 * regla que las alertas de stock del dashboard, ver memory/business-rules.md).
 * Para un pedido despachado usa cantidad_despachada; si no está informada
 * (no debería pasar) cae a cantidad_solicitada.
 */
export async function fetchTotalesSemana(fechaReferencia = new Date()) {
  const { lunes, domingo } = obtenerRangoSemana(fechaReferencia)

  const { data, error } = await supabase
    .from(TABLA)
    .select('obra_id, tipo, estado, cantidad_solicitada, cantidad_despachada')
    .in('estado', ESTADOS_COMPROMETIDOS)
    .gte('fecha_programada', aFechaISO(lunes))
    .lte('fecha_programada', aFechaISO(domingo))

  if (error) throw error

  const porObra = new Map()
  const total = { asfaltoTn: 0, hormigonM3: 0 }

  for (const pedido of data) {
    const cantidad = Number(
      pedido.estado === 'despachado' ? pedido.cantidad_despachada ?? pedido.cantidad_solicitada : pedido.cantidad_solicitada
    )

    if (!porObra.has(pedido.obra_id)) {
      porObra.set(pedido.obra_id, { obraId: pedido.obra_id, asfaltoTn: 0, hormigonM3: 0 })
    }
    const acumObra = porObra.get(pedido.obra_id)

    if (pedido.tipo === 'hormigon') {
      acumObra.hormigonM3 += cantidad
      total.hormigonM3 += cantidad
    } else {
      acumObra.asfaltoTn += cantidad
      total.asfaltoTn += cantidad
    }
  }

  return {
    rango: { lunes: aFechaISO(lunes), domingo: aFechaISO(domingo) },
    porObra: Array.from(porObra.values()),
    total,
  }
}

// ---------------------------------------------------------------------------
// Alta y cambios de estado
// ---------------------------------------------------------------------------

/**
 * @param {{ obra_id?, formula_id, tipo, cantidad_solicitada, fecha_programada,
 *   observaciones?, tipo_pedido?: 'obra'|'venta', cliente_externo?: string,
 *   encargado?: string }} pedido
 *   obra_id es opcional cuando tipo_pedido='venta' (venta externa sin obra
 *   real — migración 06, memory/business-rules.md).
 */
export async function crearPedido(pedido) {
  const { data, error } = await supabase
    .from(TABLA)
    .insert({ ...pedido, estado: 'solicitado' })
    .select()
    .single()
  if (error) throw error
  return data
}

export async function actualizarPedido(id, cambios) {
  const { data, error } = await supabase.from(TABLA).update(cambios).eq('id', id).select().single()
  if (error) throw error
  return data
}

/** solicitado -> confirmado. Solo plantista/admin (a validar contra rol logueado en la UI). */
export async function confirmarPedido(id, { observaciones } = {}) {
  const cambios = { estado: 'confirmado' }
  if (observaciones !== undefined) cambios.observaciones = observaciones
  return actualizarPedido(id, cambios)
}

/**
 * confirmado -> despachado.
 * TODO: al integrar el módulo Stock, acá va el descuento automático de
 * insumos (fórmula × cantidadDespachada, ver memory/business-rules.md). Por
 * ahora esta función solo cambia el estado del pedido.
 */
export async function despacharPedido(id, cantidadDespachada) {
  if (!(cantidadDespachada > 0)) {
    throw new Error('despacharPedido: cantidadDespachada debe ser mayor a 0')
  }
  return actualizarPedido(id, { estado: 'despachado', cantidad_despachada: cantidadDespachada })
}

/** Cancelado requiere motivo obligatorio (memory/business-rules.md) y no se reactiva. */
export async function cancelarPedido(id, motivo) {
  if (!motivo || !motivo.trim()) {
    throw new Error('cancelarPedido: el motivo es obligatorio')
  }
  return actualizarPedido(id, { estado: 'cancelado', observaciones: motivo })
}

/**
 * Archiva un pedido despachado/cancelado (memory/business-rules.md: los
 * pedidos nunca se eliminan, solo se archivan). La vista normal los excluye
 * por defecto — ver fetchPedidos({ incluirArchivados }).
 */
export async function archivarPedido(id) {
  return actualizarPedido(id, { archivado: true })
}

// ---------------------------------------------------------------------------
// Cargas de hormigón (una por camión/mixer, atómico vía RPC — ver
// supabase/migrations/07_roles_y_rpc_atomicas.sql)
// ---------------------------------------------------------------------------

/**
 * Registra una carga (mixer) de un pedido de hormigón confirmado: la RPC
 * registrar_carga_hormigon valida tipo/estado del pedido, inserta el remito
 * en plantas_cargas_hormigon y acumula cantidad_despachada en el pedido de
 * forma atómica (con lock de fila) — si la suma cubre lo solicitado, el
 * pedido pasa a despachado.
 *
 * @param {{ pedido_id: string, numero_remito: string, volumen_m3: number,
 *   patente_mixer?: string, chofer?: string, fecha_carga?: string|Date,
 *   observaciones?: string }} cargaData
 */
export async function registrarCargaHormigon(cargaData) {
  const fechaCarga = cargaData.fecha_carga ? new Date(cargaData.fecha_carga) : new Date()

  const { data, error } = await supabase.rpc('registrar_carga_hormigon', {
    p_pedido_id: cargaData.pedido_id,
    p_numero_remito: cargaData.numero_remito,
    p_volumen_m3: Number(cargaData.volumen_m3),
    p_patente_mixer: cargaData.patente_mixer || null,
    p_chofer: cargaData.chofer || null,
    p_fecha_carga: fechaCarga.toISOString(),
    p_observaciones: cargaData.observaciones || null,
  })

  if (error) throw error
  return data
}
