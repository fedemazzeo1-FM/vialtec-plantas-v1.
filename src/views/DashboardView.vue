<script setup>
// Dashboard gerencial: KPIs del mes, analítica de proveedores (con
// comparativa de período) y detalle de despachos por camión (con remito
// siempre presente, asfalto y hormigón). Toda la persistencia pasa por
// analytics.service.js — este componente no llama a Supabase directamente
// (memory/conventions.md).

import { computed, reactive, ref } from 'vue'
import VCard from '@/components/shared/VCard.vue'
import VKpiCard from '@/components/shared/VKpiCard.vue'
import VTable from '@/components/shared/VTable.vue'
import VBadge from '@/components/shared/VBadge.vue'
import VSection from '@/components/shared/VSection.vue'
import VButton from '@/components/shared/VButton.vue'
import {
  fetchResumenGeneral,
  fetchAnaliticaProveedores,
  fetchDetalleDespachosCamion,
} from '@/modules/analytics/services/analytics.service'
import { fetchObras } from '@/services/flota.service'
import { fetchFormulas } from '@/modules/maestros/services/formulas.service'

const error = ref(null)

const obras = ref([])
const formulas = ref([])
const obrasPorId = computed(() => Object.fromEntries(obras.value.map((o) => [o.id, o])))
const formulasPorId = computed(() => Object.fromEntries(formulas.value.map((f) => [f.id, f])))

async function cargarBase() {
  try {
    const [listaObras, listaFormulas] = await Promise.all([fetchObras(), fetchFormulas({ soloActivas: true })])
    obras.value = listaObras
    formulas.value = listaFormulas
  } catch (e) {
    error.value = e.message
  }
}

// ---------------------------------------------------------------------------
// KPIs del mes
// ---------------------------------------------------------------------------

const resumen = ref({ rango: null, asfaltoTn: 0, hormigonM3: 0, despachosDelMes: 0, ingresosInsumosTn: 0 })
const cargandoResumen = ref(false)

async function cargarResumen() {
  cargandoResumen.value = true
  error.value = null
  try {
    resumen.value = await fetchResumenGeneral()
  } catch (e) {
    error.value = e.message
  } finally {
    cargandoResumen.value = false
  }
}

// ---------------------------------------------------------------------------
// Analítica de proveedores
// ---------------------------------------------------------------------------

const filtrosProveedores = reactive({ desde: '', hasta: '' })
const proveedores = ref([])
const cargandoProveedores = ref(false)

const columnasProveedores = [
  { key: 'proveedor', label: 'Proveedor' },
  { key: 'cantidadActualTn', label: 'Período actual (tn)' },
  { key: 'cantidadAnteriorTn', label: 'Período anterior (tn)' },
  { key: 'variacionPct', label: 'Variación' },
]

async function cargarProveedores() {
  cargandoProveedores.value = true
  error.value = null
  try {
    proveedores.value = await fetchAnaliticaProveedores({
      desde: filtrosProveedores.desde || undefined,
      hasta: filtrosProveedores.hasta || undefined,
    })
  } catch (e) {
    error.value = e.message
  } finally {
    cargandoProveedores.value = false
  }
}

// ---------------------------------------------------------------------------
// Despachos por camión
// ---------------------------------------------------------------------------

const filtrosDespachos = reactive({ material: '', obraId: '', desde: '', hasta: '' })
const despachos = ref([])
const cargandoDespachos = ref(false)

const columnasDespachos = [
  { key: 'fechaLabel', label: 'Fecha' },
  { key: 'obraNombre', label: 'Obra' },
  { key: 'formulaNombre', label: 'Fórmula' },
  { key: 'patente', label: 'Patente' },
  { key: 'numero_remito', label: 'N° Remito' },
  { key: 'volumenLabel', label: 'Volumen' },
]

const filasDespachos = computed(() =>
  despachos.value.map((d) => ({
    ...d,
    // Defensivo (2026-09-01): fecha/volumen deberían venir siempre completos
    // desde plantas_v_despachos_camion, pero una fila con dato faltante no
    // debe mostrar "Invalid Date"/"NaN" sin explicación en la tabla.
    fechaLabel: d.fecha ? new Date(d.fecha).toLocaleString('es-AR') : '—',
    obraNombre: d.obra_id ? obrasPorId.value[d.obra_id]?.nombre ?? `Obra #${d.obra_id}` : '—',
    formulaNombre: d.formulaId ? formulasPorId.value[d.formulaId]?.nombre ?? '—' : '—',
    volumenLabel: d.volumen != null ? `${Number(d.volumen).toFixed(2)} ${d.unidad_volumen ?? ''}`.trim() : '—',
  }))
)

async function cargarDespachos() {
  cargandoDespachos.value = true
  error.value = null
  try {
    despachos.value = await fetchDetalleDespachosCamion({
      material: filtrosDespachos.material || undefined,
      obraId: filtrosDespachos.obraId || undefined,
      desde: filtrosDespachos.desde || undefined,
      hasta: filtrosDespachos.hasta || undefined,
    })
  } catch (e) {
    error.value = e.message
  } finally {
    cargandoDespachos.value = false
  }
}

