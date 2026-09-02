// Service de Pedidos — único punto de acceso a Supabase para plantas_pedidos
// y plantas_pedidos_historial. Ningún componente .vue debe importar
// `supabase` directamente: pasa por acá.
//
// fetchPedidos() usa fetchPagina() (paginación server-side): trae solo la
// página que se muestra en UI, no todo el historial a memoria (memory/
// architecture.md, regla de paginación — acá además evita renderizar miles de
// filas de golpe cuando se migre el historial legado). Las consultas
// acotadas a una semana (fetchPedidosSemana/fetchTotalesSemana) no lo
// necesitan (7 días de pedidos no va a superar 1000 filas).
//
// registrarCargaHormigon()/registrarCargaAsfalto() llaman a sus RPC (ver
// supabase/migrations/07_roles_y_rpc_atomicas.sql, extendidas en la 09 y 11):
// la lectura/validación del pedido, el insert de la carga y el update de
// cantidad_despachada corren atómicos del lado del servidor (con lock de
// fila) — memory/pending.md. Desde la migración 11, esas dos RPC NO cierran
// el pedido — eso lo hace finalizarDespacho(), que es quien decide si el
// despacho fue completo o parcial (con o sin pedido residual).
//
// Escritura sobre plantas_pedidos (migración 16, "lock down" de seguridad):
// crearPedido/actualizarPedido/confirmarPedido/cancelarPedido/archivarPedido
// van TODOS por RPC (crear_pedido/actualizar_pedido/confirmar_pedido/
// cancelar_pedido/archivar_pedido) — plantas_pedidos ya no acepta
// INSERT/UPDATE directo desde el cliente (RLS: solo SELECT para
// `authenticated`, la escritura queda exclusiva de funciones SECURITY
// DEFINER). Cada RPC valida rol + transición de estado server-side y
// escribe su evento de historial de forma atómica en la misma transacción
// — ya no hace falta el helper registrarHistorial() de acá (se eliminó,
// quedaba sin uso).

import { supabase } from '@/config/supabase'
import { fetchPagina, fetchPaginado } from '@/services/fetch-paginado'

const TABLA = 'plantas_pedidos'
const TABLA_HISTORIAL = 'plantas_pedidos_historial'
const ESTADOS_COMPROMETIDOS = ['confirmado', 'despachado']

// ---------------------------------------------------------------------------
// Historial (append-only, solo lectura desde el cliente — memory/business-rules.md)
// ---------------------------------------------------------------------------

/**
 * Timeline completo de un pedido, más viejo primero (memory/relevamiento-
 * sistema-viejo.md §1 — modal "Historial del pedido").
 */
export async function fetchHistorialPedido(pedidoId) {
  const { data, error } = await supabase
    .from(TABLA_HISTORIAL)
    .select('*')
    .eq('pedido_id', pedidoId)
    .order('fecha_evento', { ascending: true })
  if (error) throw error
  return data ?? []
}

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

const ESTADOS_CONTEO = ['solicitado', 'confirmado', 'despachado', 'postergado', 'cancelado']

/**
 * Conteo de pedidos NO archivados por estado — para los 5 KPI de arriba de
 * la vista (memory/relevamiento-sistema-viejo.md §1: "KPIs arriba: SOLICITADO,
 * CONFIRMADO, DESPACHADO, POSTERGADO, CANCELADO"). 5 `count: 'exact', head:
 * true` en paralelo — cada uno es un COUNT(*) real de Postgres, no lee filas,
 * así que no aplica el límite de 1000 de PostgREST (memory/architecture.md).
 */
export async function fetchConteoEstados() {
  const resultados = await Promise.all(
    ESTADOS_CONTEO.map((estado) => supabase.from(TABLA).select('id', { count: 'exact', head: true }).eq('estado', estado).eq('archivado', false))
  )
  const conteo = {}
  ESTADOS_CONTEO.forEach((estado, i) => {
    if (resultados[i].error) throw resultados[i].error
    conteo[estado] = resultados[i].count ?? 0
  })
  return conteo
}

/**
 * Resumen del PERÍODO filtrado (2026-09-01, pedido de Federico): a
 * diferencia de fetchConteoEstados() (siempre global, todo el histórico no
 * archivado), esto acota por desde/hasta/obraId/incluirArchivados — los
 * mismos filtros que fetchPedidos(), salvo `estado`/`tipo` (el resumen
 * siempre muestra el desglose completo por estado y por material,
 * independiente de qué tab/estado esté mirando la lista de abajo, mismo
 * criterio que el resumen de PlanSemanalView). No usa fetchConteoEstados()
 * por dentro porque ese es fijo a "todo, sin fecha" — acá se arma de nuevo
 * con el rango.
 *
 * @param {{ desde?: string, hasta?: string, obraId?: number, incluirArchivados?: boolean }} filtros
 * @returns {Promise<{ conteoEstados: Record<string, number>, asfaltoTn: number, hormigonM3: number }>}
 */
