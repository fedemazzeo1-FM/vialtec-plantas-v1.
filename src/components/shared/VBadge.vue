<script setup>
// Badge de estado (ej. solicitado/confirmado/despachado/postergado/cancelado).
defineProps({
  variant: {
    type: String,
    default: 'default', // default | success | warning | danger | info | postergado
  },
})

const variantClass = {
  default: 'bg-gray-100 text-gray-700',
  success: 'bg-green-100 text-green-700',
  warning: 'bg-yellow-100 text-yellow-700',
  danger: 'bg-red-100 text-red-700',
  info: 'bg-blue-100 text-blue-700',
  // Violeta — solo para el estado "postergado" de pedidos, distinto del
  // ámbar de "solicitado" (memory/relevamiento-sistema-viejo.md Etapa 3:
  // colores reales del legado, no un tono inventado). bg-vialtec/10 en vez
  // de un tono fijo tipo bg-purple-100 porque el resto de esta paleta
  // todavía es la vieja (sin los tokens success/danger/etc de Flota) — se
  // homologa cuando se aplique el refactor visual completo.
  postergado: 'bg-vialtec/10 text-vialtec',
}
</script>

<template>
  <span
    class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium"
    :class="variantClass[variant] || variantClass.default"
  >
    <slot />
  </span>
</template>
