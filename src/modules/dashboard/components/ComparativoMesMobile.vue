<script setup>
// Tarjeta "Comparativo del mes" para mobile — solo admin y gerencia (ver
// useComparativoMesMobile.js). Mismas filas que ComparativoMesCard.vue de
// Home, compactadas para pantalla chica: tipo + cantidad + variación arriba,
// la frase completa abajo. Se renderiza vacía para cualquier otro caso.
import VCard from '@/components/shared/VCard.vue'
import { useComparativoMesMobile } from '@/modules/dashboard/composables/useComparativoMesMobile'

const comparativo = useComparativoMesMobile()

const claseBadge = {
  sube: 'bg-success-light text-success',
  baja: 'bg-danger-light text-danger',
  igual: 'bg-panel text-text-soft',
}

function formatear(valor) {
  return valor.toLocaleString('es-AR', { maximumFractionDigits: 1 })
}
</script>

<template>
  <VCard
    v-if="comparativo.visible && (comparativo.cargando || comparativo.error || comparativo.filas.length)"
    class="mb-3"
  >
    <p class="text-[11px] font-semibold uppercase tracking-wide text-text-soft">Comparativo del mes</p>
    <p class="text-xs text-text-soft">{{ comparativo.subtitulo }}</p>
    <p v-if="comparativo.cargando" class="mt-2 text-sm text-text-soft">Cargando…</p>
    <p v-else-if="comparativo.error" class="mt-2 text-sm text-danger">{{ comparativo.error }}</p>
    <div v-else class="mt-1">
      <div v-for="f in comparativo.filas" :key="f.tipo.id" class="border-b border-border py-2.5 last:border-0 last:pb-0">
        <div class="flex items-center justify-between gap-2">
          <p class="flex min-w-0 items-center gap-2">
            <span class="h-2 w-2 shrink-0 rounded-full" :class="f.tipo.clases.punto"></span>
            <span class="text-xs text-text-soft">{{ f.tipo.nombre }}</span>
            <span class="text-base font-extrabold text-text">
              {{ formatear(f.actual) }} <span class="text-xs font-semibold text-text-soft">{{ f.tipo.unidadLabel }}</span>
            </span>
          </p>
          <span
            class="shrink-0 whitespace-nowrap rounded-full px-2 py-0.5 text-[11px] font-semibold"
            :class="f.anterior === 0 ? claseBadge.igual : claseBadge[f.tendencia]"
          >
            {{ f.badge }}
          </span>
        </div>
        <p class="mt-1 text-xs leading-snug text-text-mid">{{ f.frase }}</p>
      </div>
    </div>
  </VCard>
</template>
