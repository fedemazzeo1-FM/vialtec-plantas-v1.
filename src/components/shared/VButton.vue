<script setup>
// Botón genérico. Clonado 1:1 del sistema de botones de Flota
// (equipos2.vialtec.app) — ver memory/guia-estilo-flota.md §4: 2 tamaños ×
// 3 variantes con clases fijas, sin CSS custom.
//
// size: 'sm' (acciones inline de tabla/filtros) | 'md' (footer de modal, formularios)
// variant: 'primary' (acción principal) | 'secondary' (outline) | 'danger' (destructivo)
//   | 'success' (despachar/entregar — verde, distinto del violeta de "confirmar")
//   | 'ghost' (link liso, ej. "Limpiar")
defineProps({
  variant: { type: String, default: 'primary' },
  size: { type: String, default: 'md' },
  type: { type: String, default: 'button' },
  disabled: { type: Boolean, default: false },
})
defineEmits(['click'])

const BASE =
  'inline-flex items-center justify-center font-semibold transition-colors duration-150 disabled:cursor-not-allowed disabled:opacity-50 gap-1.5'

const SIZE_CLASS = {
  sm: 'px-[10px] py-[5px] text-xs rounded-md',
  md: 'px-4 py-2 text-sm rounded-lg',
}

const VARIANT_CLASS = {
  primary: 'bg-vialtec text-white hover:opacity-90',
  secondary: 'border border-border text-text-mid hover:bg-gray-50',
  danger: 'bg-danger text-white hover:opacity-90',
  success: 'bg-success text-white hover:opacity-90',
  // No es de Flota (no vimos un botón "ghost" con estas medidas), pero
  // "Limpiar filtros" en Flota se ve como texto liso sin caja — replicamos
  // esa idea con las mismas variables de color que el resto del sistema.
  ghost: 'text-text-mid hover:text-vialtec',
}
</script>

<template>
  <button
    :type="type"
    :disabled="disabled"
    :class="[BASE, SIZE_CLASS[size] || SIZE_CLASS.md, VARIANT_CLASS[variant] || VARIANT_CLASS.primary]"
    @click="$emit('click', $event)"
  >
    <slot />
  </button>
</template>
