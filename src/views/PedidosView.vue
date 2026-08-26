<script setup>
// Vista de Pedidos: historial completo con filtros, alta y cambios de estado.
// Toda la persistencia pasa por pedidos.service.js — este componente no llama
// a Supabase directamente (memory/conventions.md).

import { computed, reactive, ref } from 'vue'
import VCard from '@/components/shared/VCard.vue'
import VTable from '@/components/shared/VTable.vue'
import VModal from '@/components/shared/VModal.vue'
import VBadge from '@/components/shared/VBadge.vue'
import VSection from '@/components/shared/VSection.vue'
import {
  fetchPedidos,
  crearPedido,
  confirmarPedido,
  despacharPedido,
  cancelarPedido,
} from '@/modules/pedidos/services/pedidos.service'
import { fetchObras } from '@/services/flota.service'
import { fetchFormulas } from '@/modules/maestros/services/formulas.service'

const ESTADOS = ['solicitado', 'confirmado', 'despachado', 'cancelado']
const VARIANTE_ESTADO = {
  solicitado: 'default',
  confirmado: 'info',
  despachado: 'success',
  cancelado: 'danger',
}

const columnas = [
  { key: 'obraNombre', label: 'Obra' },
  { key: 'formulaNombre', label: 'Fórmula' },
  { key: 'tipo', label: 'Tipo' },
  { key: 'cantidad_solicitada', label: 'Solicitado' },
  { key: 'cantidad_despachada', label: 'Despachado' },
  { key: 'fecha_programada', label: 'Fecha' },
  { key: 'estado', label: 'Estado' },
  { key: 'acciones', label: '' },
]

const pedidos = ref([])
const obras = ref([])
const formulas = ref([])
const cargando = ref(false)
const error = ref(null)

const filtros = reactive({ estado: '', obraId: '', tipo: '', desde: '', hasta: '' })

const obrasPorId = computed(() => Object.fromEntries(obras.value.map((o) => [o.id, o])))
const formulasPorId = computed(() => Object.fromEntries(formulas.value.map((f) => [f.id, f])))

const filas = computed(() =>
  pedidos.value.map((p) => ({
    ...p,
    obraNombre: obrasPorId.value[p.obra_id]?.nombre ?? `Obra #${p.obra_id}`,
    formulaNombre: formulasPorId.value[p.formula_id]?.nombre ?? '—',
  }))
)

async function cargarBase() {
  const [listaObras, listaFormulas] = await Promise.all([fetchObras(), fetchFormulas({ soloActivas: true })])
  obras.value = listaObras
  formulas.value = listaFormulas
}

async function cargarPedidos() {
  cargando.value = true
  error.value = null
  try {
    pedidos.value = await fetchPedidos({
      estado: filtros.estado || undefined,
      obraId: filtros.obraId || undefined,
      tipo: filtros.tipo || undefined,
      desde: filtros.desde || undefined,
      hasta: filtros.hasta || undefined,
    })
  } catch (e) {
    error.value = e.message
  } finally {
    cargando.value = false
  }
}

function limpiarFiltros() {
  filtros.estado = ''
  filtros.obraId = ''
  filtros.tipo = ''
  filtros.desde = ''
  filtros.hasta = ''
  cargarPedidos()
}

// ---------------------------------------------------------------------------
// Alta de pedido
// ---------------------------------------------------------------------------

const modalAbierto = ref(false)
const guardando = ref(false)

function formularioVacio() {
  return { obra_id: '', formula_id: '', tipo: '', cantidad_solicitada: null, fecha_programada: '', observaciones: '' }
}
const formData = reactive(formularioVacio())

function abrirNuevo() {
  Object.assign(formData, formularioVacio())
  modalAbierto.value = true
}

function alSeleccionarFormula() {
  const formula = formulasPorId.value[formData.formula_id]
  formData.tipo = formula?.tipo ?? ''
}

async function guardarNuevo() {
  if (!formData.obra_id || !formData.formula_id || !formData.cantidad_solicitada || !formData.fecha_programada) {
    error.value = 'Completá obra, fórmula, cantidad y fecha.'
    return
  }

  guardando.value = true
  error.value = null
  try {
    await crearPedido({
      obra_id: formData.obra_id,
      formula_id: formData.formula_id,
      tipo: formData.tipo,
      cantidad_solicitada: formData.cantidad_solicitada,
      fecha_programada: formData.fecha_programada,
      observaciones: formData.observaciones || null,
    })
    modalAbierto.value = false
    await cargarPedidos()
  } catch (e) {
    error.value = e.message
  } finally {
    guardando.value = false
  }
}

// ---------------------------------------------------------------------------
// Confirmar
// ---------------------------------------------------------------------------

async function confirmar(pedido) {
  error.value = null
  try {
    await confirmarPedido(pedido.id)
    await cargarPedidos()
  } catch (e) {
    error.value = e.message
  }
}

// ---------------------------------------------------------------------------
// Despacho (confirmación final de despacho)
// ---------------------------------------------------------------------------

