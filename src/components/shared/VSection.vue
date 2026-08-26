<script setup>
// Sección con título, para agrupar contenido dentro de una vista/módulo.
defineProps({
  title: { type: String, default: '' },
})
</script>

<template>
  <section class="mb-6">
    <h2 v-if="title" class="mb-2 text-lg font-semibold">{{ title }}</h2>
    <slot />
  </section>
</template>
