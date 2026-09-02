<script setup>
// Contenedor genérico con estilo de card (padding, borde, sombra).
// Estilo clonado de las cards de Flota (equipos2.vialtec.app) — ver
// memory/guia-estilo-flota.md §4.
</script>

<template>
  <div class="rounded-xl border border-border bg-white p-4 shadow-sm">
    <slot />
  </div>
</template>
