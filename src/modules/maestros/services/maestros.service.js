// Service de Maestros de planta — único punto de acceso a Supabase para
// plantas_encargados, plantas_proveedores, plantas_patentes y plantas_choferes.
// Ningún componente .vue debe importar `supabase` directamente: pasa por acá.
//
// Nota sobre paginación (memory/architecture.md): son catálogos acotados (decenas
// o pocos cientos de filas), no tablas de historial — no aplica fetchPaginado()
// acá. Si algún día uno de estos catálogos empieza a crecer sin límite, revisar
// esta decisión.

import { supabase } from '@/config/supabase'

/**
 * Factory de CRUD para una tabla de maestro. Evita duplicar el mismo
 * fetch/crear/actualizar/setActivo en cada catálogo (memory/conventions.md).
 */
function crudEntidad(tabla, columnaOrden = 'nombre') {
  return {
    async fetch({ soloActivos = false } = {}) {
      let query = supabase.from(tabla).select('*').order(columnaOrden, { ascending: true })
      if (soloActivos) query = query.eq('activo', true)

      const { data, error } = await query
      if (error) throw error
      return data
    },

    async crear(registro) {
      const { data, error } = await supabase.from(tabla).insert(registro).select().single()
      if (error) throw error
      return data
    },

    async actualizar(id, cambios) {
      const { data, error } = await supabase.from(tabla).update(cambios).eq('id', id).select().single()
      if (error) throw error
      return data
    },

    async setActivo(id, activo) {
      return this.actualizar(id, { activo })
    },
  }
}

export const encargadosService = crudEntidad('plantas_encargados')
export const proveedoresService = crudEntidad('plantas_proveedores')
export const patentesService = crudEntidad('plantas_patentes', 'patente')
export const choferesService = crudEntidad('plantas_choferes')
// Catálogo de materiales (migración 13, módulo Stock — memory/modules-status.md).
// Vive acá como cualquier otro maestro; stock.service.js lo importa para leer
// el catálogo, no lo duplica.
export const materialesService = crudEntidad('plantas_materiales')

/** Acceso agrupado, útil para vistas con tabs (ej. MaestrosView). */
export const maestrosService = {
  encargados: encargadosService,
  proveedores: proveedoresService,
  patentes: patentesService,
  choferes: choferesService,
  materiales: materialesService,
}
