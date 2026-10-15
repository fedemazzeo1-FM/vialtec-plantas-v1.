<script setup>
// Tarjeta "Comparativo del mes" de Home — template puro, la lógica vive en
// useComparativoMes.js / services/comparativo-mes.js.
import VCard from '@/components/shared/VCard.vue'
import { useComparativoMes } from '@/modules/dashboard/composables/useComparativoMes'

const { cargando, error, subtitulo, filas, cargar } = useComparativoMes()

const claseBadge = {
  sube: 'bg-success-light text-success',
  baja: 'bg-danger-light text-danger',
  igual: 'bg-panel text-text-soft',
}

cargar()
</script>

<template>
  <VCard v-if="cargando || error || filas.length" class="mb-6">
    <h3 class="text-sm font-bold text-text">Comparativo del mes</h3>
    <p class="text-xs text-text-soft">{{ subtitulo }}</p>
    <p v-if="cargando" class="mt-3 text-sm text-text-soft">Cargando…</p>
    <p v-else-if="error" class="mt-3 text-sm text-danger">{{ error }}</p>
    <div v-else class="mt-1">
      <div
        v-for="f in filas"
        :key="f.tipo.id"
        class="flex flex-col gap-2 border-b border-border py-3 last:border-0 last:pb-0 sm:flex-row sm:items-center sm:justify-between sm:gap-4"
      >
        <p class="flex min-w-0 items-start gap-2 text-sm text-text-mid">
          <span class="mt-1.5 h-2 w-2 shrink-0 rounded-full" :class="f.tipo.clases.punto"></span>
          <span>{{ f.frase }}</span>
        </p>
        <span
          class="shrink-0 self-start whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-semibold sm:self-auto"
          :class="f.anterior === 0 ? claseBadge.igual : claseBadge[f.tendencia]"
        >
          {{ f.badge }}
        </span>
      </div>
    </div>
  </VCard>
</template>
