<script setup>
// Vista de Stock e Inventarios: cards de insumos con semáforo, ingreso/
// salida manual, relevamiento mensual (ajuste auditable) e historial de
// movimientos paginado. Toda la lógica vive en useStock() (memory/
// conventions.md: esta vista es template puro).
//
// Analítica de proveedores queda en el Dashboard (decisión Federico
// 2026-08-31) — acá solo hay un link de acceso rápido, no se duplica la vista.

import VCard from '@/components/shared/VCard.vue'
import VTable from '@/components/shared/VTable.vue'
import VModal from '@/components/shared/VModal.vue'
import VSection from '@/components/shared/VSection.vue'
import VButton from '@/components/shared/VButton.vue'
import VSemaforo from '@/components/shared/VSemaforo.vue'
import { useStock } from '@/modules/stock/composables/useStock'

const ESTADO_A_COLOR = { rojo: 'rojo', amarillo: 'amarillo', verde: 'verde' }
const ESTADO_LABEL = { rojo: 'Insuficiente', amarillo: 'Ajustado', verde: 'OK' }

const TIPOS_MOVIMIENTO = [
  { value: '', label: 'Todos' },
  { value: 'ingreso_proveedor', label: 'Ingreso proveedor' },
  { value: 'egreso_despacho', label: 'Egreso por despacho' },
  { value: 'egreso_arido', label: 'Egreso árido' },
  { value: 'ingreso_manual', label: 'Ingreso manual' },
  { value: 'egreso_manual', label: 'Egreso manual' },
  { value: 'ajuste', label: 'Ajuste (relevamiento)' },
  { value: 'recalculo_despacho', label: 'Recálculo de despacho' },
]

const columnasHistorial = [
  { key: 'fecha_movimiento', label: 'Fecha', format: (v) => new Date(v).toLocaleString('es-AR') },
  { key: 'tipo', label: 'Tipo' },
  { key: 'materialNombre', label: 'Material' },
  { key: 'cantidad_kg', label: 'Cantidad' },
  { key: 'origen', label: 'Proveedor / Motivo' },
  { key: 'numero_remito', label: 'Remito' },
  { key: 'responsableNombre', label: 'Responsable' },
]

const {
  error,
  unidadVista,
  formatearCantidad,
  materiales,
  cargandoStock,
  modalMovimientoAbierto,
  formMovimiento,
  guardandoMovimiento,
  abrirMovimiento,
  guardarMovimiento,
  modalRelevamientoAbierto,
  conteosRelevamiento,
  motivoRelevamiento,
  guardandoRelevamiento,
  abrirRelevamiento,
  guardarRelevamiento,
  movimientos,
  totalMovimientos,
  paginaHistorial,
  cargandoHistorial,
  filtrosHistorial,
  TAMANO_PAGINA_HISTORIAL,
  aplicarFiltrosHistorial,
  limpiarFiltrosHistorial,
  cambiarPaginaHistorial,
  etiquetaTipo,
  catalogoMateriales,
  iniciar,
} = useStock()

iniciar()

function anchoBarra(material) {
  if (!material.stock_maximo_kg) return null
  return Math.min(100, Math.max(0, (material.cantidadKg / material.stock_maximo_kg) * 100))
}
</script>

