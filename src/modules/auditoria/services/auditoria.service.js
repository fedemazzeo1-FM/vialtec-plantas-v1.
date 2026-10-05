// Service del módulo Auditoría (etapa 5): solo lectura de plantas_auditoria
// (migración 53). La escritura no pasa por acá ni por ningún cliente: la
// hacen las RPC y los triggers de la base (migraciones 54 a 62).
//
// La tabla acumula historial sin límite: el listado pagina server-side
// (fetchPagina, 50 por página) y el Excel trae todo el filtro con
// fetchPaginado (memory/architecture.md, regla de paginación). Orden con
// desempate por id para que las páginas no se pisen.
import { supabase } from '@/config/supabase'
import { fetchPagina, fetchPaginado } from '@/services/fetch-paginado'
import { formatearNumeroPedido } from '@/services/formato-numeros'

const TABLA = 'plantas_auditoria'
const TABLA_ENTIDADES = 'plantas_auditoria_entidades'

export const TAMANO_PAGINA_AUDITORIA = 50

// Mismo catálogo cerrado que el CHECK de plantas_auditoria.tipo_accion.
export const ACCIONES_AUDITORIA = [
  { id: 'CREAR', label: 'Alta', variante: 'success' },
  { id: 'EDITAR', label: 'Edición', variante: 'info' },
  { id: 'CAMBIAR_ESTADO', label: 'Cambio de estado', variante: 'default' },
  { id: 'CORREGIR', label: 'Corrección', variante: 'warning' },
  { id: 'REASIGNAR', label: 'Reasignación', variante: 'postergado' },
  { id: 'ANULAR', label: 'Anulación', variante: 'danger' },
  { id: 'ELIMINAR', label: 'Eliminación', variante: 'danger' },
]

/**
 * Texto de búsqueda por número → patrón seguro para PostgREST.
 * 'p230' / 'P-230' / 'p 0230' → 'P-0230' (N° de pedido); el resto (N° de
 * vale, de remito, nombre) va tal cual, sin los caracteres que rompen el
 * filtro `or()`.
 */
export function normalizarBusquedaAuditoria(texto) {
  const t = String(texto ?? '').trim()
  if (!t) return ''
  const pedido = /^p[-\s]?(\d+)$/i.exec(t)
  if (pedido) return formatearNumeroPedido(Number(pedido[1]))
  return t.replace(/[,()"\\*%]/g, ' ').replace(/\s+/g, ' ').trim()
}

/**
 * @param {{ usuario?: string, modulo?: string, accion?: string, desde?: string, hasta?: string, q?: string }} filtros
 *   desde/hasta 'YYYY-MM-DD' sobre fecha_negocio (fecha en hora de Argentina).
 */
function queryAuditoria(filtros, { ascendente = false, conTotal = true } = {}) {
  let query = supabase
    .from(TABLA)
    .select('*', conTotal ? { count: 'exact' } : undefined)
    .order('fecha_hora', { ascending: ascendente })
    .order('id', { ascending: ascendente })

  if (filtros.usuario) query = query.eq('usuario_email', filtros.usuario)
  if (filtros.modulo) query = query.eq('modulo', filtros.modulo)
  if (filtros.accion) query = query.eq('tipo_accion', filtros.accion)
  if (filtros.desde) query = query.gte('fecha_negocio', filtros.desde)
  if (filtros.hasta) query = query.lte('fecha_negocio', filtros.hasta)

  const busqueda = normalizarBusquedaAuditoria(filtros.q)
  if (busqueda) {
    query = query.or(`entidad_ref.ilike."*${busqueda}*",entidad_label.ilike."*${busqueda}*"`)
  }
  return query
}

/** Una página del listado, lo más nuevo primero. Devuelve `{ filas, total }`. */
export async function fetchAuditoria(filtros = {}, { pagina = 1 } = {}) {
  return fetchPagina(() => queryAuditoria(filtros), { pagina, tamanoPagina: TAMANO_PAGINA_AUDITORIA })
}

/** Todas las filas del filtro (para el Excel), en orden cronológico. */
export async function fetchTodaLaAuditoria(filtros = {}) {
  return fetchPaginado(() => queryAuditoria(filtros, { ascendente: true, conTotal: false }))
}

/** Catálogo de módulos/entidades (chico por diseño, no pagina). */
export async function fetchEntidadesAuditoria() {
  const { data, error } = await supabase.from(TABLA_ENTIDADES).select('*').order('orden', { ascending: true })
  if (error) throw error
  return data ?? []
}
