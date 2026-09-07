<script setup>
// Layout para mobile/smartphone (roadmap 2026-09-02, memory/pending.md):
// nav inferior con los 4 módulos de mayor uso táctil (Pedidos, Báscula,
// Despachos, Stock — mismo orden de prioridad pedido por Federico) + botón
// "Más" que abre una hoja inferior con el resto de las secciones, el usuario
// logueado y "Cerrar sesión". Misma fuente de links que DesktopLayout
// (src/layouts/nav.js) — ningún módulo se define dos veces.
//
// Área táctil: cada ítem de la nav inferior es un botón de altura completa
// (~56px) con ícono 22px + label 10px, big enough para el pulgar sin
// apretarse contra el vecino.
import { computed, ref } from 'vue'
import { useAuthStore } from '@/stores/auth.store'
import logoVialtec from '@/assets/img/logo-vialtec.png'
import { SECCIONES, SECCION_ADMINISTRACION, ICONOS } from '@/layouts/nav'

const auth = useAuthStore()
const menuAbierto = ref(false)

const TABS_INFERIOR = ['pedidos', 'bascula', 'despachos', 'stock']

// SECCION_ADMINISTRACION no tiene tratamiento especial de "pinneado abajo"
// acá (2026-09-06) — a diferencia de DesktopLayout, "Más" ya es una hoja
// aparte del flujo principal, así que Administración entra como una sección
// más de esa hoja (al final de TODAS_LAS_SECCIONES).
const TODAS_LAS_SECCIONES = [...SECCIONES, SECCION_ADMINISTRACION]

const todosLosLinks = computed(() =>
  TODAS_LAS_SECCIONES.flatMap((s) => s.links).filter((l) => auth.puedeVerTab(l.tab))
)

const linksNavInferior = computed(() =>
  TABS_INFERIOR.map((tab) => todosLosLinks.value.find((l) => l.tab === tab)).filter(Boolean)
)

// El resto de los módulos visibles para el rol (los que no entran en la nav
// inferior) — se listan en la hoja "Más", agrupados igual que en Desktop.
const seccionesMas = computed(() =>
  TODAS_LAS_SECCIONES.map((s) => ({
    ...s,
    links: s.links.filter((l) => auth.puedeVerTab(l.tab) && !TABS_INFERIOR.includes(l.tab)),
  })).filter((s) => s.links.length)
)

function cerrarMenu() {
  menuAbierto.value = false
}
</script>

<template>
  <div class="flex min-h-screen flex-col bg-white">
    <header class="flex items-center justify-between border-b border-border px-4 py-3">
      <img :src="logoVialtec" alt="VIAL-TEC S.A." class="h-6 w-auto" />
      <button
        type="button"
        class="flex h-11 w-11 items-center justify-center rounded-md text-text-mid active:bg-gray-100"
        aria-label="Menú"
        @click="menuAbierto = true"
      >
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="h-6 w-6" v-html="ICONOS.menu" />
      </button>
    </header>

    <main class="min-w-0 flex-1 overflow-x-hidden p-4 pb-20">
      <router-view />
    </main>

    <!-- Nav inferior: 4 accesos directos + "Más". Altura ~56px, thumb-friendly. -->
    <nav class="fixed inset-x-0 bottom-0 z-40 flex border-t border-border bg-white">
      <router-link
        v-for="link in linksNavInferior"
        :key="link.to"
        :to="link.to"
        class="flex flex-1 flex-col items-center justify-center gap-0.5 py-2 text-text-soft"
        active-class="text-vialtec"
        style="min-height: 56px"
      >
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.5"
          stroke-linecap="round"
          stroke-linejoin="round"
          class="h-6 w-6 shrink-0"
          v-html="ICONOS[link.icon]"
        />
        <span class="text-[10px] font-semibold">{{ link.label }}</span>
      </router-link>
      <button
        type="button"
        class="flex flex-1 flex-col items-center justify-center gap-0.5 py-2 text-text-soft"
        style="min-height: 56px"
        @click="menuAbierto = true"
      >
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="h-6 w-6 shrink-0" v-html="ICONOS.menu" />
        <span class="text-[10px] font-semibold">Más</span>
      </button>
    </nav>

    <!-- Hoja inferior "Más": resto de módulos + usuario + salir. -->
    <div v-if="menuAbierto" class="fixed inset-0 z-50 flex flex-col justify-end bg-black/40" @click.self="cerrarMenu">
      <div class="max-h-[80vh] overflow-y-auto rounded-t-2xl bg-white p-4 pb-8">
        <div class="mb-4 flex items-center justify-between">
          <p class="text-sm font-bold text-text">Menú</p>
          <button
            type="button"
            class="flex h-11 w-11 items-center justify-center rounded-md text-text-soft active:bg-gray-100"
            aria-label="Cerrar menú"
            @click="cerrarMenu"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="h-5 w-5" v-html="ICONOS.cerrar" />
          </button>
        </div>

        <div v-for="seccion in seccionesMas" :key="seccion.titulo" class="mb-4">
          <p class="mb-1 px-1 text-xs font-semibold uppercase tracking-wide text-text-soft">{{ seccion.titulo }}</p>
          <router-link
            v-for="link in seccion.links"
            :key="link.to"
            :to="link.to"
            class="flex items-center gap-3 rounded-lg px-3 py-3 text-sm font-semibold text-text-mid active:bg-gray-50"
            style="min-height: 44px"
            active-class="text-vialtec"
            @click="cerrarMenu"
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
            {{ link.label }}
          </router-link>
        </div>

        <div class="mt-2 border-t border-border pt-3">
          <p class="px-1 text-sm font-semibold text-text">{{ auth.nombre }}</p>
          <p class="px-1 text-xs capitalize text-text-soft">{{ auth.rol }}</p>
          <button
            type="button"
            class="mt-2 flex w-full items-center gap-3 rounded-lg px-3 py-3 text-sm font-semibold text-danger active:bg-danger-light"
            style="min-height: 44px"
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
            Cerrar sesión
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
