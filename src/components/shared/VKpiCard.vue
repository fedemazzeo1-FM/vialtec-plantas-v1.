<script setup>
// KPI destacado (ej. tn producidas, m³ del día) con label + valor + unidad opcional.
// Estilo clonado de las tarjetas KPI de Flota (equipos2.vialtec.app) — ver
// memory/guia-estilo-flota.md §4.
defineProps({
  label: { type: String, required: true },
  value: { type: [String, Number], required: true },
  unidad: { type: String, default: '' },
  // Punto de estado opcional (arriba a la derecha), mismo patrón que las
  // tarjetas de Vencimientos en Flota (🔴 vencidos / 🟠 próximos / 🟢 al día).
  // No pisa nada si no se pasa.
  estado: { type: String, default: null }, // danger | warning | success
})

const dotClass = {
  danger: 'bg-danger',
  warning: 'bg-warning',
  success: 'bg-success',
}
</script>

<template>
  <div class="rounded-xl border border-border bg-white p-[18px] shadow-sm">
    <div class="flex items-center justify-between">
      <p class="text-[11px] font-semibold uppercase tracking-wide text-text-soft">{{ label }}</p>
      <span v-if="estado" class="h-2.5 w-2.5 shrink-0 rounded-full" :class="dotClass[estado]" />
    </div>
    <p class="mt-2 text-2xl font-extrabold text-text">
      {{ value }}<span v-if="unidad" class="ml-1 text-base font-normal text-text-soft">{{ unidad }}</span>
    </p>
  </div>
</template>
