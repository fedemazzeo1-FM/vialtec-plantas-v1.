<script setup>
// Vista de Báscula: pestañas de pesaje en paralelo (slots), historial de
// vales y doble impresión (vale / remito con acumulado dinámico) en filas de
// asfalto. Toda la persistencia pasa por bascula.service.js — este componente
// no llama a Supabase directamente (memory/conventions.md).
//
// registrarPesada() ahora llama a la RPC registrar_pesada_bascula (atómica,
// ver supabase/migrations/07_roles_y_rpc_atomicas.sql) — sin cambios acá,
// la interfaz del service es la misma. El historial de vales sí cambió: usa
// paginación server-side (fetchHistorialVales devuelve { filas, total }).

import { computed, reactive, ref } from 'vue'
import VCard from '@/components/shared/VCard.vue'
import VTable from '@/components/shared/VTable.vue'
import VModal from '@/components/shared/VModal.vue'
import VBadge from '@/components/shared/VBadge.vue'
import VSection from '@/components/shared/VSection.vue'
import ValeImprimible from '@/modules/bascula/components/ValeImprimible.vue'
import {
  fetchPedidosAsfaltoConSaldo,
  fetchHistorialVales,
  registrarPesada,
  obtenerAcumuladoObraHastaFecha,
} from '@/modules/bascula/services/bascula.service'
import { fetchObras } from '@/services/flota.service'
import { patentesService } from '@/modules/maestros/services/maestros.service'

const ETIQUETA_TIPO = {
  asfalto: 'Salida asfalto',
  hormigon: 'Hormigón',
  ingreso_arido: 'Ingreso árido',
}
const VARIANTE_TIPO = {
  asfalto: 'info',
  hormigon: 'default',
  ingreso_arido: 'warning',
}

const error = ref(null)

// ---------------------------------------------------------------------------
// Datos base (pedidos con saldo, obras, patentes conocidas)
// ---------------------------------------------------------------------------

const pedidosConSaldo = ref([])
const obras = ref([])
const patentes = ref([])

const obrasPorId = computed(() => Object.fromEntries(obras.value.map((o) => [o.id, o])))

async function cargarBase() {
  try {
    const [listaPedidos, listaObras, listaPatentes] = await Promise.all([
      fetchPedidosAsfaltoConSaldo(),
      fetchObras(),
      patentesService.fetch({ soloActivos: true }),
    ])
    pedidosConSaldo.value = listaPedidos
    obras.value = listaObras
    patentes.value = listaPatentes
  } catch (e) {
    error.value = e.message
  }
}

// ---------------------------------------------------------------------------
// Slots de pesaje en paralelo
// ---------------------------------------------------------------------------

let contadorSlot = 0
const slots = ref([])
const slotActivoId = ref(null)

const slotActivo = computed(() => slots.value.find((s) => s.id === slotActivoId.value) ?? null)

function formularioVacio(tipo) {
  return reactive(
    tipo === 'asfalto'
      ? { pedido_id: '', patente: '', chofer: '', peso_bruto: null, tara: null, observaciones: '' }
      : {
          material: '',
          proveedor: '',
          numero_remito: '',
          cantidad_remito: null,
          patente: '',
          chofer: '',
          peso_bruto: null,
          tara: null,
          observaciones: '',
        }
  )
}

function crearSlot(tipo) {
  contadorSlot += 1
  const slot = { id: contadorSlot, tipo, form: formularioVacio(tipo), guardando: false }
  slots.value.push(slot)
  slotActivoId.value = slot.id
}

function cerrarSlot(id) {
  const idx = slots.value.findIndex((s) => s.id === id)
  if (idx === -1) return
  slots.value.splice(idx, 1)
  if (slotActivoId.value === id) {
    slotActivoId.value = slots.value.length ? slots.value[slots.value.length - 1].id : null
  }
}

function netoSlot(slot) {
  const bruto = Number(slot.form.peso_bruto) || 0
  const tara = Number(slot.form.tara) || 0
  return (bruto - tara).toFixed(2)
}

function alCambiarPatente(slot) {
  const encontrada = patentes.value.find((p) => p.patente === slot.form.patente)
  if (encontrada) {
    if (encontrada.tara != null) slot.form.tara = encontrada.tara
    if (encontrada.chofer_habitual) slot.form.chofer = encontrada.chofer_habitual
  }
}

