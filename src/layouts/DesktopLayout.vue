<script setup>
// Layout para pantallas de escritorio: sidebar de navegación + <router-view>.
// Ancho/colapso/tratamiento de ítem activo clonados 1:1 de Flota
// (equipos2.vialtec.app) — ver memory/guia-estilo-flota.md §3. Cada módulo
// nuevo agrega su link acá (con su `tab` y su `icon`, ver auth.store.js
// #puedeVerTab) y su ruta en src/router/index.js.
//
// Sin librería de íconos (el proyecto no tenía ninguna instalada) — set
// propio de SVGs inline mínimos en vez de agregar una dependencia nueva.

import { computed, ref } from 'vue'
import { useAuthStore } from '@/stores/auth.store'
import logoVialtec from '@/assets/img/logo-vialtec.png'

const auth = useAuthStore()

const colapsado = ref(false)

const secciones = [
  {
    titulo: 'General',
    links: [{ to: '/dashboard', label: 'Dashboard', tab: 'dashboard', icon: 'grid' }],
  },
  {
    titulo: 'Operación',
    links: [
      { to: '/plan-semanal', label: 'Plan semanal', tab: 'plan-semanal', icon: 'calendario' },
      { to: '/pedidos', label: 'Pedidos', tab: 'pedidos', icon: 'clipboard' },
      { to: '/despachos', label: 'Despachos', tab: 'despachos', icon: 'camion' },
      { to: '/bascula', label: 'Báscula', tab: 'bascula', icon: 'balanza' },
      { to: '/stock', label: 'Stock', tab: 'stock', icon: 'caja' },
      { to: '/simulador', label: 'Simulador', tab: 'simulador', icon: 'capas' },
    ],
  },
  {
    titulo: 'Administración',
    links: [
      { to: '/formulas', label: 'Fórmulas', tab: 'formulas', icon: 'matraz' },
      { to: '/maestros', label: 'Maestros', tab: 'maestros', icon: 'base-datos' },
    ],
  },
]

const seccionesVisibles = computed(() =>
  secciones
    .map((s) => ({ ...s, links: s.links.filter((l) => auth.puedeVerTab(l.tab)) }))
    .filter((s) => s.links.length)
)

const iniciales = computed(() =>
  (auth.nombre || '')
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase())
    .join('') || '—'
)

// Set mínimo de íconos outline (24x24, stroke-only) — reemplazable por una
// librería de verdad (ej. Heroicons) si en algún momento se agrega como
// dependencia. Markup estático (no viene de datos de usuario ni de DB), no
// hay riesgo de inyección al renderizarlo con v-html.
const ICONOS = {
  grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  clipboard:
    '<rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 4V3a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v1"/><line x1="8" y1="10" x2="16" y2="10"/><line x1="8" y1="14" x2="16" y2="14"/><line x1="8" y1="18" x2="13" y2="18"/>',
  calendario:
    '<rect x="3" y="5" width="18" height="16" rx="2"/><line x1="16" y1="3" x2="16" y2="7"/><line x1="8" y1="3" x2="8" y2="7"/><line x1="3" y1="10" x2="21" y2="10"/>',
  balanza:
    '<line x1="12" y1="3" x2="12" y2="21"/><line x1="5" y1="7" x2="19" y2="7"/><path d="M5 7l-3 6a3 3 0 0 0 6 0z"/><path d="M19 7l-3 6a3 3 0 0 0 6 0z"/>',
  camion:
    '<rect x="1" y="7" width="13" height="10" rx="1"/><path d="M14 10h4l3 3v4h-7z"/><circle cx="6" cy="19" r="2"/><circle cx="17" cy="19" r="2"/>',
  caja:
    '<path d="M3 8l9-5 9 5-9 5-9-5z"/><path d="M3 8v9l9 5 9-5V8"/><line x1="12" y1="13" x2="12" y2="22"/>',
  capas:
    '<path d="M12 2 2 7l10 5 10-5-10-5z"/><path d="M2 12l10 5 10-5"/><path d="M2 17l10 5 10-5"/>',
  matraz: '<path d="M9 3h6M10 3v5.5L5.5 17a2 2 0 0 0 1.8 3h9.4a2 2 0 0 0 1.8-3L14 8.5V3"/>',
  'base-datos':
    '<ellipse cx="12" cy="5" rx="8" ry="3"/><path d="M4 5v6c0 1.7 3.6 3 8 3s8-1.3 8-3V5"/><path d="M4 11v6c0 1.7 3.6 3 8 3s8-1.3 8-3v-6"/>',
  salir: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/>',
}
</script>

