// Service de Báscula/Vales — único punto de acceso a Supabase para
// plantas_vales. Ningún componente .vue debe importar `supabase` directamente
// (memory/conventions.md).
//
// registrarPesada() llama a la RPC registrar_pesada_bascula (ver
// supabase/migrations/07_roles_y_rpc_atomicas.sql, extendida en 09 y 10): la
// lectura del pedido, el insert del vale y el update de cantidad_despachada
// corren atómicos del lado del servidor (con lock de fila), en vez del flujo
// multi-paso que tenía este service antes — eso es lo que soluciona la race
// condition entre slots paralelos pesando el mismo pedido (memory/pending.md).
//
// fetchHistorialVales() usa fetchPagina() (paginación server-side): trae solo
// la página que se muestra en UI, no todo el historial a memoria (memory/
// architecture.md, regla de paginación — acá además evita renderizar miles de
// filas de golpe cuando se migre el historial legado).

import { supabase } from '@/config/supabase'
import { fetchPagina, fetchPaginado } from '@/services/fetch-paginado'

const TABLA_PEDIDOS = 'plantas_pedidos'
const TABLA_VALES = 'plantas_vales'

function aTn(valor, unidad) {
  const n = Number(valor) || 0
  return unidad === 'kg' ? n / 1000 : n
}

// ---------------------------------------------------------------------------
// Formato del N° de vale (Logica sis. plantas v1.rtf §2.4: "número (8
// dígitos con ceros)") — usado tanto en el imprimible como en el header de
// BasculaView (memory/relevamiento-sistema-viejo.md Etapa 3).
// ---------------------------------------------------------------------------

export function formatearNumeroVale(numero) {
  if (numero == null) return '—'
  return String(numero).padStart(8, '0')
}

// ---------------------------------------------------------------------------
// Pedidos de asfalto elegibles para pesar en báscula
// ---------------------------------------------------------------------------

/**
 * Pedidos de asfalto confirmados o despachados, para el selector del form
 * "Vale Asfalto" de Báscula. Sin filtro por saldo pendiente a propósito
 * (decisión de Federico, 2026-08-28): el sistema legado permite seguir
 * pesando contra un pedido ya despachado — memory/relevamiento-sistema-viejo.md §2.
 *
 * Fix 2026-09-01 (regla de paginación, memory/architecture.md): el filtro
 * `estado in (confirmado, despachado)` NO tiene corte de fecha — `despachado`
 * acumula para siempre (nunca vuelve a otro estado), así que el total crece
 * sin límite con el historial migrado + el uso normal del sistema. Sin
 * fetchPaginado() acá, al superar 1000 filas PostgREST cortaría en silencio
 * — y como el `order` es ascendente (más viejo primero), lo que se pierde
 * serían los pedidos MÁS RECIENTES, justo los que un operador necesita
 * elegir en el selector.
 */
export async function fetchPedidosAsfaltoParaPesada() {
  return fetchPaginado(() =>
    supabase
      .from(TABLA_PEDIDOS)
      .select('*')
      .eq('tipo', 'asfalto')
      .in('estado', ['confirmado', 'despachado'])
      .order('fecha_programada', { ascending: true })
  )
}

// ---------------------------------------------------------------------------
// Próximo N° de vale (header operativo de Báscula)
// ---------------------------------------------------------------------------

/**
 * Estimación de sola lectura del próximo N° de vale a asignar. No consulta
 * la secuencia de Postgres directamente (eso consumiría/reservaría un valor
 * solo por mostrarlo) — usa max(numero_vale)+1, equivalente en la práctica
 * porque plantas_vales es insert-only y numero_vale es un identity siempre
 * creciente. Si la tabla está vacía, cae al valor inicial de la secuencia
 * (9579, ver supabase/migrations/04_bascula_y_vales.sql) + 1.
 */
export async function obtenerProximoNumeroVale() {
  const { data, error } = await supabase
    .from(TABLA_VALES)
    .select('numero_vale')
    .order('numero_vale', { ascending: false })
    .limit(1)

  if (error) throw error
  const ultimo = data?.[0]?.numero_vale
  return ultimo != null ? Number(ultimo) + 1 : 9579
}

// ---------------------------------------------------------------------------
// Acumulado dinámico — por pedido si existe, si no por obra
// ---------------------------------------------------------------------------

