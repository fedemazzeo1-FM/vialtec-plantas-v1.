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
import VButton from '@/components/shared/VButton.vue'
import {
  fetchFormulas,
  crearFormula,
  actualizarFormula,
  setFormulaActiva,
} from '@/modules/maestros/services/formulas.service'
import { materialesService } from '@/modules/maestros/services/maestros.service'
import {
  LISTA_TIPOS_PRODUCTO,
  TIPO_PRODUCTO_INICIAL,
  nombreTipoProducto,
  unidadTipoProducto,
} from '@/config/tipos-producto'

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
// Catálogo de materiales (Maestros → Materiales, el mismo de Stock). El insumo
// de una fórmula tiene que ser uno de estos: el descuento de stock busca el
// material por nombre (plantas_buscar_material_id), así que un nombre que no
// esté en el catálogo no descuenta de ningún lado.
const materiales = ref([])
const cargando = ref(false)
const error = ref(null)

const modalAbierto = ref(false)
const guardando = ref(false)
const editandoId = ref(null)

function formularioVacio() {
  return {
    nombre: '',
    tipo: TIPO_PRODUCTO_INICIAL,
    unidad: unidadTipoProducto(TIPO_PRODUCTO_INICIAL),
    activo: true,
    insumos: [],
  }
}

const formData = reactive(formularioVacio())

// La unidad de producción se deriva del tipo (config/tipos-producto.js:
// asfalto tn, hormigón m3, mezcla cemento tn). No es un campo libre.
watch(
  () => formData.tipo,
  (tipo) => {
    formData.unidad = unidadTipoProducto(tipo)
  }
)

async function cargarFormulas() {
  cargando.value = true
  error.value = null
  try {
    const [listaFormulas, listaMateriales] = await Promise.all([
      fetchFormulas(),
      materialesService.fetch({ soloActivos: true }),
    ])
    formulas.value = listaFormulas
    materiales.value = listaMateriales
  } catch (e) {
    error.value = e.message
  } finally {
    cargando.value = false
  }
}

// Mismo criterio de comparación que plantas_buscar_material_id (sin
// distinguir mayúsculas ni espacios al borde).
function buscarMaterial(nombre) {
  const clave = (nombre || '').trim().toLowerCase()
  if (!clave) return null
  return materiales.value.find((m) => m.nombre.trim().toLowerCase() === clave) ?? null
}

function insumoInvalido(insumo) {
  return Boolean((insumo.material || '').trim()) && !buscarMaterial(insumo.material)
}

// Al salir del campo, deja el nombre tal cual figura en el catálogo.
function normalizarMaterial(insumo) {
  const material = buscarMaterial(insumo.material)
  if (material) insumo.material = material.nombre
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
  error.value = null
  editandoId.value = null
  Object.assign(formData, formularioVacio())
  modalAbierto.value = true
}

function abrirEdicion(formula) {
  error.value = null
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

  const insumosValidos = formData.insumos.filter((i) => (i.material || '').trim())

  const fueraDeCatalogo = insumosValidos.filter(insumoInvalido)
  if (fueraDeCatalogo.length) {
    error.value = `Estos insumos no existen en el catálogo de materiales: ${fueraDeCatalogo
      .map((i) => i.material.trim())
      .join(', ')}. Elegí uno de la lista (o dalo de alta en Maestros → Materiales).`
    return
  }
  insumosValidos.forEach(normalizarMaterial)

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
      <div v-if="error" class="mb-3 rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
        {{ error }}
      </div>

      <div class="mb-3 flex justify-end">
        <VButton size="sm" @click="abrirNueva">+ Nueva fórmula</VButton>
      </div>

      <VCard>
        <p v-if="cargando" class="text-sm text-text-soft">Cargando…</p>
        <VTable v-else :columns="columnas" :rows="formulas">
          <template #cell-tipo="{ row }">
            {{ nombreTipoProducto(row.tipo) }}
          </template>
          <template #cell-activo="{ row }">
            <VBadge :variant="row.activo ? 'success' : 'default'">
              {{ row.activo ? 'Activa' : 'Inactiva' }}
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
      </VCard>
    </VSection>

    <VModal
      :open="modalAbierto"
      :title="editandoId ? 'Editar fórmula' : 'Nueva fórmula'"
      @update:open="modalAbierto = $event"
    >
      <form class="space-y-4" @submit.prevent="guardar">
        <div class="grid grid-cols-2 gap-3">
          <label class="text-sm text-text-mid">
            Nombre
            <input
              v-model="formData.nombre"
              type="text"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
              placeholder="Ej: CAC D19"
            />
          </label>

          <label class="text-sm text-text-mid">
            Tipo
            <select
              v-model="formData.tipo"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            >
              <option v-for="t in LISTA_TIPOS_PRODUCTO" :key="t.id" :value="t.id">{{ t.nombre }}</option>
            </select>
          </label>

          <label class="text-sm text-text-mid">
            Unidad de producción
            <input
              :value="formData.unidad"
              type="text"
              disabled
              class="mt-1 w-full rounded-lg border border-border bg-panel px-3 py-2 text-sm text-text-soft"
            />
          </label>

          <label class="flex items-center gap-2 self-end text-sm text-text-mid">
            <input v-model="formData.activo" type="checkbox" />
            Activa
          </label>
        </div>

        <div>
          <div class="mb-2 flex items-center justify-between">
            <p class="text-sm font-semibold text-text">Insumos</p>
            <VButton type="button" variant="ghost" size="sm" @click="agregarInsumo">+ Agregar insumo</VButton>
          </div>

          <VTable :columns="columnasInsumos" :rows="formData.insumos">
            <template #cell-material="{ row }">
              <input
                v-model="row.material"
                type="text"
                list="materiales-formula"
                autocomplete="off"
                class="w-full rounded-lg border px-3 py-2 text-sm focus:outline-none"
                :class="insumoInvalido(row) ? 'border-danger focus:border-danger' : 'border-border focus:border-vialtec'"
                placeholder="Elegir material…"
                @change="normalizarMaterial(row)"
              />
              <p v-if="insumoInvalido(row)" class="mt-1 text-xs text-danger">No está en el catálogo de materiales.</p>
            </template>
            <template #cell-cantidad="{ row }">
              <input
                v-model.number="row.cantidad"
                type="number"
                step="0.01"
                class="w-24 rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
              />
            </template>
            <template #cell-unidad="{ row }">
              <select
                v-model="row.unidad"
                class="rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
              >
                <option v-for="u in UNIDADES_INSUMO" :key="u" :value="u">{{ u }}</option>
              </select>
            </template>
            <template #cell-acciones="{ row }">
              <VButton type="button" variant="ghost" size="sm" @click="quitarInsumo(row.id)">Quitar</VButton>
            </template>
          </VTable>

          <datalist id="materiales-formula">
            <option v-for="m in materiales" :key="m.id" :value="m.nombre" />
          </datalist>

          <p v-if="!formData.insumos.length" class="mt-2 text-sm text-text-soft">
            Sin insumos cargados todavía.
          </p>
        </div>

        <p v-if="error" class="rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
          {{ error }}
        </p>

        <div class="flex justify-end gap-2 pt-2">
          <VButton type="button" variant="secondary" @click="modalAbierto = false">Cancelar</VButton>
          <VButton type="submit" :disabled="guardando">{{ guardando ? 'Guardando…' : 'Guardar' }}</VButton>
        </div>
      </form>
    </VModal>
  </div>
</template>