<template>
  <div class="flex min-h-screen">
    <aside
      class="flex flex-col border-r border-gray-200 bg-gray-50 text-gray-600 transition-all duration-200"
      :class="colapsado ? 'w-[52px]' : 'w-[216px]'"
    >
      <div class="flex items-center justify-between px-3 py-4">
        <div v-if="!colapsado">
          <img :src="logoVialtec" alt="VIAL-TEC S.A." class="h-7 w-auto" />
          <p class="mt-0.5 text-[10px] font-semibold uppercase tracking-wide text-text-soft">Plantas</p>
        </div>
        <span
          v-else
          class="mx-auto flex h-8 w-8 items-center justify-center rounded-md bg-vialtec text-xs font-bold text-white"
        >
          VT
        </span>
        <button
          type="button"
          class="shrink-0 rounded-md p-1 text-gray-400 transition-colors duration-150 hover:bg-gray-200 hover:text-gray-600"
          :class="{ 'absolute right-1': colapsado }"
          @click="colapsado = !colapsado"
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="h-4 w-4">
            <polyline v-if="!colapsado" points="15 18 9 12 15 6" stroke-linecap="round" stroke-linejoin="round" />
            <polyline v-else points="9 18 15 12 9 6" stroke-linecap="round" stroke-linejoin="round" />
          </svg>
        </button>
      </div>

      <nav class="flex-1 space-y-4 px-2">
        <div v-for="seccion in seccionesVisibles" :key="seccion.titulo">
          <p v-if="!colapsado" class="mb-1 px-2 text-xs font-semibold uppercase tracking-wide text-gray-400">
            {{ seccion.titulo }}
          </p>
          <ul class="space-y-1">
            <li v-for="link in seccion.links" :key="link.to">
              <router-link
                :to="link.to"
                class="flex items-center gap-3 rounded-lg px-2 py-2 text-sm font-semibold transition-colors duration-150"
                :class="colapsado ? 'justify-center' : ''"
                active-class="bg-vialtec/10 text-vialtec"
                :title="colapsado ? link.label : null"
              >
                <svg
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="1.5"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  class="h-5 w-5 shrink-0"
                  v-html="ICONOS[link.icon]"
                />
                <span v-if="!colapsado">{{ link.label }}</span>
              </router-link>
            </li>
          </ul>
        </div>
      </nav>

      <div class="border-t border-gray-200 px-2 py-3">
        <div class="flex items-center gap-2 px-2" :class="colapsado ? 'justify-center' : ''">
          <span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-vialtec text-xs font-bold text-white">
            {{ iniciales }}
          </span>
          <div v-if="!colapsado" class="min-w-0 text-xs">
            <p class="truncate font-semibold text-text">{{ auth.nombre }}</p>
            <p class="truncate capitalize text-text-soft">{{ auth.rol }}</p>
          </div>
        </div>
        <button
          type="button"
          class="mt-2 flex w-full items-center gap-3 rounded-lg px-2 py-2 text-sm font-semibold text-danger transition-colors duration-150 hover:bg-danger-light"
          :class="colapsado ? 'justify-center' : ''"
          :title="colapsado ? 'Cerrar sesión' : null"
          @click="auth.logout()"
        >
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
            stroke-linecap="round"
            stroke-linejoin="round"
            class="h-5 w-5 shrink-0"
            v-html="ICONOS.salir"
          />
          <span v-if="!colapsado">Cerrar sesión</span>
        </button>
      </div>
    </aside>

    <main class="min-w-0 flex-1 overflow-x-auto p-6">
      <router-view />
    </main>
  </div>
</template>
