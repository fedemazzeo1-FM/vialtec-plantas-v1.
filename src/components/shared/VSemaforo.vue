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

// Colores clonados de Flota (equipos2.vialtec.app) — ver
// memory/guia-estilo-flota.md. Mismo semáforo de 3 estados que el módulo
// Stock del sistema legado (memory/relevamiento-sistema-viejo.md §6).
const colorClass = {
  rojo: 'bg-danger',
  amarillo: 'bg-warning',
  verde: 'bg-success',
}
</script>

<template>
  <span
    class="inline-block h-3 w-3 rounded-full"
    :class="colorClass[estado] || 'bg-gray-300'"
    :title="estado"
  />
</template>
