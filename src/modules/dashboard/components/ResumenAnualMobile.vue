<script setup>
// Tarjeta "Acumulado del año" para mobile — solo admin y gerencia (ver
// useResumenAnualMobile.js). Se renderiza vacía para cualquier otro caso.
import VCard from '@/components/shared/VCard.vue'
import { useResumenAnualMobile } from '@/modules/dashboard/composables/useResumenAnualMobile'

const resumen = useResumenAnualMobile()
const anio = new Date().getFullYear()

function formatear(valor) {
  return valor.toLocaleString('es-AR', { maximumFractionDigits: 1 })
}
</script>

<template>
  <VCard v-if="resumen.visible" class="mb-3">
    <p class="text-[11px] font-semibold uppercase tracking-wide text-text-soft">Acumulado {{ anio }}</p>
    <p v-if="resumen.cargando" class="mt-2 text-sm text-text-soft">Cargando…</p>
    <p v-else-if="resumen.error" class="mt-2 text-sm text-danger">{{ resumen.error }}</p>
    <template v-else>
      <div class="mt-2 grid grid-cols-2 gap-3">
        <div>
          <p class="text-xs text-text-soft">Asfalto</p>
          <p class="text-xl font-extrabold text-text">{{ formatear(resumen.asfalto.totalTn) }} <span class="text-sm font-semibold text-text-soft">tn</span></p>
        </div>
        <div>
          <p class="text-xs text-text-soft">Hormigón</p>
          <p class="text-xl font-extrabold text-text">{{ formatear(resumen.hormigonM3) }} <span class="text-sm font-semibold text-text-soft">m³</span></p>
        </div>
      </div>
      <div class="mt-3 space-y-1 border-t border-border pt-2 text-sm">
        <div class="flex items-center justify-between">
          <span class="text-text-mid">Ammann 140 <span class="text-xs text-text-soft">(ene-abr)</span></span>
          <span class="font-semibold text-text">{{ formatear(resumen.asfalto.ammannTn) }} tn</span>
        </div>
        <div class="flex items-center justify-between">
          <span class="text-text-mid">Marini 180 <span class="text-xs text-text-soft">(desde mayo)</span></span>
          <span class="font-semibold text-text">{{ formatear(resumen.asfalto.mariniTn) }} tn</span>
        </div>
      </div>
    </template>
  </VCard>
</template>
