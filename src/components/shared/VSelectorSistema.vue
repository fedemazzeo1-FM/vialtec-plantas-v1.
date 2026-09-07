<script setup>
// Selector para saltar entre los sistemas de VialTec (2026-09-07, pedido de
// Federico) — mismo patrón ya implementado en vialtec-flota-v2/src/layouts/
// DesktopLayout.vue#SISTEMAS, adaptado a este proyecto: acá no hay un
// <header> propio en DesktopLayout.vue (cada vista pone su título vía
// VSection, memory/conventions.md), así que el selector vive DENTRO de
// VSection.vue en vez del layout — así queda "en la misma línea que el
// título del módulo" en todas las pantallas con una sola instancia, sin
// tocar cada vista una por una.
//
// Sin pestaña nueva — mismo criterio que Flota: redirect directo en la
// misma pestaña con `window.location.href` (cambia de dominio/proyecto de
// Supabase Auth, así que no tiene sentido un <router-link> ni preservar
// historial de SPA).
import { onBeforeUnmount, onMounted, ref } from 'vue'

const SISTEMAS = [
  { value: 'plantas', label: '⚙ Plantas de Producción', url: null },
  { value: 'equipos', label: '⚙ Equipos y Pedidos', url: 'https://equipos2.vialtec.app' },
]
const SISTEMA_ACTUAL = 'plantas'

const sistemaActual = SISTEMAS.find((s) => s.value === SISTEMA_ACTUAL)
const menuAbierto = ref(false)
const menuRef = ref(null)

function toggleMenu() {
  menuAbierto.value = !menuAbierto.value
}

function elegirSistema(sistema) {
  menuAbierto.value = false
  if (!sistema.url) return
  window.location.href = sistema.url
}

function cerrarSiEsAfuera(event) {
  if (menuRef.value && !menuRef.value.contains(event.target)) {
    menuAbierto.value = false
  }
}

onMounted(() => document.addEventListener('click', cerrarSiEsAfuera))
onBeforeUnmount(() => document.removeEventListener('click', cerrarSiEsAfuera))
</script>

<template>
  <div ref="menuRef" class="relative shrink-0">
    <button
      type="button"
      class="flex h-7 items-center gap-1.5 whitespace-nowrap rounded-md border border-border px-2.5 text-xs font-semibold text-text-soft transition-colors duration-150 hover:bg-gray-50 hover:text-text-mid"
      @click="toggleMenu"
    >
      <span>{{ sistemaActual.label }}</span>
      <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        class="h-2.5 w-2.5 shrink-0 transition-transform duration-150"
        :class="{ 'rotate-180': menuAbierto }"
      >
        <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
      </svg>
    </button>

    <div
      v-if="menuAbierto"
      class="absolute right-0 top-full z-20 mt-1 w-52 rounded-lg border border-border bg-white py-1 shadow-lg"
    >
      <button
        v-for="sistema in SISTEMAS"
        :key="sistema.value"
        type="button"
        class="block w-full whitespace-nowrap px-3 py-2 text-left text-xs font-semibold transition-colors duration-150"
        :class="sistema.value === SISTEMA_ACTUAL ? 'bg-vialtec/10 text-vialtec' : 'text-text-soft hover:bg-gray-50 hover:text-text-mid'"
        @click="elegirSistema(sistema)"
      >
        {{ sistema.label }}
      </button>
    </div>
  </div>
</template>
