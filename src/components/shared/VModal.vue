<script setup>
// Modal genérico controlado por v-model:open.
// Uso previsto: modal de cargas al despachar un pedido, formularios de maestros, etc.
// Chrome clonado de los modales de Flota (equipos2.vialtec.app) — ver
// memory/guia-estilo-flota.md §4.
//
// `size` (2026-09-04, bug real reportado por Federico: la vista previa de
// impresión de Báscula "está toda apiñada, no se ve linda"): el default
// `max-w-lg` (512px) alcanza para formularios, pero el vale de báscula
// (grid de 2 columnas pensado para una hoja A4 landscape de 297mm) queda
// apretado ahí. 'xl' es un ancho mayor para contenido de ese tipo —
// ningún caller existente cambia de comportamiento (default sigue siendo
// 'md', el mismo max-w-lg de siempre).
defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, default: '' },
  size: { type: String, default: 'md' }, // 'md' (max-w-lg) | 'xl' (max-w-4xl) | '2xl' (max-w-6xl)
})
defineEmits(['update:open'])

const anchoClase = { md: 'max-w-lg', xl: 'max-w-4xl', '2xl': 'max-w-6xl' }
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
    @click.self="$emit('update:open', false)"
  >
    <div class="w-full max-h-[90vh] overflow-y-auto rounded-xl bg-white p-6 shadow-xl" :class="anchoClase[size] || anchoClase.md">
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
