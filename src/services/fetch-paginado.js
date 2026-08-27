// Helpers compartidos para consultas a Supabase que pueden superar las 1000
// filas (regla crítica de memory/architecture.md: PostgREST corta en 1000
// filas de forma silenciosa, sin error).
//
// Dos helpers, dos casos de uso distintos:
//  - fetchPaginado(): trae TODAS las filas a memoria (loop de .range()).
//    Usarlo cuando el caller necesita el dataset completo para calcular algo
//    (sumas/agrupaciones — ej. analytics.service.js#totalesPorProveedor), no
//    para pintar una tabla completa en la UI.
//  - fetchPagina(): trae UNA página server-side (un solo .range() + count
//    exacto). Usarlo para listados de UI que se muestran paginados (Pedidos,
//    Historial de báscula) — evita traer y renderizar miles de filas de golpe
//    cuando el historial migrado crezca (ver memory/pending.md, migración del
//    historial legado).

const TAMANO_PAGINA = 1000
const TAMANO_PAGINA_UI_DEFAULT = 50

/**
 * @param {() => import('@supabase/supabase-js').PostgrestFilterBuilder} construirQuery
 *   Factory que devuelve un query builder NUEVO cada vez que se llama (con
 *   .select/.eq/.order/etc. ya aplicados, pero SIN `.range()` — eso lo agrega
 *   este helper). Tiene que ser una factory y no un builder ya armado porque
 *   los builders de Supabase son de un solo uso.
 */
export async function fetchPaginado(construirQuery) {
  let desde = 0
  let resultado = []

  while (true) {
    const hasta = desde + TAMANO_PAGINA - 1
    const { data, error } = await construirQuery().range(desde, hasta)
    if (error) throw error

    resultado = resultado.concat(data ?? [])

    if (!data || data.length < TAMANO_PAGINA) break
    desde += TAMANO_PAGINA
  }

  return resultado
}

/**
 * Trae UNA página de una query de Supabase. `construirQuery()` tiene que
 * incluir `{ count: 'exact' }` en su `.select()` para que el total venga
 * correcto (el count no está sujeto al corte de 1000 filas: es un COUNT(*)
 * real del lado del servidor, aunque `data` solo traiga la página pedida).
 *
 * @param {() => import('@supabase/supabase-js').PostgrestFilterBuilder} construirQuery
 * @param {{ pagina?: number, tamanoPagina?: number }} opciones
 * @returns {Promise<{ filas: any[], total: number, pagina: number, tamanoPagina: number }>}
 */
export async function fetchPagina(construirQuery, { pagina = 1, tamanoPagina = TAMANO_PAGINA_UI_DEFAULT } = {}) {
  const desde = (pagina - 1) * tamanoPagina
  const hasta = desde + tamanoPagina - 1

  const { data, error, count } = await construirQuery().range(desde, hasta)
  if (error) throw error

  return { filas: data ?? [], total: count ?? 0, pagina, tamanoPagina }
}
