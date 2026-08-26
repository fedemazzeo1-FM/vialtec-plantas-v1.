<script setup>
// Vista de Fórmulas: listado + alta/edición en modal con edición inline de insumos.
// Toda la persistencia pasa por formulas.service.js — este componente no llama a
// Supabase directamente (memory/conventions.md).

import { reactive, ref, watch } from 'vue'
import VCard from '@/components/shared/VCard.vue'
import VTable from '@/components/shared/VTable.vue'
import VModal from '@/components/shared/VModal.vue'
import VBadge from '@/components/shared/VBadge.vue'
import VSection from '@/components/shared/VSection.vue'
import {
  fetchFormulas,
  crearFormula,
  actualizarFormula,
  setFormulaActiva,
} from '@/modules/maestros/services/formulas.service'

const UNIDADES_INSUMO = ['%', 'kg', 'tn', 'L']

const columnas = [
  { key: 'nombre', label: 'Nombre' },
  { key: 'tipo', label: 'Tipo' },
  { key: 'unidad', label: 'Unidad' },
  { key: 'activo', label: 'Estado' },
  { key: 'acciones', label: '' },
]

const columnasInsumos = [
  { key: 'material', label: 'Material' },
  { key: 'cantidad', label: 'Cantidad' },
  { key: 'unidad', label: 'Unidad' },
  { key: 'acciones', label: '' },
]

const formulas = ref([])
const cargando = ref(false)
const error = ref(null)

const modalAbierto = ref(false)
const guardando = ref(false)
const editandoId = ref(null)

function formularioVacio() {
  return {
    nombre: '',
    tipo: 'asfalto',
    unidad: 'tn',
    activo: true,
    insumos: [],
  }
}

const formData = reactive(formularioVacio())

// La unidad de producción se deriva del tipo (tn para asfalto, m3 para
// hormigón) — ver memory/business-rules.md. No es un campo libre.
watch(
  () => formData.tipo,
  (tipo) => {
    formData.unidad = tipo === 'hormigon' ? 'm3' : 'tn'
  }
)

async function cargarFormulas() {
  cargando.value = true
  error.value = null
  try {
    formulas.value = await fetchFormulas()
  } catch (e) {
    error.value = e.message
  } finally {
    cargando.value = false
  }
}

function nuevoInsumo() {
  return { id: crypto.randomUUID(), material: '', cantidad: 0, unidad: '%' }
}

function agregarInsumo() {
  formData.insumos.push(nuevoInsumo())
}

function quitarInsumo(id) {
  formData.insumos = formData.insumos.filter((i) => i.id !== id)
}

function abrirNueva() {
  editandoId.value = null
  Object.assign(formData, formularioVacio())
  modalAbierto.value = true
}

function abrirEdicion(formula) {
  editandoId.value = formula.id
  Object.assign(formData, {
    nombre: formula.nombre,
    tipo: formula.tipo,
    unidad: formula.unidad,
    activo: formula.activo,
    // clonar para no mutar la fila de la lista mientras se edita en el modal
    insumos: (formula.insumos || []).map((i) => ({ ...i, id: i.id ?? crypto.randomUUID() })),
  })
  modalAbierto.value = true
}

async function guardar() {
  if (!formData.nombre.trim()) {
    error.value = 'La fórmula necesita un nombre.'
    return
  }

  const insumosValidos = formData.insumos.filter((i) => i.material.trim())

  guardando.value = true
  error.value = null
  try {
    const payload = { ...formData, insumos: insumosValidos }
    if (editandoId.value) {
      await actualizarFormula(editandoId.value, payload)
    } else {
      await crearFormula(payload)
    }
    modalAbierto.value = false
    await cargarFormulas()
  } catch (e) {
    error.value = e.message
  } finally {
    guardando.value = false
  }
}

async function toggleActivo(formula) {
  error.value = null
  try {
    await setFormulaActiva(formula.id, !formula.activo)
    await cargarFormulas()
  } catch (e) {
    error.value = e.message
  }
}

cargarFormulas()
</script>

<template>
  <div>
    <VSection title="Fórmulas">
      <div v-if="error" class="mb-3 rounded border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
        {{ error }}
      </div>

      <div class="mb-3 flex justify-end">
        <button
          type="button"
          class="rounded bg-gray-900 px-3 py-1.5 text-sm text-white hover:bg-gray-700"
          @click="abrirNueva"
        >
          + Nueva fórmula
        </button>
      </div>

      <VCard>
        <p v-if="cargando" class="text-sm text-gray-500">Cargando…</p>
        <VTable v-else :columns="columnas" :rows="formulas">
          <template #cell-tipo="{ row }">
            {{ row.tipo === 'hormigon' ? 'Hormigón' : 'Asfalto' }}
          </template>
          <template #cell-activo="{ row }">
            <VBadge :variant="row.activo ? 'success' : 'default'">
              {{ row.activo ? 'Activa' : 'Inactiva' }}
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
      </VCard>
    </VSection>

    <VModal
      :open="modalAbierto"
      :title="editandoId ? 'Editar fórmula' : 'Nueva fórmula'"
      @update:open="modalAbierto = $event"
    >
      <form class="space-y-4" @submit.prevent="guardar">
        <div class="grid grid-cols-2 gap-3">
          <label class="text-sm">
            Nombre
            <input
              v-model="formData.nombre"
              type="text"
              class="mt-1 w-full rounded border-gray-300 text-sm"
              placeholder="Ej: CAC D19"
            />
          </label>

          <label class="text-sm">
            Tipo
            <select v-model="formData.tipo" class="mt-1 w-full rounded border-gray-300 text-sm">
              <option value="asfalto">Asfalto</option>
              <option value="hormigon">Hormigón</option>
            </select>
          </label>

          <label class="text-sm">
            Unidad de producción
            <input
              :value="formData.unidad"
              type="text"
              disabled
              class="mt-1 w-full rounded border-gray-200 bg-gray-50 text-sm text-gray-500"
            />
          </label>

          <label class="flex items-center gap-2 self-end text-sm">
            <input v-model="formData.activo" type="checkbox" />
            Activa
          </label>
        </div>

        <div>
          <div class="mb-2 flex items-center justify-between">
            <p class="text-sm font-medium">Insumos</p>
            <button type="button" class="text-sm text-blue-600 hover:underline" @click="agregarInsumo">
              + Agregar insumo
            </button>
          </div>

          <VTable :columns="columnasInsumos" :rows="formData.insumos">
            <template #cell-material="{ row }">
              <input
                v-model="row.material"
                type="text"
                class="w-full rounded border-gray-300 text-sm"
                placeholder="Material"
              />
            </template>
            <template #cell-cantidad="{ row }">
              <input
                v-model.number="row.cantidad"
                type="number"
                step="0.01"
                class="w-24 rounded border-gray-300 text-sm"
              />
            </template>
            <template #cell-unidad="{ row }">
              <select v-model="row.unidad" class="rounded border-gray-300 text-sm">
                <option v-for="u in UNIDADES_INSUMO" :key="u" :value="u">{{ u }}</option>
              </select>
            </template>
            <template #cell-acciones="{ row }">
              <button type="button" class="text-red-500 hover:text-red-700" @click="quitarInsumo(row.id)">
                Quitar
              </button>
            </template>
          </VTable>

          <p v-if="!formData.insumos.length" class="mt-2 text-sm text-gray-400">
            Sin insumos cargados todavía.
          </p>
        </div>

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