const modalDespachoAbierto = ref(false)
const pedidoDespacho = ref(null)
const cantidadDespacho = ref(null)
const despachando = ref(false)

function abrirDespacho(pedido) {
  pedidoDespacho.value = pedido
  cantidadDespacho.value = pedido.cantidad_solicitada
  modalDespachoAbierto.value = true
}

async function confirmarDespacho() {
  if (!(cantidadDespacho.value > 0)) {
    error.value = 'La cantidad despachada tiene que ser mayor a 0.'
    return
  }
  despachando.value = true
  error.value = null
  try {
    await despacharPedido(pedidoDespacho.value.id, cantidadDespacho.value)
    modalDespachoAbierto.value = false
    await cargarPedidos()
  } catch (e) {
    error.value = e.message
  } finally {
    despachando.value = false
  }
}

// ---------------------------------------------------------------------------
// Cancelación
// ---------------------------------------------------------------------------

const modalCancelAbierto = ref(false)
const pedidoCancelar = ref(null)
const motivoCancelacion = ref('')
const cancelando = ref(false)

function abrirCancelacion(pedido) {
  pedidoCancelar.value = pedido
  motivoCancelacion.value = ''
  modalCancelAbierto.value = true
}

async function confirmarCancelacion() {
  cancelando.value = true
  error.value = null
  try {
    await cancelarPedido(pedidoCancelar.value.id, motivoCancelacion.value)
    modalCancelAbierto.value = false
    await cargarPedidos()
  } catch (e) {
    error.value = e.message
  } finally {
    cancelando.value = false
  }
}

cargarBase().then(cargarPedidos)
</script>

