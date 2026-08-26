<script setup>
// Raíz de la app. El layout (que contiene <router-view />) decide la estructura
// de pantalla. Por ahora solo existe DesktopLayout — cuando haya detección de
// mobile/breakpoint se elige entre DesktopLayout y MobileLayout acá.
import DesktopLayout from '@/layouts/DesktopLayout.vue'
</script>

<template>
  <DesktopLayout />
</template>
