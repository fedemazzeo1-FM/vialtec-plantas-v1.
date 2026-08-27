// Service de Báscula/Vales — único punto de acceso a Supabase para
// plantas_vales. Ningún componente .vue debe importar `supabase` directamente
// (memory/conventions.md).
//
// registrarPesada() llama a la RPC registrar_pesada_bascula (ver
// supabase/migrations/07_roles_y_rpc_atomicas.sql): la lectura del pedido, el
// insert del vale y el update de cantidad_despachada corren atómicos del lado
// del servidor (con lock de fila), en vez del flujo multi-paso que tenía este
// service antes — eso es lo que soluciona la race condition entre slots
// paralelos pesando el mismo pedido (memory/pending.md).
//
// fetchHistorialVales() usa fetchPagina() (paginación server-side): trae solo
// la página que se muestra en UI, no todo el historial a memoria (memory/
// architecture.md, regla de paginación — acá además evita renderizar miles de
// filas de golpe cuando se migre el historial legado).

import { supabase } from '@/config/supabase'
import { fetchPagina } from '@/services/fetch-paginado'

const TABLA = 'plantas_pedidos'

function aTn(valor, unidad) {
  const n = Number(valor) || 0
  return unidad === 'kg' ? n / 1000 : n
}

// ---------------------------------------------------------------------------
// Pedidos de asfalto con saldo pendiente
// ---------------------------------------------------------------------------

/**
 * Pedidos de asfalto, confirmados, con cantidad_despachada < cantidad_solicitada.
 * Excluye por completo hormigón y pedidos cerrados (despachado/cancelado).
 */
export async function fetchPedidosAsfaltoConSaldo() {
  const { data, error } = await supabase
    .from(TABLA)
    .select('*')
    .eq('tipo', 'asfalto')
    .eq('estado', 'confirmado')
    .order('fecha_programada', { ascending: true })

  if (error) throw error

  // PostgREST no compara columna contra columna directamente, así que el
  // filtro cantidad_despachada < cantidad_solicitada se resuelve acá. El
  // universo ya viene acotado por tipo+estado (chico), no hace falta paginar.
  return (data ?? []).filter((p) => Number(p.cantidad_despachada ?? 0) < Number(p.cantidad_solicitada))
}

// ---------------------------------------------------------------------------
// Acumulado dinámico por obra
// ---------------------------------------------------------------------------

/**
 * Suma en tn de los vales de ASFALTO de una obra, del mismo día calendario que
 * `fechaCorte`, con fecha_pesada <= fechaCorte (mismo criterio que el sistema
 * legado: mismo día, obra, hasta este camión — ver memory/business-rules.md).
 * Se recalcula siempre en el momento de usarla, nunca se lee de una columna
 * guardada. Usada para imprimir el remito — la RPC de abajo recalcula lo
 * mismo internamente al registrar la pesada, esta función queda para el
 * momento de imprimir/consultar.
 */
export async function obtenerAcumuladoObraHastaFecha(obraId, fechaCorte) {
  const corte = new Date(fechaCorte)
  const inicioDia = new Date(corte)
  inicioDia.setHours(0, 0, 0, 0)

  const { data, error } = await supabase
    .from('plantas_vales')
    .select('peso_neto, unidad')
    .eq('obra_id', obraId)
    .eq('tipo_vale', 'asfalto')
    .gte('fecha_pesada', inicioDia.toISOString())
    .lte('fecha_pesada', corte.toISOString())

  if (error) throw error

  return (data ?? []).reduce((acumulado, vale) => acumulado + aTn(vale.peso_neto, vale.unidad), 0)
}

// ---------------------------------------------------------------------------
// Registrar pesada (atómico, vía RPC)
// ---------------------------------------------------------------------------

/**
 * @param {{
 *   tipo_vale: 'asfalto'|'hormigon'|'ingreso_arido',
 *   pedido_id?: string, obra_id?: number, patente?: string, chofer?: string,
 *   peso_bruto: number, tara: number, unidad?: 'tn'|'kg', observaciones?: string,
 *   fecha_pesada?: string|Date, material?: string, proveedor?: string,
 *   numero_remito?: string, cantidad_remito?: number,
 * }} valeData
 */
export async function registrarPesada(valeData) {
  const fechaPesada = valeData.fecha_pesada ? new Date(valeData.fecha_pesada) : new Date()

  const { data, error } = await supabase.rpc('registrar_pesada_bascula', {
    p_tipo_vale: valeData.tipo_vale,
    p_peso_bruto: Number(valeData.peso_bruto),
    p_tara: Number(valeData.tara),
    p_pedido_id: valeData.pedido_id ?? null,
    p_obra_id: valeData.obra_id ?? null,
    p_patente: valeData.patente ?? null,
    p_chofer: valeData.chofer ?? null,
    p_unidad: valeData.unidad || 'tn',
    p_observaciones: valeData.observaciones ?? null,
    p_fecha_pesada: fechaPesada.toISOString(),
    p_material: valeData.material ?? null,
    p_proveedor: valeData.proveedor ?? null,
    p_numero_remito: valeData.numero_remito ?? null,
    p_cantidad_remito: valeData.cantidad_remito ?? null,
  })

  if (error) throw error
  return data
}

// ---------------------------------------------------------------------------
// Historial (paginado server-side)
// ---------------------------------------------------------------------------

/**
 * @param {{ tipoVale?: string, obraId?: number, patente?: string, desde?: string, hasta?: string }} filtros
 * @param {{ pagina?: number, tamanoPagina?: number }} opciones
 * @returns {Promise<{ filas: any[], total: number, pagina: number, tamanoPagina: number }>}
 */
export async function fetchHistorialVales(filtros = {}, { pagina = 1, tamanoPagina = 50 } = {}) {
  return fetchPagina(
    () => {
      let query = supabase.from('plantas_vales').select('*', { count: 'exact' }).order('fecha_pesada', { ascending: false })

      if (filtros.tipoVale) query = query.eq('tipo_vale', filtros.tipoVale)
      if (filtros.obraId) query = query.eq('obra_id', filtros.obraId)
      if (filtros.patente) query = query.ilike('patente', `%${filtros.patente}%`)
      if (filtros.desde) query = query.gte('fecha_pesada', filtros.desde)
      if (filtros.hasta) query = query.lte('fecha_pesada', filtros.hasta)

      return query
    },
    { pagina, tamanoPagina }
  )
}
