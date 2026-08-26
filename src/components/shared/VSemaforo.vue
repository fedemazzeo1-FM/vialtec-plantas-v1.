<script setup>
// Indicador tipo semáforo para alertas de stock del Dashboard (ver
// memory/business-rules.md): rojo = no alcanza, amarillo = alcanza pero queda
// por debajo del umbral proyectado, verde = ok.
defineProps({
  estado: {
    type: String,
    required: true, // 'rojo' | 'amarillo' | 'verde'
  },
})

const colorClass = {
  rojo: 'bg-red-500',
  amarillo: 'bg-yellow-400',
  verde: 'bg-green-500',
}
</script>

<template>
  <span
    class="inline-block h-3 w-3 rounded-full"
    :class="colorClass[estado] || 'bg-gray-300'"
    :title="estado"
  />
</template>
