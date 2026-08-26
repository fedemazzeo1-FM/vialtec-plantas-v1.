<script setup>
// Badge de estado (ej. solicitado/confirmado/despachado/postergado/cancelado).
defineProps({
  variant: {
    type: String,
    default: 'default', // default | success | warning | danger | info
  },
})

const variantClass = {
  default: 'bg-gray-100 text-gray-700',
  success: 'bg-green-100 text-green-700',
  warning: 'bg-yellow-100 text-yellow-700',
  danger: 'bg-red-100 text-red-700',
  info: 'bg-blue-100 text-blue-700',
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
