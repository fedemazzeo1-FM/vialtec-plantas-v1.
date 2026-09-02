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
 *
 * `filtroFijo` (2026-09-01, separación Vehículos Propios/Externos): un
 * objeto columna->valor que se aplica siempre — tanto al listar (WHERE) como
 * al crear (se mezcla en el registro, así "Nuevo vehículo" desde la tab
 * "Propios" no necesita que el usuario tilde nada, ya sale con
 * `es_externa: false`). No se puede cambiar por fuera de qué tab lo creó,
 * consistente con que son vistas separadas, no un filtro que el usuario
 * pueda tocar.
 */
function crudEntidad(tabla, columnaOrden = 'nombre', filtroFijo = null) {
  return {
    async fetch({ soloActivos = false } = {}) {
      let query = supabase.from(tabla).select('*').order(columnaOrden, { ascending: true })
      if (soloActivos) query = query.eq('activo', true)
      if (filtroFijo) {
        for (const [columna, valor] of Object.entries(filtroFijo)) query = query.eq(columna, valor)
      }

      const { data, error } = await query
      if (error) throw error
      return data
    },

    async crear(registro) {
      const { data, error } = await supabase.from(tabla).insert({ ...registro, ...filtroFijo }).select().single()
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
// patentesService sin filtro: usado donde hace falta el catálogo COMPLETO
// (ej. datalist de patente en los modales de despacho de Pedidos/Báscula —
// ahí no importa si es propia o externa, cualquier camión puede cargar).
export const patentesService = crudEntidad('plantas_patentes', 'patente')
// Separación Propios/Externos (2026-09-01, pedido de Federico — relevado
// contra el legado: `es_externa` ya existía en el schema desde la migración
// de historial, 30 propias / 21 externas reales, pero convivían en una sola
// tabla de Maestros sin distinción visual clara). Mismo `plantas_patentes`,
// filtro fijo en cada servicio — no son tablas separadas.
export const patentesPropiasService = crudEntidad('plantas_patentes', 'patente', { es_externa: false })
export const patentesExternasService = crudEntidad('plantas_patentes', 'patente', { es_externa: true })
export const choferesService = crudEntidad('plantas_choferes')
// Catálogo de materiales (migración 13, módulo Stock — memory/modules-status.md).
// Vive acá como cualquier otro maestro; stock.service.js lo importa para leer
// el catálogo, no lo duplica.
export const materialesService = crudEntidad('plantas_materiales')

/** Acceso agrupado, útil para vistas con tabs (ej. MaestrosView). */
// Fix 2026-09-02 (roadmap Mobile, auditoría de Maestros — pedido explícito
// de Federico de auditar la carga de vehículos): las claves de acá tenían
// que coincidir con las de ENTIDADES en MaestrosView.vue
// (maestrosService[tabActiva.value].fetch()), pero decían patentesPropias/
// patentesExternas mientras la vista usa vehiculosPropios/vehiculosExternos
// (nombres de tab más claros, elegidos aparte al armar la vista) — las tabs
// "Vehículos propios"/"Vehículos externos" quedaban 100% rotas
// ("Cannot read properties of undefined (reading 'fetch')" en cada acción:
// listar, crear, editar, activar/desactivar), sin ningún error visible más
// que el mensaje genérico — nunca se había smoke-testeado en vivo desde que
// se separaron las 2 tabs. Se renombran las claves acá para matchear la
// vista (patentesPropiasService/patentesExternasService, los named exports
// de abajo, no se tocan — no se usan en ningún otro lado).
export const maestrosService = {
  encargados: encargadosService,
  proveedores: proveedoresService,
  patentes: patentesService,
  vehiculosPropios: patentesPropiasService,
  vehiculosExternos: patentesExternasService,
  choferes: choferesService,
  materiales: materialesService,
}
