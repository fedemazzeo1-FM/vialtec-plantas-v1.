<script setup>
// Modal genérico controlado por v-model:open.
// Uso previsto: modal de cargas al despachar un pedido, formularios de maestros, etc.
// Chrome clonado de los modales de Flota (equipos2.vialtec.app) — ver
// memory/guia-estilo-flota.md §4.
defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, default: '' },
})
defineEmits(['update:open'])
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
    @click.self="$emit('update:open', false)"
  >
    <div class="w-full max-w-lg max-h-[90vh] overflow-y-auto rounded-xl bg-white p-6 shadow-xl">
      <div class="mb-4 flex items-center justify-between">
        <h3 v-if="title" class="text-lg font-bold text-text">{{ title }}</h3>
        <button
          class="shrink-0 rounded-md p-1 text-gray-400 transition-colors duration-150 hover:bg-gray-200 hover:text-gray-600"
          @click="$emit('update:open', false)"
        >
          ✕
        </button>
      </div>
      <slot />
    </div>
  </div>
</template>