<template>
  <div>
    <VSection title="Pedidos">
      <div v-if="error" class="mb-3 rounded border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
        {{ error }}
      </div>

      <VCard class="mb-4">
        <div class="grid grid-cols-2 gap-3 md:grid-cols-5">
          <label class="text-sm">
            Estado
            <select v-model="filtros.estado" class="mt-1 w-full rounded border-gray-300 text-sm">
              <option value="">Todos</option>
              <option v-for="e in ESTADOS" :key="e" :value="e">{{ e }}</option>
            </select>
          </label>
          <label class="text-sm">
            Obra
            <select v-model="filtros.obraId" class="mt-1 w-full rounded border-gray-300 text-sm">
              <option value="">Todas</option>
              <option v-for="o in obras" :key="o.id" :value="o.id">{{ o.nombre }}</option>
            </select>
          </label>
          <label class="text-sm">
            Tipo
            <select v-model="filtros.tipo" class="mt-1 w-full rounded border-gray-300 text-sm">
              <option value="">Todos</option>
              <option value="asfalto">Asfalto</option>
              <option value="hormigon">Hormigón</option>
            </select>
          </label>
          <label class="text-sm">
            Desde
            <input v-model="filtros.desde" type="date" class="mt-1 w-full rounded border-gray-300 text-sm" />
          </label>
          <label class="text-sm">
            Hasta
            <input v-model="filtros.hasta" type="date" class="mt-1 w-full rounded border-gray-300 text-sm" />
          </label>
        </div>
        <div class="mt-3 flex gap-2">
          <button type="button" class="rounded bg-gray-900 px-3 py-1.5 text-sm text-white hover:bg-gray-700" @click="cargarPedidos">
            Filtrar
          </button>
          <button type="button" class="rounded px-3 py-1.5 text-sm text-gray-600 hover:bg-gray-100" @click="limpiarFiltros">
            Limpiar
          </button>
        </div>
      </VCard>

      <div class="mb-3 flex justify-end">
        <button type="button" class="rounded bg-gray-900 px-3 py-1.5 text-sm text-white hover:bg-gray-700" @click="abrirNuevo">
          + Nuevo pedido
        </button>
      </div>

      <VCard>
        <p v-if="cargando" class="text-sm text-gray-500">Cargando…</p>
        <VTable v-else :columns="columnas" :rows="filas">
          <template #cell-tipo="{ row }">
            {{ row.tipo === 'hormigon' ? 'Hormigón' : 'Asfalto' }}
          </template>
          <template #cell-cantidad_solicitada="{ row }">
            {{ row.cantidad_solicitada }} {{ row.tipo === 'hormigon' ? 'm³' : 'tn' }}
          </template>
          <template #cell-cantidad_despachada="{ row }">
            <span v-if="row.cantidad_despachada != null">
              {{ row.cantidad_despachada }} {{ row.tipo === 'hormigon' ? 'm³' : 'tn' }}
            </span>
            <span v-else class="text-gray-300">—</span>
          </template>
          <template #cell-estado="{ row }">
            <VBadge :variant="VARIANTE_ESTADO[row.estado]">{{ row.estado }}</VBadge>
          </template>
          <template #cell-acciones="{ row }">
            <div class="flex gap-3 text-sm">
              <button v-if="row.estado === 'solicitado'" type="button" class="text-blue-600 hover:underline" @click="confirmar(row)">
                Confirmar
              </button>
              <button v-if="row.estado === 'confirmado'" type="button" class="text-green-600 hover:underline" @click="abrirDespacho(row)">
                Despachar
              </button>
              <button
                v-if="row.estado === 'solicitado' || row.estado === 'confirmado'"
                type="button"
                class="text-red-500 hover:underline"
                @click="abrirCancelacion(row)"
              >
                Cancelar
              </button>
            </div>
          </template>
        </VTable>
        <p v-if="!cargando && !filas.length" class="py-4 text-center text-sm text-gray-400">
          No hay pedidos que coincidan con el filtro.
        </p>
      </VCard>
    </VSection>

    <!-- Alta de pedido -->
    <VModal :open="modalAbierto" title="Nuevo pedido" @update:open="modalAbierto = $event">
      <form class="space-y-3" @submit.prevent="guardarNuevo">
        <label class="block text-sm">
          Obra
          <select v-model="formData.obra_id" class="mt-1 w-full rounded border-gray-300 text-sm">
            <option value="" disabled>Elegir obra…</option>
            <option v-for="o in obras" :key="o.id" :value="o.id">{{ o.nombre }}</option>
          </select>
        </label>
        <label class="block text-sm">
          Fórmula
          <select v-model="formData.formula_id" class="mt-1 w-full rounded border-gray-300 text-sm" @change="alSeleccionarFormula">
            <option value="" disabled>Elegir fórmula…</option>
            <option v-for="f in formulas" :key="f.id" :value="f.id">{{ f.nombre }}</option>
          </select>
        </label>
        <label class="block text-sm">
          Cantidad solicitada ({{ formData.tipo === 'hormigon' ? 'm³' : 'tn' }})
          <input v-model.number="formData.cantidad_solicitada" type="number" step="0.01" class="mt-1 w-full rounded border-gray-300 text-sm" />
        </label>
        <label class="block text-sm">
          Fecha programada
          <input v-model="formData.fecha_programada" type="date" class="mt-1 w-full rounded border-gray-300 text-sm" />
        </label>
        <label class="block text-sm">
          Observaciones
          <textarea v-model="formData.observaciones" rows="2" class="mt-1 w-full rounded border-gray-300 text-sm"></textarea>
        </label>

        <div class="flex justify-end gap-2 pt-2">
          <button type="button" class="rounded px-3 py-1.5 text-sm text-gray-600 hover:bg-gray-100" @click="modalAbierto = false">
            Cancelar
          </button>
          <button type="submit" :disabled="guardando" class="rounded bg-gray-900 px-3 py-1.5 text-sm text-white hover:bg-gray-700 disabled:opacity-50">
            {{ guardando ? 'Guardando…' : 'Crear pedido' }}
          </button>
        </div>
      </form>
    </VModal>

    <!-- Despacho -->
    <VModal :open="modalDespachoAbierto" title="Confirmar despacho" @update:open="modalDespachoAbierto = $event">
      <form class="space-y-3" @submit.prevent="confirmarDespacho">
        <p class="text-sm text-gray-600">
          Obra: <strong>{{ obrasPorId[pedidoDespacho?.obra_id]?.nombre }}</strong> —
          Solicitado: {{ pedidoDespacho?.cantidad_solicitada }} {{ pedidoDespacho?.tipo === 'hormigon' ? 'm³' : 'tn' }}
        </p>
        <label class="block text-sm">
          Cantidad realmente despachada
          <input v-model.number="cantidadDespacho" type="number" step="0.01" class="mt-1 w-full rounded border-gray-300 text-sm" />
        </label>
        <div class="flex justify-end gap-2 pt-2">
          <button type="button" class="rounded px-3 py-1.5 text-sm text-gray-600 hover:bg-gray-100" @click="modalDespachoAbierto = false">
            Cancelar
          </button>
          <button type="submit" :disabled="despachando" class="rounded bg-gray-900 px-3 py-1.5 text-sm text-white hover:bg-gray-700 disabled:opacity-50">
            {{ despachando ? 'Guardando…' : 'Confirmar despacho' }}
          </button>
        </div>
      </form>
    </VModal>

    <!-- Cancelación -->
    <VModal :open="modalCancelAbierto" title="Cancelar pedido" @update:open="modalCancelAbierto = $event">
      <form class="space-y-3" @submit.prevent="confirmarCancelacion">
        <label class="block text-sm">
          Motivo (obligatorio)
          <textarea v-model="motivoCancelacion" rows="3" class="mt-1 w-full rounded border-gray-300 text-sm"></textarea>
        </label>
        <div class="flex justify-end gap-2 pt-2">
          <button type="button" class="rounded px-3 py-1.5 text-sm text-gray-600 hover:bg-gray-100" @click="modalCancelAbierto = false">
            Volver
          </button>
          <button type="submit" :disabled="cancelando" class="rounded bg-red-600 px-3 py-1.5 text-sm text-white hover:bg-red-700 disabled:opacity-50">
            {{ cancelando ? 'Guardando…' : 'Cancelar pedido' }}
          </button>
        </div>
      </form>
    </VModal>
  </div>
</template>
