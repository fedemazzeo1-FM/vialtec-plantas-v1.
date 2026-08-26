<script setup>
// Plan Semanal: matriz lunes-domingo de pedidos + KPIs de acumulado semanal en
// dos métricas paralelas (asfalto en tn, hormigón en m³). Toda la persistencia
// pasa por pedidos.service.js — este componente no llama a Supabase
// directamente (memory/conventions.md).

import { computed, ref } from 'vue'
import VCard from '@/components/shared/VCard.vue'
import VKpiCard from '@/components/shared/VKpiCard.vue'
import VBadge from '@/components/shared/VBadge.vue'
import VSection from '@/components/shared/VSection.vue'
import {
  obtenerRangoSemana,
  fetchPedidosSemana,
  fetchTotalesSemana,
  confirmarPedido,
} from '@/modules/pedidos/services/pedidos.service'
import { fetchObras } from '@/services/flota.service'
import { fetchFormulas } from '@/modules/maestros/services/formulas.service'

const NOMBRES_DIA = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo']
const VARIANTE_ESTADO = {
  solicitado: 'default',
  confirmado: 'info',
  despachado: 'success',
  cancelado: 'danger',
}

const fechaRef = ref(new Date())
const pedidos = ref([])
const totales = ref({ rango: null, porObra: [], total: { asfaltoTn: 0, hormigonM3: 0 } })
const obras = ref([])
const formulas = ref([])
const cargando = ref(false)
const error = ref(null)

const obrasPorId = computed(() => Object.fromEntries(obras.value.map((o) => [o.id, o])))
const formulasPorId = computed(() => Object.fromEntries(formulas.value.map((f) => [f.id, f])))

const diasSemana = computed(() => {
  const { lunes } = obtenerRangoSemana(fechaRef.value)
  return Array.from({ length: 7 }, (_, i) => {
    const fecha = new Date(lunes)
    fecha.setDate(lunes.getDate() + i)
    const iso = fecha.toISOString().slice(0, 10)
    return {
      etiqueta: NOMBRES_DIA[i],
      iso,
      pedidos: pedidos.value.filter((p) => p.fecha_programada === iso),
    }
  })
})

const rangoLabel = computed(() =>
  diasSemana.value.length ? `${diasSemana.value[0].iso} — ${diasSemana.value[6].iso}` : ''
)

function nombreObra(obraId) {
  return obrasPorId.value[obraId]?.nombre ?? `Obra #${obraId}`
}

async function cargarSemana() {
  cargando.value = true
  error.value = null
  try {
    const [listaPedidos, totalesSemana, listaObras, listaFormulas] = await Promise.all([
      fetchPedidosSemana(fechaRef.value),
      fetchTotalesSemana(fechaRef.value),
      fetchObras(),
      fetchFormulas({ soloActivas: true }),
    ])
    pedidos.value = listaPedidos
    totales.value = totalesSemana
    obras.value = listaObras
    formulas.value = listaFormulas
  } catch (e) {
    error.value = e.message
  } finally {
    cargando.value = false
  }
}

function semanaAnterior() {
  const f = new Date(fechaRef.value)
  f.setDate(f.getDate() - 7)
  fechaRef.value = f
  cargarSemana()
}

function semanaSiguiente() {
  const f = new Date(fechaRef.value)
  f.setDate(f.getDate() + 7)
  fechaRef.value = f
  cargarSemana()
}

async function confirmar(pedido) {
  error.value = null
  try {
    await confirmarPedido(pedido.id)
    await cargarSemana()
  } catch (e) {
    error.value = e.message
  }
}

cargarSemana()
</script>

<template>
  <div>
    <VSection title="Plan semanal">
      <div class="mb-4 flex items-center justify-between">
        <button type="button" class="rounded px-3 py-1.5 text-sm text-gray-600 hover:bg-gray-100" @click="semanaAnterior">
          ‹ Semana anterior
        </button>
        <p class="text-sm font-medium text-gray-700">{{ rangoLabel }}</p>
        <button type="button" class="rounded px-3 py-1.5 text-sm text-gray-600 hover:bg-gray-100" @click="semanaSiguiente">
          Semana siguiente ›
        </button>
      </div>

      <div v-if="error" class="mb-3 rounded border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
        {{ error }}
      </div>

      <!-- Totalizador general: siempre las dos métricas en paralelo -->
      <VCard class="mb-4">
        <p class="mb-2 text-sm font-medium text-gray-500">Total semana — todas las obras</p>
        <div class="grid grid-cols-2 gap-3">
          <VKpiCard label="Asfalto" :value="totales.total.asfaltoTn.toFixed(1)" unidad="tn" />
          <VKpiCard label="Hormigón" :value="totales.total.hormigonM3.toFixed(1)" unidad="m³" />
        </div>
      </VCard>

      <!-- Totales por obra: mismas dos métricas en paralelo -->
      <div v-if="totales.porObra.length" class="mb-6 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <VCard v-for="t in totales.porObra" :key="t.obraId">
          <p class="mb-2 text-sm font-medium text-gray-500">{{ nombreObra(t.obraId) }}</p>
          <div class="grid grid-cols-2 gap-3">
            <VKpiCard label="Asfalto" :value="t.asfaltoTn.toFixed(1)" unidad="tn" />
            <VKpiCard label="Hormigón" :value="t.hormigonM3.toFixed(1)" unidad="m³" />
          </div>
        </VCard>
      </div>

      <p v-if="cargando" class="text-sm text-gray-500">Cargando…</p>

      <!-- Matriz lunes a domingo -->
      <div v-else class="grid grid-cols-1 gap-3 md:grid-cols-7">
        <VCard v-for="dia in diasSemana" :key="dia.iso">
          <p class="mb-2 text-sm font-semibold">
            {{ dia.etiqueta }} <span class="font-normal text-gray-400">{{ dia.iso }}</span>
          </p>
          <p v-if="!dia.pedidos.length" class="text-xs text-gray-400">Sin pedidos</p>
          <div v-for="p in dia.pedidos" :key="p.id" class="mb-2 rounded border border-gray-100 p-2 text-xs">
            <p class="font-medium">{{ nombreObra(p.obra_id) }}</p>
            <p class="text-gray-500">
              {{ formulasPorId[p.formula_id]?.nombre ?? '—' }} ·
              {{ p.cantidad_solicitada }} {{ p.tipo === 'hormigon' ? 'm³' : 'tn' }}
            </p>
            <div class="mt-1 flex items-center justify-between">
              <VBadge :variant="VARIANTE_ESTADO[p.estado]">{{ p.estado }}</VBadge>
              <button
                v-if="p.estado === 'solicitado'"
                type="button"
                class="text-blue-600 hover:underline"
                @click="confirmar(p)"
              >
                Confirmar
              </button>
            </div>
          </div>
        </VCard>
      </div>
    </VSection>
  </div>
</template>
