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
  registrarCargaHormigon,
} from '@/modules/pedidos/services/pedidos.service'
import { fetchObras } from '@/services/flota.service'
import { fetchFormulas } from '@/modules/maestros/services/formulas.service'
import { patentesService, choferesService } from '@/modules/maestros/services/maestros.service'

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
const patentes = ref([])
const choferes = ref([])
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
  const [listaObras, listaFormulas, listaPatentes, listaChoferes] = await Promise.all([
    fetchObras(),
    fetchFormulas({ soloActivas: true }),
    patentesService.fetch({ soloActivos: true }),
    choferesService.fetch({ soloActivos: true }),
  ])
  obras.value = listaObras
  formulas.value = listaFormulas
  patentes.value = listaPatentes
  choferes.value = listaChoferes
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

// ---------------------------------------------------------------------------
// Registro de carga de hormigón (una por camión/mixer, con remito)
// ---------------------------------------------------------------------------

const modalCargaHormigonAbierto = ref(false)
const pedidoCargaHormigon = ref(null)
const guardandoCarga = ref(false)

function formularioCargaVacio() {
  return { numero_remito: '', volumen_m3: null, patente_mixer: '', chofer: '', fecha_carga: '', observaciones: '' }
}
const formCarga = reactive(formularioCargaVacio())

function formatDatetimeLocal(date) {
  const pad = (n) => String(n).padStart(2, '0')
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`
}

const saldoCargaHormigon = computed(() => {
  if (!pedidoCargaHormigon.value) return 0
  return Number(pedidoCargaHormigon.value.cantidad_solicitada) - Number(pedidoCargaHormigon.value.cantidad_despachada || 0)
})

function abrirCargaHormigon(pedido) {
  pedidoCargaHormigon.value = pedido
  Object.assign(formCarga, formularioCargaVacio())
  formCarga.fecha_carga = formatDatetimeLocal(new Date())
  modalCargaHormigonAbierto.value = true
}

function alCambiarPatenteMixer() {
  const encontrada = patentes.value.find((p) => p.patente === formCarga.patente_mixer)
  if (encontrada?.chofer_habitual) formCarga.chofer = encontrada.chofer_habitual
}

async function guardarCargaHormigon() {
  if (!formCarga.numero_remito.trim()) {
    error.value = 'El número de remito es obligatorio.'
    return
  }
  if (!(Number(formCarga.volumen_m3) > 0)) {
    error.value = 'El volumen del viaje tiene que ser mayor a 0.'
    return
  }

  guardandoCarga.value = true
  error.value = null
  try {
    await registrarCargaHormigon({
      pedido_id: pedidoCargaHormigon.value.id,
      numero_remito: formCarga.numero_remito,
      volumen_m3: formCarga.volumen_m3,
      patente_mixer: formCarga.patente_mixer || null,
      chofer: formCarga.chofer || null,
      fecha_carga: formCarga.fecha_carga || new Date(),
      observaciones: formCarga.observaciones || null,
    })
    modalCargaHormigonAbierto.value = false
    await cargarPedidos()
  } catch (e) {
    error.value = e.message
  } finally {
    guardandoCarga.value = false
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
              <button
                v-if="row.estado === 'confirmado' && row.tipo === 'asfalto'"
                type="button"
                class="text-green-600 hover:underline"
                @click="abrirDespacho(row)"
              >
                Despachar
              </button>
              <button
                v-if="row.estado === 'confirmado' && row.tipo === 'hormigon'"
                type="button"
                class="text-green-600 hover:underline"
                @click="abrirCargaHormigon(row)"
              >
                Registrar carga
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

    <!-- Registro de carga de hormigón -->
    <VModal
      :open="modalCargaHormigonAbierto"
      title="Registrar carga de hormigón"
      @update:open="modalCargaHormigonAbierto = $event"
    >
      <form class="space-y-3" @submit.prevent="guardarCargaHormigon">
        <p class="text-sm text-gray-600">
          Obra: <strong>{{ obrasPorId[pedidoCargaHormigon?.obra_id]?.nombre }}</strong> —
          Saldo pendiente: {{ saldoCargaHormigon.toFixed(1) }} m³
        </p>

        <label class="block text-sm">
          N° de remito (obligatorio)
          <input v-model="formCarga.numero_remito" type="text" class="mt-1 w-full rounded border-gray-300 text-sm" />
        </label>
        <label class="block text-sm">
          Volumen del viaje (m³)
          <input v-model.number="formCarga.volumen_m3" type="number" step="0.01" class="mt-1 w-full rounded border-gray-300 text-sm" />
        </label>

        <div class="grid grid-cols-2 gap-3">
          <label class="text-sm">
            Patente del mixer
            <input
              v-model="formCarga.patente_mixer"
              list="patentes-mixer"
              class="mt-1 w-full rounded border-gray-300 text-sm"
              @change="alCambiarPatenteMixer"
            />
          </label>
          <label class="text-sm">
            Chofer
            <input v-model="formCarga.chofer" list="choferes-conocidos" class="mt-1 w-full rounded border-gray-300 text-sm" />
          </label>
        </div>

        <label class="block text-sm">
          Fecha / hora de salida
          <input v-model="formCarga.fecha_carga" type="datetime-local" class="mt-1 w-full rounded border-gray-300 text-sm" />
        </label>
        <label class="block text-sm">
          Observaciones
          <textarea v-model="formCarga.observaciones" rows="2" class="mt-1 w-full rounded border-gray-300 text-sm"></textarea>
        </label>

        <datalist id="patentes-mixer">
          <option v-for="p in patentes" :key="p.id" :value="p.patente" />
        </datalist>
        <datalist id="choferes-conocidos">
          <option v-for="c in choferes" :key="c.id" :value="c.nombre" />
        </datalist>

        <div class="flex justify-end gap-2 pt-2">
          <button type="button" class="rounded px-3 py-1.5 text-sm text-gray-600 hover:bg-gray-100" @click="modalCargaHormigonAbierto = false">
            Cancelar
          </button>
          <button
            type="submit"
            :disabled="guardandoCarga"
            class="rounded bg-gray-900 px-3 py-1.5 text-sm text-white hover:bg-gray-700 disabled:opacity-50"
          >
            {{ guardandoCarga ? 'Guardando…' : 'Registrar carga' }}
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