/**
 * Suma en tn de los vales de ASFALTO hasta `fechaCorte` (mismo día
 * calendario), agrupando por `pedidoId` cuando la pesada tiene un pedido
 * asociado, y solo cayendo a agrupar por `obraId` cuando no lo tiene — regla
 * exacta de Logica sis. plantas v1.rtf §2.4 / v2.rtf §6 ("pedidoId === este
 * vale's pedidoId (si existe) O bien obra === ... (si no hay pedidoId)").
 * Se recalcula siempre en el momento de usarla (acá y en el imprimible),
 * nunca se lee de `plantas_vales.acumulado_obra_tn` como fuente de verdad —
 * esa columna es solo una foto informativa al momento de pesar.
 *
 * Devuelve también el rango de `numero_vale` correlativos del día (2026-09-01,
 * a pedido de Federico con una foto de un remito real de VialTec): el
 * "REMITO" impreso tiene que mostrar "S/VALE DE BALANZA N° <desde> AL
 * <hasta> (CORRELATIVOS)" — el respaldo de básculas de todo lo acumulado ese
 * día para ese pedido/obra, no solo el vale individual que se está mirando.
 *
 * @param {{ pedidoId?: string|null, obraId?: number|null, fechaCorte: string|Date }} args
 * @returns {Promise<{ acumuladoTn: number, valeDesde: number|null, valeHasta: number|null, cantidadVales: number }>}
 */
export async function obtenerAcumuladoHastaFecha({ pedidoId, obraId, fechaCorte }) {
  const corte = new Date(fechaCorte)
  const inicioDia = new Date(corte)
  inicioDia.setHours(0, 0, 0, 0)

  let query = supabase
    .from(TABLA_VALES)
    .select('peso_neto, unidad, numero_vale')
    .eq('tipo_vale', 'asfalto')
    .gte('fecha_pesada', inicioDia.toISOString())
    .lte('fecha_pesada', corte.toISOString())

  query = pedidoId ? query.eq('pedido_id', pedidoId) : query.eq('obra_id', obraId)

  const { data, error } = await query
  if (error) throw error

  const vales = data ?? []
  const numeros = vales.map((v) => v.numero_vale).filter((n) => n != null)

  return {
    acumuladoTn: vales.reduce((acumulado, vale) => acumulado + aTn(vale.peso_neto, vale.unidad), 0),
    valeDesde: numeros.length ? Math.min(...numeros) : null,
    valeHasta: numeros.length ? Math.max(...numeros) : null,
    cantidadVales: numeros.length,
  }
}

// ---------------------------------------------------------------------------
// Registrar pesada (atómico, vía RPC)
// ---------------------------------------------------------------------------

/**
 * @param {{
 *   tipo_vale: 'asfalto'|'hormigon'|'ingreso_arido'|'egreso_arido',
 *   pedido_id?: string, obra_id?: number, patente?: string, chofer?: string,
 *   peso_bruto: number, tara: number, unidad?: 'tn'|'kg', observaciones?: string,
 *   fecha_pesada?: string|Date, material?: string, proveedor?: string,
 *   numero_remito?: string, cantidad_remito?: number, temperatura?: number,
 * }} valeData
 *   material/proveedor/numero_remito/cantidad_remito son el grupo de
 *   'ingreso_arido'. material + obra_id son el par que usa 'egreso_arido'
 *   (memory/relevamiento-sistema-viejo.md §2 — "Vale Salida Áridos": desde
 *   la migración 10, el destino es obra_id, ya no un texto libre).
 *   temperatura es específico de 'asfalto', siempre opcional.
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
    p_temperatura: valeData.temperatura ?? null,
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
 *   Cada fila trae embebido `plantas_ingresos` (array de a lo sumo 1 elemento,
 *   por el FK plantas_ingresos.vale_id -> plantas_vales.id) para poder
 *   calcular la diferencia peso pesado vs. cantidad declarada en el remito
 *   sin una query aparte — ver calcularDiferencia() más abajo.
 */
export async function fetchHistorialVales(filtros = {}, { pagina = 1, tamanoPagina = 50 } = {}) {
  return fetchPagina(
    () => {
      let query = supabase
        .from(TABLA_VALES)
        .select('*, plantas_ingresos(cantidad)', { count: 'exact' })
        .order('fecha_pesada', { ascending: false })

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

// ---------------------------------------------------------------------------
// Diferencia (peso neto pesado vs. cantidad declarada en el remito)
// ---------------------------------------------------------------------------

/**
 * Solo tiene sentido para ingreso_arido (memory/business-rules.md: el stock
 * se actualiza con lo declarado en el remito, no con el peso neto — la
 * diferencia es la que se registra para seguimiento, no la que se aplica).
 * `vale` es una fila de fetchHistorialVales() (con plantas_ingresos embebido).
 * Devuelve null cuando no aplica (asfalto, hormigón, egreso, o sin cantidad
 * de remito cargada todavía).
 */
export function calcularDiferencia(vale) {
  if (vale.tipo_vale !== 'ingreso_arido') return null
  const cantidadRemito = vale.plantas_ingresos?.[0]?.cantidad
  if (cantidadRemito == null) return null
  return Number(aTn(vale.peso_neto, vale.unidad).toFixed(2)) - Number(cantidadRemito)
}