export async function fetchResumenPeriodo(filtros = {}) {
  const conteo = Object.fromEntries(ESTADOS_CONTEO.map((e) => [e, 0]))

  const filas = await fetchPaginado(() => {
    let query = supabase.from(TABLA).select('tipo, estado, cantidad_solicitada, cantidad_despachada')
    if (!filtros.incluirArchivados) query = query.eq('archivado', false)
    if (filtros.obraId) query = query.eq('obra_id', filtros.obraId)
    if (filtros.desde) query = query.gte('fecha_programada', filtros.desde)
    if (filtros.hasta) query = query.lte('fecha_programada', filtros.hasta)
    return query
  })

  let asfaltoTn = 0
  let hormigonM3 = 0
  for (const p of filas) {
    if (Object.prototype.hasOwnProperty.call(conteo, p.estado)) conteo[p.estado] += 1
    // Mismo criterio que fetchTotalesSemana(): despachado usa cantidad_despachada
    // (cantidadReal), el resto usa cantidad_solicitada — un pedido todavía no
    // despachado no tiene "real" que sumar.
    const cantidad = Number(p.estado === 'despachado' ? p.cantidad_despachada ?? p.cantidad_solicitada : p.cantidad_solicitada) || 0
    if (p.tipo === 'hormigon') hormigonM3 += cantidad
    else asfaltoTn += cantidad
  }

  return { conteoEstados: conteo, asfaltoTn, hormigonM3 }
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
 * Crea un pedido en estado solicitado + su primer evento de historial, de
 * forma atómica vía RPC (migración 16 — plantas_pedidos ya no acepta INSERT
 * directo desde el cliente).
 *
 * @param {{ obra_id?, formula_id, cantidad_solicitada, fecha_programada,
 *   observaciones?, tipo_pedido?: 'obra'|'venta', cliente_externo?: string,
 *   encargado?: string, ubicacion?: string }} pedido
 *   obra_id es opcional cuando tipo_pedido='venta' (venta externa sin obra
 *   real — migración 06, memory/business-rules.md). ubicacion es texto libre
 *   opcional (migración 09, memory/relevamiento-sistema-viejo.md §1). `tipo`
 *   ya no se manda: la RPC lo deriva de la fórmula elegida.
 * @param {{ usuarioLegado?: string }} opciones nombre para mostrar en el
 *   historial (la vista lo saca de authStore.nombre — el service no depende
 *   de Pinia, memory/conventions.md).
 */
export async function crearPedido(pedido, { usuarioLegado } = {}) {
  const { data, error } = await supabase.rpc('crear_pedido', {
    p_formula_id: pedido.formula_id,
    p_cantidad_solicitada: pedido.cantidad_solicitada,
    p_fecha_programada: pedido.fecha_programada,
    p_obra_id: pedido.obra_id ?? null,
    p_tipo_pedido: pedido.tipo_pedido || 'obra',
    p_cliente_externo: pedido.cliente_externo ?? null,
    p_encargado: pedido.encargado ?? null,
    p_ubicacion: pedido.ubicacion ?? null,
    p_observaciones: pedido.observaciones ?? null,
    p_usuario_legado: usuarioLegado || null,
  })
  if (error) throw error
  return data
}

/**
 * Edita los campos generales de un pedido solicitado/confirmado (no cambia
 * estado, no genera historial) vía RPC — mismo set de campos que el form
 * "Editar pedido" (memory/conventions.md: la vista manda el objeto completo,
 * no un patch parcial, ver usePedidos.js#guardarEdicion).
 */
export async function actualizarPedido(id, cambios) {
  const { data, error } = await supabase.rpc('actualizar_pedido', {
    p_pedido_id: id,
    p_formula_id: cambios.formula_id,
    p_cantidad_solicitada: cambios.cantidad_solicitada,
    p_fecha_programada: cambios.fecha_programada,
    p_obra_id: cambios.obra_id ?? null,
    p_tipo_pedido: cambios.tipo_pedido || 'obra',
    p_cliente_externo: cambios.cliente_externo ?? null,
    p_encargado: cambios.encargado ?? null,
    p_ubicacion: cambios.ubicacion ?? null,
    p_observaciones: cambios.observaciones ?? null,
  })
  if (error) throw error
  return data
}

/** solicitado|postergado -> confirmado. Solo plantista/admin, validado server-side en la RPC. */
export async function confirmarPedido(id, { observaciones, usuarioLegado } = {}) {
  const { data, error } = await supabase.rpc('confirmar_pedido', {
    p_pedido_id: id,
    p_observaciones: observaciones ?? null,
    p_usuario_legado: usuarioLegado || null,
  })
  if (error) throw error
  return data
}

/**
 * solicitado|confirmado -> postergado, vía RPC atómica (necesita leer
 * fecha_programada "antes" de forma consistente para guardarla en el
 * historial — no se puede hacer en dos pasos desde el cliente sin una
 * carrera). fechaNueva y motivo son opcionales, igual que el modal real
 * (memory/relevamiento-sistema-viejo.md Etapa 3).
 */
export async function postergarPedido(id, { fechaNueva, motivo } = {}) {
  const { data, error } = await supabase.rpc('postergar_pedido', {
    p_pedido_id: id,
    p_fecha_nueva: fechaNueva || null,
    p_motivo: motivo || null,
  })
  if (error) throw error
  return data
}

// NOTA: no hay un despacharPedido(id, cantidad) genérico acá — el despacho
// de asfalto se hace SIEMPRE vía registrarCargaAsfalto() (multi-carga, una
// llamada atómica por camión, ver más abajo) y el de hormigón vía
// registrarCargaHormigon(). Ninguna de las dos cierra el pedido por sí
// sola desde la migración 11 — finalizarDespacho() es quien decide cerrarlo
// (completo o parcial, con o sin pedido residual).
// TODO(stock): cuando exista plantas_stock, el descuento automático de
// insumos (fórmula × cantidad_despachada) va del lado de finalizarDespacho().

/**
 * Cierra un pedido confirmado como despachado con lo cargado hasta el
 * momento — Logica sis. plantas v1.rtf §2.2: "cantidadReal = suma de las
 * cargas", el pedido pasa a despachado aunque sea menos de lo pedido. Si
 * `dividir` es true y queda saldo, crea automáticamente un pedido nuevo
 * confirmado por el residual en `fechaResidual` ("dividir pedido").
 *
 * @param {string} pedidoId
 * @param {{ dividir?: boolean, fechaResidual?: string|Date }} opciones
 */
export async function finalizarDespacho(pedidoId, { dividir = false, fechaResidual } = {}) {
  const fecha = fechaResidual ? new Date(fechaResidual).toISOString().slice(0, 10) : null
  const { data, error } = await supabase.rpc('finalizar_despacho', {
    p_pedido_id: pedidoId,
    p_dividir: dividir,
    p_fecha_residual: fecha,
  })
  if (error) throw error
  return data
}

/**
 * Cancelado requiere motivo obligatorio (memory/business-rules.md) y no se
 * reactiva — validado en el cliente Y de nuevo server-side en la RPC
 * (defensa en profundidad, migración 16).
 */
export async function cancelarPedido(id, motivo, { usuarioLegado } = {}) {
  if (!motivo || !motivo.trim()) {
    throw new Error('cancelarPedido: el motivo es obligatorio')
  }
  const { data, error } = await supabase.rpc('cancelar_pedido', {
    p_pedido_id: id,
    p_motivo: motivo,
    p_usuario_legado: usuarioLegado || null,
  })
  if (error) throw error
  return data
}

/**
 * Archiva un pedido despachado/cancelado (memory/business-rules.md: los
 * pedidos nunca se eliminan, solo se archivan). La vista normal los excluye
 * por defecto — ver fetchPedidos({ incluirArchivados }).
 */
export async function archivarPedido(id) {
  const { data, error } = await supabase.rpc('archivar_pedido', { p_pedido_id: id })
  if (error) throw error
  return data
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

// ---------------------------------------------------------------------------
// Cargas de asfalto (despacho multi-camión, vale por carga — atómico vía
// RPC, ver supabase/migrations/09_ubicacion_temperatura_egreso_multicarga.sql)
// ---------------------------------------------------------------------------

/**
 * Registra una carga (camión) de un pedido de asfalto confirmado: la RPC
 * registrar_carga_asfalto valida tipo/estado del pedido, inserta el vale en
 * plantas_cargas_asfalto y acumula cantidad_despachada en el pedido de forma
 * atómica (con lock de fila) — si la suma cubre lo solicitado, el pedido
 * pasa a despachado. Análoga a registrarCargaHormigon(), ver
 * memory/relevamiento-sistema-viejo.md §1 (multi-camión con vale por carga,
 * disponible desde el modal "Registrar despacho" de Pedidos, no solo desde
 * Báscula).
 *
 * @param {{ pedido_id: string, numero_vale: string, cantidad_tn: number,
 *   patente?: string, fecha_carga?: string|Date, observaciones?: string,
 *   numero_remito_global?: string }} cargaData
 *   numero_remito_global es el remito único opcional de todo el despacho
 *   (plantas_pedidos.nro_remito_global) — se completa una sola vez, no se
 *   pisa si ya lo trae una carga anterior del mismo despacho.
 */
export async function registrarCargaAsfalto(cargaData) {
  const fechaCarga = cargaData.fecha_carga ? new Date(cargaData.fecha_carga) : new Date()

  const { data, error } = await supabase.rpc('registrar_carga_asfalto', {
    p_pedido_id: cargaData.pedido_id,
    p_numero_vale: cargaData.numero_vale,
    p_cantidad_tn: Number(cargaData.cantidad_tn),
    p_patente: cargaData.patente || null,
    p_fecha_carga: fechaCarga.toISOString(),
    p_observaciones: cargaData.observaciones || null,
    p_numero_remito_global: cargaData.numero_remito_global || null,
  })

  if (error) throw error
  return data
}
