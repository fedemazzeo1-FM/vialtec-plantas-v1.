<script setup>
// KPI destacado (ej. tn producidas, m³ del día) con label + valor + unidad opcional.
defineProps({
  label: { type: String, required: true },
  value: { type: [String, Number], required: true },
  unidad: { type: String, default: '' },
})
</script>

<template>
  <div class="rounded-lg border border-gray-200 bg-white p-4 shadow-sm">
    <p class="text-sm text-gray-500">{{ label }}</p>
    <p class="text-2xl font-semibold">
      {{ value }}<span v-if="unidad" class="ml-1 text-base font-normal">{{ unidad }}</span>
    </p>
  </div>
</template>
