// Helper compartido para traer TODAS las filas de una query de Supabase,
// evitando el corte silencioso de PostgREST en 1000 filas (regla crítica de
// memory/architecture.md). Cualquier service que liste una tabla que puede
// crecer sin límite (pedidos, vales, movimientos de stock…) debe pasar por acá
// en vez de hacer un `.select()` suelto.

const TAMANO_PAGINA = 1000

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