async function guardarPesada(slot) {
  const form = slot.form
  if (!(Number(form.peso_bruto) > 0) || form.tara == null || Number(form.tara) < 0) {
    error.value = 'Completá peso bruto y tara.'
    return
  }
  if (slot.tipo === 'asfalto' && !form.pedido_id) {
    error.value = 'Elegí un pedido de asfalto con saldo.'
    return
  }

  if (slot.tipo === 'ingreso_arido' && (!form.material || !form.proveedor)) {
    error.value = 'Completá material y proveedor del ingreso.'
    return
  }

  const pedido = slot.tipo === 'asfalto' ? pedidosConSaldo.value.find((p) => p.id === form.pedido_id) : null

  slot.guardando = true
  error.value = null
  try {
    await registrarPesada({
      tipo_vale: slot.tipo,
      pedido_id: slot.tipo === 'asfalto' ? form.pedido_id : null,
      obra_id: pedido?.obra_id ?? null,
      patente: form.patente || null,
      chofer: form.chofer || null,
      peso_bruto: form.peso_bruto,
      tara: form.tara,
      observaciones: form.observaciones || null,
      ...(slot.tipo === 'ingreso_arido'
        ? {
            material: form.material,
            proveedor: form.proveedor,
            numero_remito: form.numero_remito || null,
            cantidad_remito: form.cantidad_remito,
          }
        : {}),
    })
    // Al confirmar, el slot se cierra (misma semántica que el sistema legado).
    cerrarSlot(slot.id)
    await Promise.all([cargarHistorial(), cargarBase()])
  } catch (e) {
    error.value = e.message
  } finally {
    slot.guardando = false
  }
}

// ---------------------------------------------------------------------------
// Historial de vales
// ---------------------------------------------------------------------------

const columnasHistorial = [
  { key: 'numero_vale', label: 'N° Vale' },
  { key: 'tipo_vale', label: 'Tipo' },
  { key: 'obraNombre', label: 'Obra' },
  { key: 'patente', label: 'Patente' },
  { key: 'pesoNetoLabel', label: 'Neto' },
  { key: 'fechaLabel', label: 'Fecha / hora' },
  { key: 'acciones', label: '' },
]

const TAMANO_PAGINA_HISTORIAL = 50

const historial = ref([])
const totalHistorial = ref(0)
const paginaHistorial = ref(1)
const cargandoHistorial = ref(false)
const filtros = reactive({ tipoVale: '', obraId: '', patente: '', desde: '', hasta: '' })

const filasHistorial = computed(() =>
  historial.value.map((v) => ({
    ...v,
    obraNombre: v.obra_id ? obrasPorId.value[v.obra_id]?.nombre ?? `Obra #${v.obra_id}` : '—',
    pesoNetoLabel: `${v.peso_neto} ${v.unidad}`,
    fechaLabel: new Date(v.fecha_pesada).toLocaleString('es-AR'),
  }))
)

async function cargarHistorial() {
  cargandoHistorial.value = true
  error.value = null
  try {
    const resultado = await fetchHistorialVales(
      {
        tipoVale: filtros.tipoVale || undefined,
        obraId: filtros.obraId || undefined,
        patente: filtros.patente || undefined,
        desde: filtros.desde || undefined,
        hasta: filtros.hasta || undefined,
      },
      { pagina: paginaHistorial.value, tamanoPagina: TAMANO_PAGINA_HISTORIAL }
    )
    historial.value = resultado.filas
    totalHistorial.value = resultado.total
  } catch (e) {
    error.value = e.message
  } finally {
    cargandoHistorial.value = false
  }
}

/** Cualquier cambio de filtro vuelve a la página 1 (si no, se puede quedar en una página que ya no existe). */
function aplicarFiltrosHistorial() {
  paginaHistorial.value = 1
  cargarHistorial()
}

function limpiarFiltros() {
  filtros.tipoVale = ''
  filtros.obraId = ''
  filtros.patente = ''
  filtros.desde = ''
  filtros.hasta = ''
  aplicarFiltrosHistorial()
}

function cambiarPaginaHistorial(pagina) {
  paginaHistorial.value = pagina
  cargarHistorial()
}

// ---------------------------------------------------------------------------
// Impresión (vale individual / remito con acumulado dinámico)
// ---------------------------------------------------------------------------
// REGLA: no existe ninguna acción de impresión para "Vale de Salida de
// Áridos" (tipo_vale = 'ingreso_arido') — solo se ofrece imprimir en filas de
// asfalto, ver template.

const modalImpresionAbierto = ref(false)
const modoImpresion = ref('vale')
const valeParaImprimir = ref(null)
const obraNombreParaImprimir = ref('')
const acumuladoParaImprimir = ref(null)

function abrirImpresionVale(vale) {
  valeParaImprimir.value = vale
  obraNombreParaImprimir.value = vale.obra_id ? obrasPorId.value[vale.obra_id]?.nombre ?? '' : ''
  modoImpresion.value = 'vale'
  acumuladoParaImprimir.value = null
  modalImpresionAbierto.value = true
}

