<script setup>
// Layout para pantallas de escritorio: sidebar de navegación + <router-view>.
// Las secciones del sidebar agrupan módulos por área (Administración, Operación,
// etc.). Cada módulo nuevo agrega su link acá (con su `tab`, ver
// auth.store.js#puedeVerTab) y su ruta en src/router/index.js.

import { computed } from 'vue'
import { useAuthStore } from '@/stores/auth.store'

const auth = useAuthStore()

const secciones = [
  {
    titulo: 'General',
    links: [{ to: '/dashboard', label: 'Dashboard', tab: 'dashboard' }],
  },
  {
    titulo: 'Operación',
    links: [
      { to: '/plan-semanal', label: 'Plan semanal', tab: 'plan-semanal' },
      { to: '/pedidos', label: 'Pedidos', tab: 'pedidos' },
      { to: '/bascula', label: 'Báscula', tab: 'bascula' },
    ],
  },
  {
    titulo: 'Administración',
    links: [
      { to: '/formulas', label: 'Fórmulas', tab: 'formulas' },
      { to: '/maestros', label: 'Maestros', tab: 'maestros' },
    ],
  },
]

// Solo se muestran los links que el rol logueado puede ver — las secciones
// que se quedan sin ningún link visible no se pintan.
const seccionesVisibles = computed(() =>
  secciones.map((s) => ({ ...s, links: s.links.filter((l) => auth.puedeVerTab(l.tab)) })).filter((s) => s.links.length)
)
</script>

<template>
  <div class="flex min-h-screen">
    <aside class="flex w-60 shrink-0 flex-col border-r border-gray-200 bg-white p-4">
      <p class="mb-4 text-lg font-semibold">VialTec Plantas</p>

      <nav class="flex-1 space-y-4 text-sm">
        <div v-for="seccion in seccionesVisibles" :key="seccion.titulo">
          <p class="mb-1 px-2 text-xs font-semibold uppercase tracking-wide text-gray-400">
            {{ seccion.titulo }}
          </p>
          <ul class="space-y-1">
            <li v-for="link in seccion.links" :key="link.to">
              <router-link
                :to="link.to"
                class="block rounded px-2 py-1.5 hover:bg-gray-100"
                active-class="bg-gray-100 font-medium"
              >
                {{ link.label }}
              </router-link>
            </li>
          </ul>
        </div>
      </nav>

      <div class="border-t border-gray-100 pt-3 text-xs text-gray-500">
        <p class="font-medium text-gray-700">{{ auth.nombre }}</p>
        <p class="mb-2 capitalize">{{ auth.rol }}</p>
        <button type="button" class="text-red-500 hover:underline" @click="auth.logout()">Cerrar sesión</button>
      </div>
    </aside>

    <main class="flex-1 p-6">
      <router-view />
    </main>
  </div>
</template>
