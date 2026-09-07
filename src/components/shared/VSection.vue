<script setup>
// Sección con título, para agrupar contenido dentro de una vista/módulo.
//
// Selector de sistema (2026-09-07, pedido de Federico): vive acá, no en
// DesktopLayout.vue — este proyecto no tiene un <header> propio (a
// diferencia de Flota), cada vista pone su título vía VSection, y todas
// la usan exactamente una vez como título de página (grep confirmado en
// src/views/*.vue) — así queda en la misma línea que el título del
// módulo en toda la app con un solo cambio.
import VSelectorSistema from '@/components/shared/VSelectorSistema.vue'

defineProps({
  title: { type: String, default: '' },
})
</script>

<template>
  <section class="mb-6">
    <div v-if="title" class="mb-2 flex items-center justify-between gap-3">
      <h2 class="text-lg font-bold text-text">{{ title }}</h2>
      <VSelectorSistema />
    </div>
    <slot />
  </section>
</template>