<template>
  <div>
    <VSection title="Stock e Inventarios">
      <div v-if="error" class="mb-3 rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
        {{ error }}
      </div>

      <div class="mb-4 flex flex-wrap items-center justify-between gap-2">
        <div class="flex items-center gap-2">
          <span class="text-sm text-text-mid">Unidad:</span>
          <div class="flex rounded-lg border border-border p-0.5">
            <button
              type="button"
              class="rounded-md px-3 py-1 text-xs font-semibold"
              :class="unidadVista === 'tn' ? 'bg-vialtec text-white' : 'text-text-mid'"
              @click="unidadVista = 'tn'"
            >
              Toneladas
            </button>
            <button
              type="button"
              class="rounded-md px-3 py-1 text-xs font-semibold"
              :class="unidadVista === 'kg' ? 'bg-vialtec text-white' : 'text-text-mid'"
              @click="unidadVista = 'kg'"
            >
              Kilogramos
            </button>
          </div>
          <router-link to="/dashboard" class="text-sm text-vialtec hover:underline">
            Ver analítica de proveedores en el Dashboard →
          </router-link>
        </div>
        <div class="flex flex-wrap gap-2">
          <VButton size="sm" variant="success" @click="abrirMovimiento('ingreso_manual')">+ Ingreso manual</VButton>
          <VButton size="sm" variant="secondary" @click="abrirMovimiento('egreso_manual')">+ Salida manual</VButton>
          <VButton size="sm" variant="secondary" @click="abrirRelevamiento">▤ Relevamiento mensual</VButton>
        </div>
      </div>

      <p v-if="cargandoStock" class="text-sm text-text-soft">Cargando…</p>
      <div v-else-if="!materiales.length" class="rounded-lg border border-border bg-white p-6 text-center text-sm text-text-soft">
        No hay materiales que controlen stock todavía.
        <router-link to="/maestros" class="text-vialtec hover:underline">Cargalos en Maestros → Materiales</router-link>.
      </div>
      <div v-else class="mb-6 grid grid-cols-2 gap-3 md:grid-cols-4">
        <VCard v-for="material in materiales" :key="material.id">
          <div class="flex items-center justify-between">
            <p class="truncate text-sm font-semibold text-text">{{ material.nombre }}</p>
            <VSemaforo :estado="ESTADO_A_COLOR[material.estado]" />
          </div>
          <p class="mt-2 text-2xl font-extrabold text-text">
            {{ formatearCantidad(material.cantidadKg) }}
            <span class="text-sm font-normal text-text-soft">{{ unidadVista }}</span>
          </p>
          <p class="text-xs text-text-soft">{{ ESTADO_LABEL[material.estado] }}</p>
          <div v-if="material.stock_maximo_kg" class="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-gray-100">
            <div
              class="h-full rounded-full"
              :class="{ 'bg-danger': material.estado === 'rojo', 'bg-warning': material.estado === 'amarillo', 'bg-success': material.estado === 'verde' }"
              :style="{ width: anchoBarra(material) + '%' }"
            />
          </div>
          <p v-if="material.stock_minimo_kg || material.stock_maximo_kg" class="mt-1 text-[11px] text-text-soft">
            min {{ ((material.stock_minimo_kg || 0) / 1000).toFixed(1) }}t · máx {{ material.stock_maximo_kg ? (material.stock_maximo_kg / 1000).toFixed(1) + 't' : '—' }}
          </p>
        </VCard>
      </div>

      <VCard class="mb-3">
        <p class="mb-2 text-sm font-bold text-text">Historial de movimientos</p>
        <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
          <label class="text-sm text-text-mid">
            Material
            <select v-model="filtrosHistorial.materialId" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none">
              <option value="">Todos</option>
              <option v-for="m in catalogoMateriales" :key="m.id" :value="m.id">{{ m.nombre }}</option>
            </select>
          </label>
          <label class="text-sm text-text-mid">
            Tipo
            <select v-model="filtrosHistorial.tipo" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none">
              <option v-for="t in TIPOS_MOVIMIENTO" :key="t.value" :value="t.value">{{ t.label }}</option>
            </select>
          </label>
          <label class="text-sm text-text-mid">
            Desde
            <input v-model="filtrosHistorial.desde" type="date" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none" />
          </label>
          <label class="text-sm text-text-mid">
            Hasta
            <input v-model="filtrosHistorial.hasta" type="date" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none" />
          </label>
        </div>
        <div class="mt-3 flex gap-2">
          <VButton size="sm" @click="aplicarFiltrosHistorial">Filtrar</VButton>
          <VButton variant="ghost" size="sm" @click="limpiarFiltrosHistorial">Limpiar</VButton>
        </div>
      </VCard>

      <VCard>
        <p v-if="cargandoHistorial" class="text-sm text-text-soft">Cargando…</p>
        <VTable
          v-else
          :columns="columnasHistorial"
          :rows="movimientos"
          :page="paginaHistorial"
          :page-size="TAMANO_PAGINA_HISTORIAL"
          :total="totalMovimientos"
          @update:page="cambiarPaginaHistorial"
        >
          <template #cell-tipo="{ row }">
            {{ etiquetaTipo(row.tipo) }}
          </template>
          <template #cell-cantidad_kg="{ row }">
            <span :class="row.cantidad_kg > 0 ? 'text-success' : 'text-danger'">
              {{ row.cantidad_kg > 0 ? '+' : '' }}{{ (row.cantidad_kg / 1000).toFixed(3) }} t
            </span>
          </template>
        </VTable>
        <p v-if="!cargandoHistorial && !movimientos.length" class="py-4 text-center text-sm text-text-soft">
          No hay movimientos que coincidan con el filtro.
        </p>
      </VCard>
    </VSection>

    <!-- Ingreso / salida manual -->
    <VModal
      :open="modalMovimientoAbierto"
      :title="formMovimiento.tipo === 'ingreso_manual' ? 'Ingreso manual' : 'Salida manual'"
      @update:open="modalMovimientoAbierto = $event"
    >
      <form class="space-y-3" @submit.prevent="guardarMovimiento">
        <label class="block text-sm text-text-mid">
          Material
          <select v-model="formMovimiento.material_id" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none">
            <option value="" disabled>Elegir material…</option>
            <option v-for="m in catalogoMateriales" :key="m.id" :value="m.id">{{ m.nombre }}</option>
          </select>
        </label>
        <div class="grid grid-cols-[2fr_1fr] gap-2">
          <label class="block text-sm text-text-mid">
            Cantidad
            <input
              v-model.number="formMovimiento.cantidad"
              type="number"
              step="0.001"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            />
          </label>
          <label class="block text-sm text-text-mid">
            Unidad
            <select v-model="formMovimiento.unidad" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none">
              <option value="tn">tn</option>
              <option value="kg">kg</option>
            </select>
          </label>
        </div>
        <label class="block text-sm text-text-mid">
          {{ formMovimiento.tipo === 'ingreso_manual' ? 'Proveedor' : 'Motivo' }}
          <input v-model="formMovimiento.origen" type="text" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none" />
        </label>
        <label v-if="formMovimiento.tipo === 'ingreso_manual'" class="block text-sm text-text-mid">
          N° de remito (opcional)
          <input v-model="formMovimiento.numero_remito" type="text" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none" />
        </label>
        <label class="block text-sm text-text-mid">
          Observaciones (opcional)
          <textarea v-model="formMovimiento.observaciones" rows="2" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"></textarea>
        </label>
        <div class="flex justify-end gap-2 pt-2">
          <VButton type="button" variant="secondary" @click="modalMovimientoAbierto = false">Cancelar</VButton>
          <VButton type="submit" :disabled="guardandoMovimiento">{{ guardandoMovimiento ? 'Guardando…' : 'Guardar' }}</VButton>
        </div>
      </form>
    </VModal>

    <!-- Relevamiento mensual: NO pisa el stock directo, calcula diferencia -->
    <VModal :open="modalRelevamientoAbierto" title="Relevamiento mensual" @update:open="modalRelevamientoAbierto = $event">
      <div class="space-y-3">
        <p class="text-sm text-text-mid">
          Cargá el conteo real de cada material (en tn). Se guarda como un movimiento de <strong>ajuste</strong> por la
          diferencia contra el stock actual — no se pisa nada directo.
        </p>
        <label class="block text-sm text-text-mid">
          Motivo
          <input v-model="motivoRelevamiento" type="text" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none" />
        </label>
        <div class="max-h-80 space-y-2 overflow-y-auto">
          <div v-for="conteo in conteosRelevamiento" :key="conteo.materialId" class="flex items-center justify-between gap-3">
            <span class="text-sm text-text-mid">{{ conteo.nombre }}</span>
            <input
              v-model.number="conteo.cantidadTn"
              type="number"
              step="0.001"
              class="w-32 rounded-lg border border-border px-2 py-1.5 text-right text-sm focus:border-vialtec focus:outline-none"
            />
          </div>
        </div>
        <div class="flex justify-end gap-2 pt-2">
          <VButton type="button" variant="secondary" @click="modalRelevamientoAbierto = false">Cancelar</VButton>
          <VButton type="button" :disabled="guardandoRelevamiento" @click="guardarRelevamiento">
            {{ guardandoRelevamiento ? 'Guardando…' : 'Guardar relevamiento' }}
          </VButton>
        </div>
      </div>
    </VModal>
  </div>
</template>
