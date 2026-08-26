// Service de Báscula/Vales — único punto de acceso a Supabase para
// plantas_vales. Ningún componente .vue debe importar `supabase` directamente
// (memory/conventions.md).
//
// plantas_vales es historial que crece sin límite: fetchHistorialVales() usa
// fetchPaginado() (memory/architecture.md, regla de paginación).

import { supabase } from '@/config/supabase'
import { fetchPaginado } from '@/services/fetch-paginado'

const TABLA = 'plantas_vales'
const TABLA_PEDIDOS = 'plantas_pedidos'

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
    .from(TABLA_PEDIDOS)
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
 * guardada.
 */
export async function obtenerAcumuladoObraHastaFecha(obraId, fechaCorte) {
  const corte = new Date(fechaCorte)
  const inicioDia = new Date(corte)
  inicioDia.setHours(0, 0, 0, 0)

  const { data, error } = await supabase
    .from(TABLA)
    .select('peso_neto, unidad')
    .eq('obra_id', obraId)
    .eq('tipo_vale', 'asfalto')
    .gte('fecha_pesada', inicioDia.toISOString())
    .lte('fecha_pesada', corte.toISOString())

  if (error) throw error

  return (data ?? []).reduce((acumulado, vale) => acumulado + aTn(vale.peso_neto, vale.unidad), 0)
}

// ---------------------------------------------------------------------------
// Registrar pesada
// ---------------------------------------------------------------------------

/**
 * @param {{
 *   tipo_vale: 'asfalto'|'hormigon'|'ingreso_arido',
 *   pedido_id?: string, obra_id?: number, patente?: string, chofer?: string,
 *   peso_bruto: number, tara: number, unidad?: 'tn'|'kg', observaciones?: string,
 *   fecha_pesada?: string|Date,
 * }} valeData
 */
export async function registrarPesada(valeData) {
  const pesoBruto = Number(valeData.peso_bruto)
  const tara = Number(valeData.tara)

  if (!(pesoBruto > 0)) throw new Error('registrarPesada: peso_bruto debe ser mayor a 0')
  if (!(tara >= 0)) throw new Error('registrarPesada: tara no puede ser negativa')
  if (!(pesoBruto > tara)) throw new Error('registrarPesada: el peso bruto debe ser mayor que la tara')

  const pesoNeto = pesoBruto - tara
  const unidad = valeData.unidad || 'tn'
  const fechaPesada = valeData.fecha_pesada ? new Date(valeData.fecha_pesada) : new Date()

  let pedido = null
  if (valeData.pedido_id) {
    const { data, error } = await supabase.from(TABLA_PEDIDOS).select('*').eq('id', valeData.pedido_id).single()
    if (error) throw error
    pedido = data
  }

  const obraId = valeData.obra_id ?? pedido?.obra_id ?? null

  // El acumulado que se guarda acá es una foto al momento de pesar, a título
  // informativo. El remito impreso NUNCA lo lee de esta columna: siempre lo
  // recalcula con obtenerAcumuladoObraHastaFecha() (memory/business-rules.md,
  // "Acumulado del vale: calculado dinámico, no guardado").
  let acumuladoObraTn = null
  if (obraId && valeData.tipo_vale === 'asfalto') {
    const acumuladoPrevio = await obtenerAcumuladoObraHastaFecha(obraId, fechaPesada)
    acumuladoObraTn = acumuladoPrevio + aTn(pesoNeto, unidad)
  }

  const { data: vale, error: errorInsert } = await supabase
    .from(TABLA)
    .insert({
      tipo_vale: valeData.tipo_vale,
      pedido_id: valeData.pedido_id ?? null,
      obra_id: obraId,
      patente: valeData.patente ?? null,
      chofer: valeData.chofer ?? null,
      peso_bruto: pesoBruto,
      tara,
      peso_neto: pesoNeto,
      unidad,
      acumulado_obra_tn: acumuladoObraTn,
      fecha_pesada: fechaPesada.toISOString(),
      observaciones: valeData.observaciones ?? null,
    })
    .select()
    .single()

  if (errorInsert) throw errorInsert

  // Actualiza cantidad_despachada del pedido (solo vales de asfalto atados a
  // un pedido). Si esta pesada cubre lo solicitado, el pedido pasa a
  // despachado — mismo criterio que el despacho manual del módulo Pedidos.
  if (pedido && valeData.tipo_vale === 'asfalto') {
    const nuevaCantidadDespachada = Number(pedido.cantidad_despachada ?? 0) + aTn(pesoNeto, unidad)
    const cambios = { cantidad_despachada: nuevaCantidadDespachada }
    if (nuevaCantidadDespachada >= Number(pedido.cantidad_solicitada)) {
      cambios.estado = 'despachado'
    }
    const { error: errorPedido } = await supabase.from(TABLA_PEDIDOS).update(cambios).eq('id', pedido.id)
    if (errorPedido) throw errorPedido
  }

  // Si es ingreso de áridos, además del vale (evidencia del pesaje) se
  // registra el ingreso en plantas_ingresos — es la fuente ÚNICA que lee la
  // analítica de proveedores del Dashboard (evita duplicar entre vale e
  // ingreso, ver memory/pending.md "CAMBIO 7"). Se guarda la cantidad
  // DECLARADA en el remito, no el peso neto pesado (memory/business-rules.md:
  // "se suma la cantidad del remito, no el peso neto de la báscula").
  if (valeData.tipo_vale === 'ingreso_arido') {
    if (!valeData.material || !valeData.proveedor) {
      throw new Error('registrarPesada: un ingreso de áridos necesita material y proveedor')
    }
    const { error: errorIngreso } = await supabase.from('plantas_ingresos').insert({
      material: valeData.material,
      proveedor: valeData.proveedor,
      numero_remito: valeData.numero_remito || null,
      cantidad: valeData.cantidad_remito ?? aTn(pesoNeto, unidad),
      unidad: 'tn',
      origen: 'bascula',
      vale_id: vale.id,
      fecha_ingreso: fechaPesada.toISOString(),
      observaciones: valeData.observaciones ?? null,
    })
    if (errorIngreso) throw errorIngreso
  }

  // TODO(stock): acá debería descontarse del stock el consumo de insumos de
  // la fórmula del pedido × peso neto despachado (memory/business-rules.md).
  // No se persiste todavía porque el módulo Stock (memory/modules-status.md
  // #4) no existe: no hay tabla plantas_stock ni service. Este es el punto de
  // integración cuando exista.

  return vale
}

// ---------------------------------------------------------------------------
// Historial (paginado)
// ---------------------------------------------------------------------------

/**
 * @param {{ tipoVale?: string, obraId?: number, patente?: string, desde?: string, hasta?: string }} filtros
 */
export async function fetchHistorialVales(filtros = {}) {
  return fetchPaginado(() => {
    let query = supabase.from(TABLA).select('*').order('fecha_pesada', { ascending: false })

    if (filtros.tipoVale) query = query.eq('tipo_vale', filtros.tipoVale)
    if (filtros.obraId) query = query.eq('obra_id', filtros.obraId)
    if (filtros.patente) query = query.ilike('patente', `%${filtros.patente}%`)
    if (filtros.desde) query = query.gte('fecha_pesada', filtros.desde)
    if (filtros.hasta) query = query.lte('fecha_pesada', filtros.hasta)

    return query
  })
}