function limpiarFiltrosDespachos() {
  filtrosDespachos.material = ''
  filtrosDespachos.obraId = ''
  filtrosDespachos.desde = ''
  filtrosDespachos.hasta = ''
  cargarDespachos()
}

cargarBase()
cargarResumen()
cargarProveedores()
cargarDespachos()
</script>

<template>
  <div>
    <VSection title="Home">
      <div v-if="error" class="mb-3 rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
        {{ error }}
      </div>

      <!-- KPIs del mes -->
      <p v-if="cargandoResumen" class="mb-4 text-sm text-text-soft">Cargando resumen…</p>
      <div v-else class="mb-6 grid grid-cols-2 gap-3 md:grid-cols-4">
        <VKpiCard label="Asfalto (mes)" :value="resumen.asfaltoTn.toFixed(1)" unidad="tn" />
        <VKpiCard label="Hormigón (mes)" :value="resumen.hormigonM3.toFixed(1)" unidad="m³" />
        <VKpiCard label="Despachos del mes" :value="resumen.despachosDelMes" />
        <VKpiCard label="Ingresos de insumos (mes)" :value="resumen.ingresosInsumosTn.toFixed(1)" unidad="tn" />
      </div>
    </VSection>

    <!-- Analítica de proveedores -->
    <VSection title="Analítica de proveedores">
      <VCard class="mb-4">
        <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
          <label class="text-sm text-text-mid">
            Desde
            <input
              v-model="filtrosProveedores.desde"
              type="date"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            />
          </label>
          <label class="text-sm text-text-mid">
            Hasta
            <input
              v-model="filtrosProveedores.hasta"
              type="date"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            />
          </label>
        </div>
        <p class="mt-2 text-xs text-text-soft">
          Sin fechas, muestra el mes en curso comparado contra el mismo largo de período inmediatamente anterior.
        </p>
        <VButton size="sm" class="mt-3" @click="cargarProveedores">Filtrar</VButton>
      </VCard>

      <VCard>
        <p v-if="cargandoProveedores" class="text-sm text-text-soft">Cargando…</p>
        <VTable v-else :columns="columnasProveedores" :rows="proveedores">
          <template #cell-cantidadActualTn="{ row }">{{ row.cantidadActualTn.toFixed(2) }} tn</template>
          <template #cell-cantidadAnteriorTn="{ row }">{{ row.cantidadAnteriorTn.toFixed(2) }} tn</template>
          <template #cell-variacionPct="{ row }">
            <VBadge v-if="row.variacionPct == null" variant="default">s/d</VBadge>
            <VBadge v-else :variant="row.variacionPct >= 0 ? 'success' : 'danger'">
              {{ row.variacionPct >= 0 ? '+' : '' }}{{ row.variacionPct.toFixed(1) }}%
            </VBadge>
          </template>
        </VTable>
        <p v-if="!cargandoProveedores && !proveedores.length" class="py-4 text-center text-sm text-text-soft">
          Sin ingresos de proveedores registrados en el rango elegido.
        </p>
      </VCard>
    </VSection>

    <!-- Despachos por camión -->
    <VSection title="Historial detallado de despachos por camión">
      <VCard class="mb-4">
        <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
          <label class="text-sm text-text-mid">
            Material
            <select
              v-model="filtrosDespachos.material"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            >
              <option value="">Todos</option>
              <option value="asfalto">Asfalto</option>
              <option value="hormigon">Hormigón</option>
            </select>
          </label>
          <label class="text-sm text-text-mid">
            Obra
            <select
              v-model="filtrosDespachos.obraId"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            >
              <option value="">Todas</option>
              <option v-for="o in obras" :key="o.id" :value="o.id">{{ o.nombre }}</option>
            </select>
          </label>
          <label class="text-sm text-text-mid">
            Desde
            <input
              v-model="filtrosDespachos.desde"
              type="date"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            />
          </label>
          <label class="text-sm text-text-mid">
            Hasta
            <input
              v-model="filtrosDespachos.hasta"
              type="date"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            />
          </label>
        </div>
        <div class="mt-3 flex gap-2">
          <VButton size="sm" @click="cargarDespachos">Filtrar</VButton>
          <VButton variant="ghost" size="sm" @click="limpiarFiltrosDespachos">Limpiar</VButton>
        </div>
      </VCard>

      <VCard>
        <p v-if="cargandoDespachos" class="text-sm text-text-soft">Cargando…</p>
        <VTable v-else :columns="columnasDespachos" :rows="filasDespachos" />
        <p v-if="!cargandoDespachos && !filasDespachos.length" class="py-4 text-center text-sm text-text-soft">
          No hay despachos que coincidan con el filtro.
        </p>
      </VCard>
    </VSection>
  </div>
</template>
