<script setup>
// Vista de Maestros de planta: tabs para encargados, proveedores, patentes y
// choferes. Toda la persistencia pasa por maestros.service.js — este componente
// no llama a Supabase directamente (memory/conventions.md).

import { computed, reactive, ref, watch } from 'vue'
import VCard from '@/components/shared/VCard.vue'
import VTable from '@/components/shared/VTable.vue'
import VModal from '@/components/shared/VModal.vue'
import VBadge from '@/components/shared/VBadge.vue'
import VSection from '@/components/shared/VSection.vue'
import { maestrosService } from '@/modules/maestros/services/maestros.service'

// Config declarativa por catálogo: columnas de tabla, campos de formulario y
// registro vacío. Evita repetir la vista 4 veces para 4 tablas casi idénticas.
const ENTIDADES = {
  encargados: {
    label: 'Encargados',
    columnas: [
      { key: 'nombre', label: 'Nombre' },
      { key: 'telefono', label: 'Teléfono' },
    ],
    campos: [
      { key: 'nombre', label: 'Nombre', type: 'text', required: true },
      { key: 'telefono', label: 'Teléfono', type: 'text' },
    ],
    vacio: () => ({ nombre: '', telefono: '', activo: true }),
  },
  proveedores: {
    label: 'Proveedores',
    columnas: [
      { key: 'nombre', label: 'Nombre' },
      { key: 'material_principal', label: 'Material principal' },
    ],
    campos: [
      { key: 'nombre', label: 'Nombre', type: 'text', required: true },
      { key: 'material_principal', label: 'Material principal', type: 'text' },
    ],
    vacio: () => ({ nombre: '', material_principal: '', activo: true }),
  },
  patentes: {
    label: 'Patentes',
    columnas: [
      { key: 'patente', label: 'Patente' },
      { key: 'tipo_camion', label: 'Tipo camión' },
      { key: 'tara', label: 'Tara (tn)' },
      { key: 'chofer_habitual', label: 'Chofer habitual' },
      { key: 'es_externa', label: 'Origen', format: (v) => (v ? 'Externa' : 'Propia') },
    ],
    campos: [
      { key: 'patente', label: 'Patente', type: 'text', required: true },
      { key: 'tipo_camion', label: 'Tipo de camión', type: 'text' },
      { key: 'tara', label: 'Tara (tn)', type: 'number' },
      { key: 'chofer_habitual', label: 'Chofer habitual', type: 'text' },
      { key: 'es_externa', label: 'Es externa', type: 'checkbox' },
    ],
    vacio: () => ({
      patente: '',
      tipo_camion: '',
      tara: null,
      chofer_habitual: '',
      es_externa: false,
      activo: true,
    }),
  },
  choferes: {
    label: 'Choferes',
    columnas: [
      { key: 'nombre', label: 'Nombre' },
      { key: 'dni', label: 'DNI' },
    ],
    campos: [
      { key: 'nombre', label: 'Nombre', type: 'text', required: true },
      { key: 'dni', label: 'DNI', type: 'text' },
    ],
    vacio: () => ({ nombre: '', dni: '', activo: true }),
  },
  // Catálogo de materiales (migración 13, módulo Stock) — gap #2 del
  // relevamiento: antes "material" era texto libre en todos lados. `nombre`
  // es la clave de matching contra fórmulas/báscula/ingresos (case-
  // insensitive, ver plantas_buscar_material_id() en la migración).
  materiales: {
    label: 'Materiales',
    columnas: [
      { key: 'nombre', label: 'Nombre' },
      { key: 'unidad', label: 'Unidad' },
      { key: 'categoria', label: 'Categoría' },
      { key: 'controla_stock', label: 'Controla stock', format: (v) => (v ? 'Sí' : 'No') },
      { key: 'stock_minimo_kg', label: 'Mín. (kg)' },
      { key: 'stock_maximo_kg', label: 'Máx. (kg)' },
    ],
    campos: [
      { key: 'nombre', label: 'Nombre', type: 'text', required: true },
      { key: 'unidad', label: 'Unidad (referencia, ej. "TN")', type: 'text' },
      { key: 'categoria', label: 'Categoría (opcional)', type: 'text' },
      { key: 'controla_stock', label: 'Controla stock (desmarcar para Agua/Purgue)', type: 'checkbox' },
      { key: 'stock_minimo_kg', label: 'Stock mínimo de alerta (kg)', type: 'number' },
      { key: 'stock_maximo_kg', label: 'Stock máximo (kg)', type: 'number' },
    ],
    vacio: () => ({
      nombre: '',
      unidad: '',
      categoria: '',
      controla_stock: true,
      stock_minimo_kg: null,
      stock_maximo_kg: null,
      activo: true,
    }),
  },
}

const tabs = Object.keys(ENTIDADES)
const tabActiva = ref(tabs[0])
const entidadActual = computed(() => ENTIDADES[tabActiva.value])
const columnasConAcciones = computed(() => [
  ...entidadActual.value.columnas,
  { key: 'activo', label: 'Estado' },
  { key: 'acciones', label: '' },
])

const registros = ref([])
const cargando = ref(false)
const error = ref(null)

const modalAbierto = ref(false)
const guardando = ref(false)
const editandoId = ref(null)
const formData = reactive({})

