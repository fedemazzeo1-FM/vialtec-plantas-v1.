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

// Área táctil (roadmap Mobile, memory/pending.md 2026-09-02): mobile-first,
// el padding grande de acá abajo es el que rige por debajo de 768px
// (~44px de alto en `sm`, ~48px en `md`); `md:` (mismo breakpoint que
// useBreakpoint()) lo recorta a las medidas compactas originales para
// desktop, donde el mouse no necesita ese margen.
const SIZE_CLASS = {
  sm: 'px-3 py-3 text-xs rounded-md md:px-[10px] md:py-[5px]',
  md: 'px-4 py-3 text-sm rounded-lg md:py-2',
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
