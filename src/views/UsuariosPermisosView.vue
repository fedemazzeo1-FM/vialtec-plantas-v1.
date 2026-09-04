<script setup>
// Módulo "Usuarios y Permisos por rol" (pedido de Federico, 2026-09-03):
// unifica en un solo lugar la administración de cuentas (tab "Usuarios") y
// la consulta de qué puede hacer cada rol (tab "Permisos por rol"). Acceso
// restringido a rol admin — doble guarda: el link de nav no aparece para
// otros roles (nav.js filtra por auth.puedeVerTab, y admin es el único rol
// con `tabs: 'todas'` en PERMISOS_POR_ROL) y el router bloquea el acceso
// directo por URL (router/index.js, mismo guard genérico que usa toda la
// app) — no hace falta un guard especial acá.
//
// La tab "Usuarios" depende de la migración 21 (policy "admin lee todos los
// usuarios" + RPC admin_upsert_usuario_rol) — APLICADA 2026-09-03 noche con
// confirmación explícita de Federico, ver supabase/migrations/21_admin_gestion_usuarios_roles.sql
// y memory/pending.md.

import { computed, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import VSection from '@/components/shared/VSection.vue'
import VCard from '@/components/shared/VCard.vue'
import VTable from '@/components/shared/VTable.vue'
import VModal from '@/components/shared/VModal.vue'
import VBadge from '@/components/shared/VBadge.vue'
import VButton from '@/components/shared/VButton.vue'
import { useUsuariosRoles } from '@/modules/usuarios/composables/useUsuariosRoles'
import { PERMISOS_POR_ROL } from '@/stores/auth.store'

const TABS = ['usuarios', 'permisos']
const route = useRoute()
const router = useRouter()
const tabActiva = ref(TABS.includes(route.query.tab) ? route.query.tab : TABS[0])
function irATab(tab) {
  tabActiva.value = tab
  router.replace({ query: { ...route.query, tab } })
}

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

const obrasSeleccionadasTexto = computed(() =>
  formData.obraIds.length ? formData.obraIds.map(nombreObra).join(', ') : 'Ninguna'
)
function toggleObra(id) {
  const i = formData.obraIds.indexOf(id)
  if (i === -1) formData.obraIds.push(id)
  else formData.obraIds.splice(i, 1)
}

// Etiquetas legibles de los campos de PERMISOS_POR_ROL, para la tab
// "Permisos por rol" — mismo orden en el que se definen en auth.store.js.
const CAMPOS_PERMISO = [
  { key: 'tabs', label: 'Pantallas visibles' },
  { key: 'crearPedido', label: 'Crear pedido' },
  { key: 'confirmar', label: 'Confirmar pedido' },
  { key: 'despachar', label: 'Despachar' },
  { key: 'stock', label: 'Stock' },
  { key: 'verVentas', label: 'Ver ventas' },
]
function formatearPermiso(valor) {
  if (valor === 'todas') return 'Todas'
  if (Array.isArray(valor)) return valor.join(', ')
  if (valor === true) return 'Sí'
  if (valor === false) return 'No'
  if (valor === 'editar') return 'Editar'
  if (valor === 'ver') return 'Solo ver'
  return String(valor)
}
</script>

<template>
  <div>
    <VSection title="Usuarios y Permisos por rol">
      <div class="mb-4 flex gap-1 overflow-x-auto border-b border-border">
        <button
          v-for="tab in TABS"
          :key="tab"
          type="button"
          class="shrink-0 whitespace-nowrap border-b-2 px-3 py-2 text-sm font-semibold transition-colors duration-150"
          :class="tab === tabActiva ? 'border-vialtec text-vialtec' : 'border-transparent text-text-soft hover:text-text-mid'"
          @click="irATab(tab)"
        >
          {{ tab === 'usuarios' ? 'Usuarios' : 'Permisos por rol' }}
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
              <VBadge>{{ row.rol }}</VBadge>
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

      <!-- Tab Permisos por rol -->
      <template v-else>
        <p class="mb-3 text-xs text-text-soft">
          Matriz de permisos por rol (solo lectura acá — se define en
          <code>src/stores/auth.store.js#PERMISOS_POR_ROL</code>). Es la fuente que usa
          la UI para mostrar/ocultar pantallas y botones; el chequeo real y no
          salteable vive en las RPC/RLS del server.
        </p>
        <div class="space-y-4">
          <VCard v-for="(permisos, rol) in PERMISOS_POR_ROL" :key="rol">
            <h3 class="mb-2 text-sm font-semibold text-text-strong">{{ rol }}</h3>
            <dl class="grid grid-cols-1 gap-x-6 gap-y-1.5 sm:grid-cols-2">
              <div v-for="campo in CAMPOS_PERMISO" :key="campo.key" class="flex justify-between gap-3 text-sm">
                <dt class="text-text-soft">{{ campo.label }}</dt>
                <dd class="text-right font-medium text-text-mid">{{ formatearPermiso(permisos[campo.key]) }}</dd>
              </div>
            </dl>
          </VCard>
        </div>
      </template>
    </VSection>

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
            <option v-for="rol in rolesDisponibles" :key="rol" :value="rol">{{ rol }}</option>
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
  </div>
</template>
