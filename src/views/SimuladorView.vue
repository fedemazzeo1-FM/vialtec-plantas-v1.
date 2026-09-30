<script setup>
// Simulador de producción: 100% client-side, sin tocar datos reales — mismo
// texto que el legado ("Calculá despachos sin afectar el sistema real").
// Toda la lógica vive en useSimulador() (memory/conventions.md: esta vista
// es template puro). Layout replicado 1:1 del relevamiento en vivo contra
// produccion.vialtec.app (2026-08-31).

import VCard from '@/components/shared/VCard.vue'
import VSection from '@/components/shared/VSection.vue'
import VButton from '@/components/shared/VButton.vue'
import { useSimulador } from '@/modules/simulador/composables/useSimulador'

const {
  error,
  cargandoBase,
  formulas,
  form,
  unidadForm,
  entradas,
  agregarEntrada,
  quitarEntrada,
  limpiarTodo,
  totalAsfaltoTn,
  totalHormigonM3,
  impactoStock,
  iniciar,
} = useSimulador()

iniciar()
</script>

<template>
  <div>
    <VSection>
      <div class="mb-4 flex items-center justify-between">
        <div>
          <h2 class="text-lg font-bold text-text">Simulador de stock</h2>
          <p class="text-sm text-text-soft">Calculá despachos sin afectar el sistema real</p>
        </div>
        <div v-if="entradas.length" class="flex items-center gap-2">
          <span class="rounded-full bg-vialtec/10 px-2.5 py-1 text-xs font-semibold text-vialtec">
            {{ entradas.length }} simulación{{ entradas.length === 1 ? '' : 'es' }}
          </span>
          <VButton variant="danger" size="sm" @click="limpiarTodo">Limpiar todo</VButton>
        </div>
      </div>

      <div v-if="error" class="mb-3 rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
        {{ error }}
      </div>

      <VCard class="mb-4">
        <p class="mb-3 text-xs font-semibold uppercase tracking-wide text-text-soft">Agregar despacho simulado</p>
        <p v-if="cargandoBase" class="text-sm text-text-soft">Cargando…</p>
        <div v-else class="grid grid-cols-1 items-end gap-3 md:grid-cols-[2fr_1fr_1.5fr_auto]">
          <label class="block text-sm text-text-mid">
            Fórmula
            <select v-model="form.formulaId" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none">
              <option value="" disabled>— Seleccioná —</option>
              <option v-for="f in formulas" :key="f.id" :value="f.id">{{ f.nombre }} ({{ f.tipo === 'hormigon' ? 'Hormigón' : 'Asfalto' }})</option>
            </select>
          </label>
          <label class="block text-sm text-text-mid">
            Cantidad ({{ unidadForm }})
            <input
              v-model.number="form.cantidad"
              type="number"
              step="0.01"
              placeholder="0"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            />
          </label>
          <label class="block text-sm text-text-mid">
            Etiqueta (opcional)
            <input
              v-model="form.etiqueta"
              type="text"
              placeholder="ej: Obra Norte"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            />
          </label>
          <VButton @click="agregarEntrada">+ Agregar</VButton>
        </div>
      </VCard>

      <!-- Lista acumulable de despachos simulados -->
      <VCard v-if="entradas.length" class="mb-4">
        <p class="mb-3 text-xs font-semibold uppercase tracking-wide text-text-soft">Despachos simulados</p>
        <ul class="divide-y divide-border">
          <li v-for="(entrada, i) in entradas" :key="entrada.id" class="flex items-center justify-between gap-3 py-2.5">
            <div class="flex items-center gap-2.5 text-sm">
              <span class="rounded-full bg-vialtec/10 px-2 py-0.5 text-xs font-semibold text-vialtec">#{{ i + 1 }}</span>
              <span class="font-semibold text-text">{{ entrada.etiqueta || entrada.formulaNombre }}</span>
              <span class="text-text-soft">{{ entrada.formulaNombre }}</span>
            </div>
            <div class="flex items-center gap-3">
              <span class="text-sm font-bold text-text">{{ entrada.cantidad.toFixed(2) }} {{ entrada.tipo === 'hormigon' ? 'm³' : 'tn' }}</span>
              <button type="button" class="text-text-soft hover:text-danger" @click="quitarEntrada(entrada.id)">✕</button>
            </div>
          </li>
        </ul>
        <div class="mt-3 flex gap-4 border-t border-border pt-3 text-sm font-semibold">
          <p v-if="totalAsfaltoTn > 0" class="text-vialtec">Total asfalto: {{ totalAsfaltoTn.toFixed(2) }} tn</p>
          <p v-if="totalHormigonM3 > 0" class="text-success">Total hormigón: {{ totalHormigonM3.toFixed(2) }} m³</p>
        </div>
      </VCard>

      <!-- Impacto en stock -->
      <VCard v-if="entradas.length">
        <p class="mb-3 text-xs font-semibold uppercase tracking-wide text-text-soft">Impacto en stock</p>
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-border text-sm">
            <thead>
              <tr class="text-left text-xs font-bold uppercase tracking-wide text-text-soft">
                <th class="py-2 pr-4">Insumo</th>
                <th class="py-2 pr-4 text-right">Stock actual</th>
                <th class="py-2 pr-4 text-right">Consumo total</th>
                <th class="py-2 pr-4 text-right">Stock proyectado</th>
                <th class="py-2 text-right">Estado</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-border">
              <tr v-for="fila in impactoStock" :key="fila.insumo">
                <td class="py-2.5 pr-4 font-semibold text-text">{{ fila.insumo }}</td>
                <td class="py-2.5 pr-4 text-right text-text-mid">{{ (fila.stockActualKg / 1000).toFixed(3) }} tn</td>
                <td class="py-2.5 pr-4 text-right font-semibold text-danger">-{{ (fila.consumoTotalKg / 1000).toFixed(3) }} tn</td>
                <td class="py-2.5 pr-4 text-right font-bold" :class="fila.stockProyectadoKg < 0 ? 'text-danger' : 'text-success'">
                  {{ (fila.stockProyectadoKg / 1000).toFixed(3) }} tn
                </td>
                <td class="py-2.5 text-right">
                  <span
                    class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-bold"
                    :class="fila.estado === 'ok' ? 'bg-success-light text-success' : 'bg-danger-light text-danger'"
                  >
                    {{ fila.estado === 'ok' ? 'OK' : 'INSUFICIENTE' }}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </VCard>

      <VCard v-else-if="!cargandoBase">
        <p class="py-6 text-center text-sm font-semibold text-text">Sin simulaciones todavía</p>
        <p class="pb-2 text-center text-sm text-text-soft">Elegí una fórmula y cantidad para calcular el impacto en stock</p>
      </VCard>
    </VSection>
  </div>
</template>
