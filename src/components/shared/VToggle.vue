<script setup>
// Switch on/off — creado 2026-09-06 para la matriz de permisos del módulo
// Administración (calco del switch púrpura del sistema de Flota, pedido
// explícito de Federico: "calcando exactamente... la matriz de switches
// púrpura de la captura"). Genérico, v-model:modelValue — reusable en
// cualquier otro on/off del sistema si hace falta más adelante.
defineProps({
  modelValue: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
})
defineEmits(['update:modelValue'])
</script>

<template>
  <button
    type="button"
    role="switch"
    :aria-checked="modelValue"
    :disabled="disabled"
    class="relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors duration-150 focus:outline-none focus:ring-2 focus:ring-offset-2"
    :class="[
      modelValue ? 'bg-[#7c3aed] focus:ring-[#7c3aed]/40' : 'bg-gray-300 focus:ring-gray-300/40',
      disabled ? 'cursor-not-allowed opacity-50' : 'cursor-pointer',
    ]"
    @click="!disabled && $emit('update:modelValue', !modelValue)"
  >
    <span
      class="inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform duration-150"
      :class="modelValue ? 'translate-x-6' : 'translate-x-1'"
    />
  </button>
</template>
