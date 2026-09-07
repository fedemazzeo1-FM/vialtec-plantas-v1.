<script setup>
// Módulo "Administración" (2026-09-06 — antes "Usuarios y Permisos por
// rol"; renombrado + reconstruido a pedido de Federico, imágenes de
// referencia del sistema de Flota). Dos tabs:
//   - "Usuarios": alta/edición de cuentas y asignación de rol (sin cambios
//     de fondo respecto al módulo anterior, migración 21).
//   - "Roles": la matriz de permisos REAL (migración 26) — lista de roles +
//     modal "Editar rol" con la matriz Ver/Crear/Editar/Eliminar/Aprobar/
//     Exportar por módulo, switches púrpura, calcado del "Editar Rol" de
//     Flota. Reemplaza la vieja matriz informativa (MATRIZ_REAL_PERMISOS),
//     que era solo un documento hardcodeado en el frontend — esto lee y
//     escribe la tabla real que ahora hacen cumplir las RPC/RLS.
//
// Acceso restringido a rol admin — doble guarda: el link de nav no aparece
// para otros roles (nav.js filtra por auth.puedeVerTab) y el router bloquea
// el acceso directo por URL (router/index.js, mismo guard genérico de
// siempre) — no hace falta un guard especial acá. El módulo "Administración"
// en sí queda siempre admin-only y NO es editable desde su propia matriz de
// roles (migración 26, `plantas_tiene_permiso()` — piso de seguridad para
// que nadie pueda auto-otorgarse ni quitarle el control a admin).