async function abrirImpresionRemito(vale) {
  valeParaImprimir.value = vale
  obraNombreParaImprimir.value = vale.obra_id ? obrasPorId.value[vale.obra_id]?.nombre ?? '' : ''
  modoImpresion.value = 'remito'
  modalImpresionAbierto.value = true
  error.value = null
  try {
    acumuladoParaImprimir.value = await obtenerAcumuladoObraHastaFecha(vale.obra_id, vale.fecha_pesada)
  } catch (e) {
    error.value = e.message
  }
}

function imprimir() {
  window.print()
}

// ---------------------------------------------------------------------------

cargarBase()
cargarHistorial()
crearSlot('asfalto')
</script>

<template>
  <div>
    <VSection title="Báscula">
      <div v-if="error" class="mb-3 rounded border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
        {{ error }}
      </div>

      <!-- Pestañas de pesaje en paralelo -->
      <div class="mb-3 flex flex-wrap items-center gap-1 border-b border-gray-200 pb-1">
        <button
          v-for="slot in slots"
          :key="slot.id"
          type="button"
          class="flex items-center gap-1 px-3 py-2 text-sm"
          :class="
            slot.id === slotActivoId
              ? 'border-b-2 border-gray-900 font-medium text-gray-900'
              : 'text-gray-500 hover:text-gray-700'
          "
          @click="slotActivoId = slot.id"
        >
          {{ ETIQUETA_TIPO[slot.tipo] }}
          <span class="text-gray-300 hover:text-red-500" @click.stop="cerrarSlot(slot.id)">✕</span>
        </button>

        <div class="ml-auto flex gap-1">
          <button type="button" class="rounded px-2 py-1 text-xs text-blue-600 hover:bg-blue-50" @click="crearSlot('asfalto')">
            + Salida asfalto
          </button>
          <button
            type="button"
            class="rounded px-2 py-1 text-xs text-blue-600 hover:bg-blue-50"
            @click="crearSlot('ingreso_arido')"
          >
            + Ingreso árido
          </button>
        </div>
      </div>

      <!-- Formulario del slot activo -->
      <VCard v-if="slotActivo" class="mb-6">
        <div class="grid grid-cols-2 gap-3 md:grid-cols-3">
          <template v-if="slotActivo.tipo === 'ingreso_arido'">
            <label class="text-sm">
              Material
              <input v-model="slotActivo.form.material" type="text" class="mt-1 w-full rounded border-gray-300 text-sm" />
            </label>
            <label class="text-sm">
              Proveedor
              <input v-model="slotActivo.form.proveedor" type="text" class="mt-1 w-full rounded border-gray-300 text-sm" />
            </label>
            <label class="text-sm">
              N° de remito
              <input v-model="slotActivo.form.numero_remito" type="text" class="mt-1 w-full rounded border-gray-300 text-sm" />
            </label>
            <label class="text-sm md:col-span-3">
              Cantidad según remito (tn)
              <input
                v-model.number="slotActivo.form.cantidad_remito"
                type="number"
                step="0.01"
                class="mt-1 w-full rounded border-gray-300 text-sm md:w-1/3"
              />
              <span class="ml-2 text-xs text-gray-400">
                El stock se actualiza con esta cantidad, no con el peso neto pesado (memory/business-rules.md).
              </span>
            </label>
          </template>

          <label v-if="slotActivo.tipo === 'asfalto'" class="text-sm md:col-span-3">
            Pedido (asfalto, confirmado, con saldo)
            <select v-model="slotActivo.form.pedido_id" class="mt-1 w-full rounded border-gray-300 text-sm">
              <option value="" disabled>Elegir pedido…</option>
              <option v-for="p in pedidosConSaldo" :key="p.id" :value="p.id">
                {{ obrasPorId[p.obra_id]?.nombre ?? `Obra #${p.obra_id}` }} — saldo
                {{ (Number(p.cantidad_solicitada) - Number(p.cantidad_despachada || 0)).toFixed(1) }} tn
              </option>
            </select>
            <p v-if="!pedidosConSaldo.length" class="mt-1 text-xs text-gray-400">
              No hay pedidos de asfalto confirmados con saldo pendiente.
            </p>
          </label>

          <label class="text-sm">
            Patente
            <input
              v-model="slotActivo.form.patente"
              list="patentes-conocidas"
              class="mt-1 w-full rounded border-gray-300 text-sm"
              @change="alCambiarPatente(slotActivo)"
            />
          </label>
          <label class="text-sm">
            Chofer
            <input v-model="slotActivo.form.chofer" type="text" class="mt-1 w-full rounded border-gray-300 text-sm" />
          </label>
          <div />

          <label class="text-sm">
            Peso bruto (tn)
            <input v-model.number="slotActivo.form.peso_bruto" type="number" step="0.01" class="mt-1 w-full rounded border-gray-300 text-sm" />
          </label>
          <label class="text-sm">
            Tara (tn)
            <input v-model.number="slotActivo.form.tara" type="number" step="0.01" class="mt-1 w-full rounded border-gray-300 text-sm" />
          </label>
          <label class="text-sm">
            Neto (calculado)
            <input :value="netoSlot(slotActivo)" type="text" disabled class="mt-1 w-full rounded border-gray-200 bg-gray-50 text-sm text-gray-500" />
          </label>
        </div>

        <label class="mt-3 block text-sm">
          Observaciones
          <textarea v-model="slotActivo.form.observaciones" rows="2" class="mt-1 w-full rounded border-gray-300 text-sm"></textarea>
        </label>

        <datalist id="patentes-conocidas">
          <option v-for="p in patentes" :key="p.id" :value="p.patente" />
        </datalist>

        <div class="mt-4 flex justify-end">
          <button
            type="button"
            :disabled="slotActivo.guardando"
            class="rounded bg-gray-900 px-3 py-1.5 text-sm text-white hover:bg-gray-700 disabled:opacity-50"
            @click="guardarPesada(slotActivo)"
          >
            {{ slotActivo.guardando ? 'Guardando…' : 'Confirmar pesada' }}
          </button>
        </div>
      </VCard>
      <p v-else class="mb-6 text-sm text-gray-400">No hay ninguna pestaña de pesaje abierta. Creá una arriba.</p>

      <!-- Filtros de historial -->
      <VCard class="mb-4">
        <div class="grid grid-cols-2 gap-3 md:grid-cols-5">
          <label class="text-sm">
            Tipo
            <select v-model="filtros.tipoVale" class="mt-1 w-full rounded border-gray-300 text-sm">
              <option value="">Todos</option>
              <option value="asfalto">Asfalto</option>
              <option value="hormigon">Hormigón</option>
              <option value="ingreso_arido">Ingreso árido</option>
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
            Patente
            <input v-model="filtros.patente" type="text" class="mt-1 w-full rounded border-gray-300 text-sm" />
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
          <button type="button" class="rounded bg-gray-900 px-3 py-1.5 text-sm text-white hover:bg-gray-700" @click="aplicarFiltrosHistorial">
            Filtrar
          </button>
          <button type="button" class="rounded px-3 py-1.5 text-sm text-gray-600 hover:bg-gray-100" @click="limpiarFiltros">
            Limpiar
          </button>
        </div>
      </VCard>

      <!-- Historial -->
      <VCard>
        <p v-if="cargandoHistorial" class="text-sm text-gray-500">Cargando…</p>
        <VTable
          v-else
          :columns="columnasHistorial"
          :rows="filasHistorial"
          :page="paginaHistorial"
          :page-size="TAMANO_PAGINA_HISTORIAL"
          :total="totalHistorial"
          @update:page="cambiarPaginaHistorial"
        >
          <template #cell-tipo_vale="{ row }">
            <VBadge :variant="VARIANTE_TIPO[row.tipo_vale]">{{ ETIQUETA_TIPO[row.tipo_vale] }}</VBadge>
          </template>
          <template #cell-acciones="{ row }">
            <div v-if="row.tipo_vale === 'asfalto'" class="flex gap-3 text-sm">
              <button type="button" class="text-blue-600 hover:underline" @click="abrirImpresionVale(row)">
                Imprimir vale
              </button>
              <button type="button" class="text-blue-600 hover:underline" @click="abrirImpresionRemito(row)">
                Imprimir remito
              </button>
            </div>
            <span v-else class="text-xs text-gray-300">—</span>
          </template>
        </VTable>
        <p v-if="!cargandoHistorial && !filasHistorial.length" class="py-4 text-center text-sm text-gray-400">
          No hay vales que coincidan con el filtro.
        </p>
      </VCard>
    </VSection>

    <!-- Modal de impresión -->
    <VModal
      :open="modalImpresionAbierto"
      :title="modoImpresion === 'remito' ? 'Remito de entrega' : 'Vale de pesaje'"
      @update:open="modalImpresionAbierto = $event"
    >
      <div class="imprimible">
        <ValeImprimible
          v-if="valeParaImprimir"
          :vale="valeParaImprimir"
          :obra-nombre="obraNombreParaImprimir"
          :modo="modoImpresion"
          :acumulado-tn="acumuladoParaImprimir"
        />
      </div>
      <div class="mt-4 flex justify-end gap-2">
        <button type="button" class="rounded px-3 py-1.5 text-sm text-gray-600 hover:bg-gray-100" @click="modalImpresionAbierto = false">
          Cerrar
        </button>
        <button type="button" class="rounded bg-gray-900 px-3 py-1.5 text-sm text-white hover:bg-gray-700" @click="imprimir">
          Imprimir
        </button>
      </div>
    </VModal>
  </div>
</template>
