// Lecturas de solo lectura sobre tablas flota_* compartidas con el sistema de
// flota (memory/architecture.md). VialTec Plantas NO es dueño de este schema:
// acá solo se lee, nunca se escribe. Cualquier necesidad de escritura sobre
// flota_* requiere el protocolo de memory/procedimientos.md.

import { supabase } from '@/config/supabase'

/** Obras (catálogo compartido, ~20 filas — no necesita fetchPaginado). */
export async function fetchObras({ soloActivas = true } = {}) {
  let query = supabase
    .from('flota_obras')
    .select('id, nombre, codigo, activo')
    .order('nombre', { ascending: true })

  if (soloActivas) query = query.eq('activo', true)

  const { data, error } = await query
  if (error) throw error
  return data
}