import { computed, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import VSection from '@/components/shared/VSection.vue'
import VCard from '@/components/shared/VCard.vue'
import VTable from '@/components/shared/VTable.vue'
import VModal from '@/components/shared/VModal.vue'
import VBadge from '@/components/shared/VBadge.vue'
import VButton from '@/components/shared/VButton.vue'
import VToggle from '@/components/shared/VToggle.vue'
import { useUsuariosRoles } from '@/modules/usuarios/composables/useUsuariosRoles'
import { useAdministracionRoles } from '@/modules/usuarios/composables/useAdministracionRoles'

const TABS = ['usuarios', 'roles']
const route = useRoute()
const router = useRouter()
const tabActiva = ref(TABS.includes(route.query.tab) ? route.query.tab : TABS[0])
function irATab(tab) {
  tabActiva.value = tab
  router.replace({ query: { ...route.query, tab } })
}

// -----------------------------------------------------------------------
// Tab Usuarios
// -----------------------------------------------------------------------

const {
  usuarios,
  obras,
  cargando,
  error,
  modalAbierto,
  guardando,
  editandoId,
  formData,
  rolesDisponibles,
  cargar,
  abrirNuevo,
  abrirEdicion,
  guardar,
  toggleActivo,
} = useUsuariosRoles()
cargar()

const columnas = [
  { key: 'email', label: 'Email' },
  { key: 'rol', label: 'Rol' },
  { key: 'obras', label: 'Obras visibles' },
  { key: 'ver_ventas', label: 'Ve ventas' },
  { key: 'activo', label: 'Estado' },
  { key: 'acciones', label: '' },
]

function nombreObra(id) {
  return obras.value.find((o) => o.id === id)?.nombre ?? `Obra #${id}`
}
function nombreRol(rolId) {
  return rolesDisponibles.value.find((r) => r.id === rolId)?.nombre ?? rolId
}

const obrasSeleccionadasTexto = computed(() =>
  formData.obraIds.length ? formData.obraIds.map(nombreObra).join(', ') : 'Ninguna'
)
function toggleObra(id) {
  const i = formData.obraIds.indexOf(id)
  if (i === -1) formData.obraIds.push(id)
  else formData.obraIds.splice(i, 1)
}

// -----------------------------------------------------------------------
// Tab Roles
// -----------------------------------------------------------------------

const {
  roles,
  cargando: cargandoRoles,
  error: errorRoles,
  modalAbierto: modalRolAbierto,
  guardando: guardandoRol,
  cargandoPermisos,
  rolEditando,
  formRol,
  permisos,
  modulosMatriz,
  accionesMatriz,
  cargar: cargarRoles,
  abrirNuevo: abrirNuevoRol,
  abrirEditar: abrirEditarRol,
  guardar: guardarRol,
  toggleActivo: toggleActivoRol,
} = useAdministracionRoles()
cargarRoles()

const columnasRoles = [
  { key: 'nombre', label: 'Rol' },
  { key: 'descripcion', label: 'Descripción' },
  { key: 'cantidadUsuarios', label: 'Usuarios' },
  { key: 'activo', label: 'Estado' },
  { key: 'acciones', label: '' },
]
</script>

<template>
  <div>
    <VSection title="Administración">
      <div class="mb-4 flex gap-1 overflow-x-auto border-b border-border">
        <button
          v-for="tab in TABS"
          :key="tab"
          type="button"
          class="shrink-0 whitespace-nowrap border-b-2 px-3 py-2 text-sm font-semibold transition-colors duration-150"
          :class="tab === tabActiva ? 'border-vialtec text-vialtec' : 'border-transparent text-text-soft hover:text-text-mid'"
          @click="irATab(tab)"
        >
          {{ tab === 'usuarios' ? 'Usuarios' : 'Roles' }}
        </button>
      </div>

      <!-- Tab Usuarios -->
      <template v-if="tabActiva === 'usuarios'">
        <div v-if="error" class="mb-3 rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
          {{ error }}
        </div>

        <div class="mb-3 flex justify-end">
          <VButton size="sm" @click="abrirNuevo"> + Nuevo usuario </VButton>
        </div>

        <VCard>
          <p v-if="cargando" class="text-sm text-text-soft">Cargando…</p>
          <VTable v-else :columns="columnas" :rows="usuarios">
            <template #cell-rol="{ row }">
              <VBadge>{{ nombreRol(row.rol) }}</VBadge>
            </template>
            <template #cell-obras="{ row }">
              <span class="text-xs text-text-soft">
                {{ row.ver_todas_obras ? 'Todas' : (row.obra_ids?.length ? row.obra_ids.map(nombreObra).join(', ') : '—') }}
              </span>
            </template>
            <template #cell-ver_ventas="{ row }">
              <VBadge :variant="row.ver_ventas ? 'success' : 'default'">{{ row.ver_ventas ? 'Sí' : 'No' }}</VBadge>
            </template>
            <template #cell-activo="{ row }">
              <VBadge :variant="row.activo ? 'success' : 'default'">{{ row.activo ? 'Activo' : 'Inactivo' }}</VBadge>
            </template>
            <template #cell-acciones="{ row }">
              <div class="flex gap-1.5">
                <VButton variant="secondary" size="sm" @click="abrirEdicion(row)">Editar</VButton>
                <VButton variant="ghost" size="sm" @click="toggleActivo(row)">
                  {{ row.activo ? 'Desactivar' : 'Activar' }}
                </VButton>
              </div>
            </template>
          </VTable>
          <p v-if="!cargando && !usuarios.length" class="py-4 text-center text-sm text-text-soft">
            No hay usuarios cargados todavía.
          </p>
        </VCard>
      </template>

      <!-- Tab Roles -->
      <template v-else>
        <div v-if="errorRoles" class="mb-3 rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
          {{ errorRoles }}
        </div>

        <p class="mb-3 text-xs text-text-soft">
          Cada rol tiene una matriz de permisos real: los switches que se editan acá son los que
          consultan las funciones y políticas del servidor (migración 26) — no es una vista
          informativa, cambiar un permiso cambia el comportamiento del sistema al instante.
        </p>

        <div class="mb-3 flex justify-end">
          <VButton size="sm" @click="abrirNuevoRol"> + Nuevo rol </VButton>
        </div>

        <VCard>
          <p v-if="cargandoRoles" class="text-sm text-text-soft">Cargando…</p>
          <VTable v-else :columns="columnasRoles" :rows="roles">
            <template #cell-nombre="{ row }">
              <div class="flex items-center gap-2">
                <span class="font-semibold text-text">{{ row.nombre }}</span>
                <VBadge v-if="row.es_sistema" variant="default">Sistema</VBadge>
              </div>
            </template>
            <template #cell-descripcion="{ row }">
              <span class="text-xs text-text-soft">{{ row.descripcion || '—' }}</span>
            </template>
            <template #cell-activo="{ row }">
              <VBadge :variant="row.activo ? 'success' : 'default'">{{ row.activo ? 'Activo' : 'Inactivo' }}</VBadge>
            </template>
            <template #cell-acciones="{ row }">
              <div class="flex gap-1.5">
                <VButton variant="secondary" size="sm" @click="abrirEditarRol(row)">Editar</VButton>
                <VButton v-if="!row.es_sistema" variant="ghost" size="sm" @click="toggleActivoRol(row)">
                  {{ row.activo ? 'Desactivar' : 'Activar' }}
                </VButton>
              </div>
            </template>
          </VTable>
        </VCard>

        <p class="mt-4 text-xs text-text-soft">
          La visibilidad de obras (qué pedidos/despachos ve cada usuario) no depende del rol, sino
          de la fila individual de cada usuario en la tab "Usuarios" (<code>ver_todas_obras</code>,
          <code>obra_ids</code>, <code>ver_ventas</code>). El módulo "Administración" en sí es
          siempre exclusivo de <code>admin</code> y no se configura desde acá — evita que la
          herramienta se pueda usar para quitarle el control a sí misma.
        </p>
      </template>
    </VSection>

    <!-- Modal Nuevo/Editar usuario -->
    <VModal :open="modalAbierto" :title="(editandoId ? 'Editar' : 'Nuevo') + ' usuario'" @update:open="modalAbierto = $event">
      <form class="space-y-3" @submit.prevent="guardar">
        <label class="block text-sm text-text-mid">
          Email
          <input
            v-model="formData.email"
            type="email"
            :disabled="!!editandoId"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none disabled:bg-gray-50 disabled:text-text-soft"
          />
        </label>

        <label class="block text-sm text-text-mid">
          Rol
          <select
            v-model="formData.rol"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          >
            <option v-for="rol in rolesDisponibles" :key="rol.id" :value="rol.id">{{ rol.nombre }}</option>
          </select>
        </label>

        <label class="flex items-center gap-2 text-sm text-text-mid">
          <input v-model="formData.verVentas" type="checkbox" />
          Ve ventas externas
        </label>

        <label class="flex items-center gap-2 text-sm text-text-mid">
          <input v-model="formData.verTodasObras" type="checkbox" />
          Ve todas las obras
        </label>

        <div v-if="!formData.verTodasObras" class="rounded-lg border border-border p-2">
          <p class="mb-1.5 text-xs text-text-soft">Obras visibles: {{ obrasSeleccionadasTexto }}</p>
          <div class="max-h-32 space-y-1 overflow-y-auto">
            <label v-for="obra in obras" :key="obra.id" class="flex items-center gap-2 text-sm text-text-mid">
              <input
                type="checkbox"
                :checked="formData.obraIds.includes(obra.id)"
                @change="toggleObra(obra.id)"
              />
              {{ obra.nombre }}
            </label>
          </div>
        </div>

        <label class="flex items-center gap-2 text-sm text-text-mid">
          <input v-model="formData.activo" type="checkbox" />
          Activo
        </label>

        <div v-if="error" class="rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
          {{ error }}
        </div>

        <div class="flex justify-end gap-2 pt-2">
          <VButton type="button" variant="secondary" @click="modalAbierto = false">Cancelar</VButton>
          <VButton type="submit" :disabled="guardando">{{ guardando ? 'Guardando…' : 'Guardar' }}</VButton>
        </div>
      </form>
    </VModal>

    <!-- Modal Nuevo/Editar rol — calco del "Editar Rol" de Flota (imagen de referencia). -->
    <VModal
      :open="modalRolAbierto"
      :title="(rolEditando ? 'Editar' : 'Nuevo') + ' rol'"
      size="2xl"
      @update:open="modalRolAbierto = $event"
    >
      <form class="space-y-4" @submit.prevent="guardarRol">
        <label class="block text-sm font-semibold text-text-mid">
          Nombre *
          <input
            v-model="formRol.nombre"
            type="text"
            required
            :disabled="!!rolEditando?.es_sistema"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none disabled:bg-gray-50 disabled:text-text-soft"
            placeholder="Ej: Administrativo Taller"
          />
        </label>

        <label class="block text-sm font-semibold text-text-mid">
          Descripción
          <textarea
            v-model="formRol.descripcion"
            rows="2"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            placeholder="Qué hace este rol en el sistema"
          />
        </label>

        <div>
          <p class="mb-2 text-sm font-semibold text-text-mid">Matriz de permisos</p>
          <p v-if="cargandoPermisos" class="text-sm text-text-soft">Cargando…</p>
          <div v-else class="overflow-x-auto rounded-lg border border-border">
            <table class="min-w-full divide-y divide-border text-sm">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wide text-text-soft">Módulo</th>
                  <th
                    v-for="accion in accionesMatriz"
                    :key="accion.key"
                    class="px-3 py-2 text-center text-xs font-bold uppercase tracking-wide text-text-soft"
                  >
                    {{ accion.label }}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-border">
                <tr v-for="modulo in modulosMatriz" :key="modulo.key">
                  <td class="whitespace-nowrap px-3 py-2.5 font-medium text-text">{{ modulo.label }}</td>
                  <td v-for="accion in accionesMatriz" :key="accion.key" class="px-3 py-2.5 text-center">
                    <VToggle v-model="permisos[modulo.key][accion.key]" />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="mt-2 text-xs text-text-soft">
            El módulo "Administración" no aparece acá: es siempre exclusivo de <code>admin</code>,
            no se puede restringir ni ampliar desde la matriz.
          </p>
        </div>

        <div v-if="errorRoles" class="rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
          {{ errorRoles }}
        </div>

        <div class="flex justify-end gap-2 pt-2">
          <VButton type="button" variant="secondary" @click="modalRolAbierto = false">Cancelar</VButton>
          <VButton type="submit" :disabled="guardandoRol">{{ guardandoRol ? 'Guardando…' : 'Guardar' }}</VButton>
        </div>
      </form>
    </VModal>
  </div>
</template>