async function cargarRegistros() {
  cargando.value = true
  error.value = null
  try {
    registros.value = await maestrosService[tabActiva.value].fetch()
  } catch (e) {
    error.value = e.message
  } finally {
    cargando.value = false
  }
}

watch(tabActiva, cargarRegistros, { immediate: true })

function abrirNuevo() {
  editandoId.value = null
  Object.keys(formData).forEach((k) => delete formData[k])
  Object.assign(formData, entidadActual.value.vacio())
  modalAbierto.value = true
}

function abrirEdicion(registro) {
  editandoId.value = registro.id
  Object.keys(formData).forEach((k) => delete formData[k])
  Object.assign(formData, registro)
  modalAbierto.value = true
}

async function guardar() {
  const campoRequerido = entidadActual.value.campos.find((c) => c.required && !String(formData[c.key] || '').trim())
  if (campoRequerido) {
    error.value = `El campo "${campoRequerido.label}" es obligatorio.`
    return
  }

  guardando.value = true
  error.value = null
  try {
    if (editandoId.value) {
      await maestrosService[tabActiva.value].actualizar(editandoId.value, formData)
    } else {
      await maestrosService[tabActiva.value].crear(formData)
    }
    modalAbierto.value = false
    await cargarRegistros()
  } catch (e) {
    error.value = e.message
  } finally {
    guardando.value = false
  }
}

async function toggleActivo(registro) {
  error.value = null
  try {
    await maestrosService[tabActiva.value].setActivo(registro.id, !registro.activo)
    await cargarRegistros()
  } catch (e) {
    error.value = e.message
  }
}
</script>

<template>
  <div>
    <VSection title="Maestros">
      <div class="mb-4 flex gap-1 border-b border-gray-200">
        <button
          v-for="tab in tabs"
          :key="tab"
          type="button"
          class="px-3 py-2 text-sm"
          :class="
            tab === tabActiva
              ? 'border-b-2 border-gray-900 font-medium text-gray-900'
              : 'text-gray-500 hover:text-gray-700'
          "
          @click="tabActiva = tab"
        >
          {{ ENTIDADES[tab].label }}
        </button>
      </div>

      <div v-if="error" class="mb-3 rounded border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
        {{ error }}
      </div>

      <div class="mb-3 flex justify-end">
        <button
          type="button"
          class="rounded bg-gray-900 px-3 py-1.5 text-sm text-white hover:bg-gray-700"
          @click="abrirNuevo"
        >
          + Nuevo{{ tabActiva === 'patentes' ? 'a' : '' }} {{ entidadActual.label.slice(0, -1).toLowerCase() }}
        </button>
      </div>

      <VCard>
        <p v-if="cargando" class="text-sm text-gray-500">Cargando…</p>
        <VTable v-else :columns="columnasConAcciones" :rows="registros">
          <template #cell-activo="{ row }">
            <VBadge :variant="row.activo ? 'success' : 'default'">
              {{ row.activo ? 'Activo' : 'Inactivo' }}
            </VBadge>
          </template>
          <template #cell-acciones="{ row }">
            <div class="flex gap-3 text-sm">
              <button type="button" class="text-blue-600 hover:underline" @click="abrirEdicion(row)">
                Editar
              </button>
              <button type="button" class="text-gray-500 hover:underline" @click="toggleActivo(row)">
                {{ row.activo ? 'Desactivar' : 'Activar' }}
              </button>
            </div>
          </template>
        </VTable>
        <p v-if="!cargando && !registros.length" class="py-4 text-center text-sm text-gray-400">
          No hay {{ entidadActual.label.toLowerCase() }} cargados todavía.
        </p>
      </VCard>
    </VSection>

    <VModal
      :open="modalAbierto"
      :title="(editandoId ? 'Editar ' : 'Nuevo/a ') + entidadActual.label.slice(0, -1)"
      @update:open="modalAbierto = $event"
    >
      <form class="space-y-3" @submit.prevent="guardar">
        <label v-for="campo in entidadActual.campos" :key="campo.key" class="block text-sm">
          <template v-if="campo.type === 'checkbox'">
            <span class="flex items-center gap-2">
              <input v-model="formData[campo.key]" type="checkbox" />
              {{ campo.label }}
            </span>
          </template>
          <template v-else-if="campo.type === 'number'">
            {{ campo.label }}
            <input
              v-model.number="formData[campo.key]"
              type="number"
              class="mt-1 w-full rounded border-gray-300 text-sm"
            />
          </template>
          <template v-else>
            {{ campo.label }}
            <input
              v-model="formData[campo.key]"
              type="text"
              class="mt-1 w-full rounded border-gray-300 text-sm"
            />
          </template>
        </label>

        <label class="flex items-center gap-2 text-sm">
          <input v-model="formData.activo" type="checkbox" />
          Activo
        </label>

        <div class="flex justify-end gap-2 pt-2">
          <button
            type="button"
            class="rounded px-3 py-1.5 text-sm text-gray-600 hover:bg-gray-100"
            @click="modalAbierto = false"
          >
            Cancelar
          </button>
          <button
            type="submit"
            :disabled="guardando"
            class="rounded bg-gray-900 px-3 py-1.5 text-sm text-white hover:bg-gray-700 disabled:opacity-50"
          >
            {{ guardando ? 'Guardando…' : 'Guardar' }}
          </button>
        </div>
      </form>
    </VModal>
  </div>
</template>
