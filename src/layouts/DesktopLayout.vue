<script setup>
// Layout para pantallas de escritorio: sidebar de navegación + <router-view>.
// Ancho/colapso/tratamiento de ítem activo clonados 1:1 de Flota
// (equipos2.vialtec.app) — ver memory/guia-estilo-flota.md §3. Cada módulo
// nuevo agrega su link en src/layouts/nav.js (compartido con MobileLayout,
// ver memory/pending.md — roadmap Mobile 2026-09-02) y su ruta en
// src/router/index.js.

import { computed, ref } from 'vue'
import { useAuthStore } from '@/stores/auth.store'
import logoVialtec from '@/assets/img/logo-vialtec.png'
import { SECCIONES, ICONOS } from '@/layouts/nav'

const auth = useAuthStore()

const colapsado = ref(false)

const seccionesVisibles = computed(() =>
  SECCIONES.map((s) => ({ ...s, links: s.links.filter((l) => auth.puedeVerTab(l.tab)) })).filter(
    (s) => s.links.length
  )
)

const iniciales = computed(() =>
  (auth.nombre || '')
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase())
    .join('') || '—'
)
</script>

<template>
  <div class="flex min-h-screen">
    <aside
      class="flex flex-col border-r border-gray-200 bg-gray-50 text-gray-600 transition-all duration-200"
      :class="colapsado ? 'w-[52px]' : 'w-[216px]'"
    >
      <div class="relative flex items-center justify-between px-3 py-4">
        <div v-if="!colapsado">
          <img :src="logoVialtec" alt="VIAL-TEC S.A." class="h-9 w-auto" />
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
