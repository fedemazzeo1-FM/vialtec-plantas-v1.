<script setup>
// Vista de Maestros de planta: tabs para encargados, proveedores, patentes y
// choferes. Toda la persistencia pasa por maestros.service.js — este componente
// no llama a Supabase directamente (memory/conventions.md).

import { computed, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import VCard from '@/components/shared/VCard.vue'
import VTable from '@/components/shared/VTable.vue'
import VModal from '@/components/shared/VModal.vue'
import VBadge from '@/components/shared/VBadge.vue'
import VSection from '@/components/shared/VSection.vue'
import VButton from '@/components/shared/VButton.vue'
import { maestrosService } from '@/modules/maestros/services/maestros.service'

// Config declarativa por catálogo: columnas de tabla, campos de formulario y
// registro vacío. Evita repetir la vista 4 veces para 4 tablas casi idénticas.
const ENTIDADES = {
  encargados: {
    label: 'Encargados',
    nombreSingular: 'encargado',
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
    nombreSingular: 'proveedor',
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
  // Separación Vehículos Propios/Externos (2026-09-01, pedido de Federico —
  // relevado contra el legado: 30 patentes propias / 21 externas reales,
  // `es_externa` ya existía en el schema pero convivían sin distinción
  // visual clara en una sola tabla). Misma `plantas_patentes`, 2 tabs con
  // filtro fijo cada una (ver patentesPropiasService/patentesExternasService
  // en maestros.service.js) — "es_externa" ya no es columna/campo visible
  // porque queda implícito por la tab en la que se está parado.
  vehiculosPropios: {
    // Renombrado 2026-09-04 (pedido de Federico) de "Vehículos propios" a
    // "Camiones propios" — mismo catálogo/service, solo la etiqueta visible.
    label: 'Camiones propios',
    nombreSingular: 'camión propio',
    columnas: [
      { key: 'patente', label: 'Patente' },
      { key: 'tipo_camion', label: 'Tipo camión' },
      { key: 'tara', label: 'Tara (tn)' },
      { key: 'chofer_habitual', label: 'Chofer habitual' },
    ],
    campos: [
      { key: 'patente', label: 'Patente', type: 'text', required: true },
      { key: 'tipo_camion', label: 'Tipo de camión', type: 'text' },
      { key: 'tara', label: 'Tara (tn)', type: 'number' },
      { key: 'chofer_habitual', label: 'Chofer habitual', type: 'text' },
    ],
    vacio: () => ({ patente: '', tipo_camion: '', tara: null, chofer_habitual: '', activo: true }),
  },
  vehiculosExternos: {
    // Renombrado 2026-09-04 (pedido de Federico) de "Vehículos externos" a
    // "Camiones externos" — mismo catálogo/service, solo la etiqueta visible.
    label: 'Camiones externos',
    nombreSingular: 'camión externo',
    columnas: [
      { key: 'patente', label: 'Patente' },
      { key: 'tipo_camion', label: 'Tipo camión' },
      { key: 'tara', label: 'Tara (tn)' },
      { key: 'chofer_habitual', label: 'Chofer / transportista' },
    ],
    campos: [
      { key: 'patente', label: 'Patente', type: 'text', required: true },
      { key: 'tipo_camion', label: 'Tipo de camión', type: 'text' },
      { key: 'tara', label: 'Tara (tn)', type: 'number' },
      { key: 'chofer_habitual', label: 'Chofer / transportista', type: 'text' },
    ],
    vacio: () => ({ patente: '', tipo_camion: '', tara: null, chofer_habitual: '', activo: true }),
  },
  choferes: {
    label: 'Choferes',
    nombreSingular: 'chofer',
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
    nombreSingular: 'material',
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

// Persistencia de navegación (2026-09-01, memory/modules-status.md — "F5 /
// duplicar pestaña"): la tab activa se sincroniza con `?tab=` en la URL. Sin
// esto, recargar la página (o abrir el link desde otro lado) siempre volvía
// a "Encargados" aunque el usuario estuviera parado en "Materiales". Se usa
// `router.replace` (no `push`) para no ensuciar el historial con una entrada
// nueva por cada click de tab.
const route = useRoute()
const router = useRouter()
const tabActiva = ref(tabs.includes(route.query.tab) ? route.query.tab : tabs[0])
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

watch(
  tabActiva,
  (nueva) => {
    cargarRegistros()
    router.replace({ query: { ...route.query, tab: nueva } })
  },
  { immediate: true }
)

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
      <div class="mb-4 flex gap-1 overflow-x-auto border-b border-border">
        <button
          v-for="tab in tabs"
          :key="tab"
          type="button"
          class="shrink-0 whitespace-nowrap border-b-2 px-3 py-2 text-sm font-semibold transition-colors duration-150"
          :class="
            tab === tabActiva
              ? 'border-vialtec text-vialtec'
              : 'border-transparent text-text-soft hover:text-text-mid'
          "
          @click="tabActiva = tab"
        >
          {{ ENTIDADES[tab].label }}
        </button>
      </div>

      <div v-if="error" class="mb-3 rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
        {{ error }}
      </div>

      <div class="mb-3 flex justify-end">
        <VButton size="sm" @click="abrirNuevo"> + Nuevo {{ entidadActual.nombreSingular }} </VButton>
      </div>

      <VCard>
        <p v-if="cargando" class="text-sm text-text-soft">Cargando…</p>
        <VTable v-else :columns="columnasConAcciones" :rows="registros">
          <template #cell-activo="{ row }">
            <VBadge :variant="row.activo ? 'success' : 'default'">
              {{ row.activo ? 'Activo' : 'Inactivo' }}
            </VBadge>
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
        <p v-if="!cargando && !registros.length" class="py-4 text-center text-sm text-text-soft">
          No hay {{ entidadActual.label.toLowerCase() }} cargados todavía.
        </p>
      </VCard>
    </VSection>

    <VModal
      :open="modalAbierto"
      :title="(editandoId ? 'Editar ' : 'Nuevo ') + entidadActual.nombreSingular"
      @update:open="modalAbierto = $event"
    >
      <form class="space-y-3" @submit.prevent="guardar">
        <label v-for="campo in entidadActual.campos" :key="campo.key" class="block text-sm text-text-mid">
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
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            />
          </template>
          <template v-else>
            {{ campo.label }}
            <input
              v-model="formData[campo.key]"
              type="text"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            />
          </template>
        </label>

        <label class="flex items-center gap-2 text-sm text-text-mid">
          <input v-model="formData.activo" type="checkbox" />
          Activo
        </label>

        <div class="flex justify-end gap-2 pt-2">
          <VButton type="button" variant="secondary" @click="modalAbierto = false">Cancelar</VButton>
          <VButton type="submit" :disabled="guardando">{{ guardando ? 'Guardando…' : 'Guardar' }}</VButton>
        </div>
      </form>
    </VModal>
  </div>
</template>
