<script setup>
// Modal genérico controlado por v-model:open.
// Uso previsto: modal de cargas al despachar un pedido, formularios de maestros, etc.
defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, default: '' },
})
defineEmits(['update:open'])
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
    @click.self="$emit('update:open', false)"
  >
    <div class="w-full max-w-lg rounded-lg bg-white p-4 shadow-lg">
      <div class="mb-3 flex items-center justify-between">
        <h3 v-if="title" class="text-lg font-semibold">{{ title }}</h3>
        <button class="text-gray-400 hover:text-gray-600" @click="$emit('update:open', false)">
          ✕
        </button>
      </div>
      <slot />
    </div>
  </div>
</template>
