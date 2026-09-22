<script setup>
// Layout para mobile/smartphone. Nav inferior con los 4 módulos operativos
// de uso táctil diario (Pedidos, Calendario, Stock, Báscula) + FAB central
// de "Nuevo pedido". Misma fuente de links que DesktopLayout (src/layouts/
// nav.js) para esos 4 — ningún módulo se define dos veces.
//
// Sin acceso al resto de los módulos desde mobile (rediseño Mobile-First
// 2026-09-22, pedido explícito de Federico: "el menú con el resto de los
// módulos lo sacaría, solo me interesa el home, pero si es más fácil
// sacarlo, sacalo" — se optó por sacarlo entero): Home/Despachos/Simulador/
// Fórmulas/Administración/Maestros quedan exclusivos de Desktop. El ícono
// del header ya no abre un menú de navegación, solo una hoja mínima con el
// usuario logueado y "Cerrar sesión" — logout tiene que seguir siendo
// alcanzable desde mobile pase lo que pase con el resto del menú.
//
// Área táctil: cada ítem de la nav inferior es un botón de altura completa
// (~56px) con ícono 22px + label 10px, big enough para el pulgar sin
// apretarse contra el vecino.
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth.store'
import logoVialtec from '@/assets/img/logo-vialtec.png'
import { SECCIONES, SECCION_ADMINISTRACION, ICONOS } from '@/layouts/nav'

const auth = useAuthStore()
const router = useRouter()
const menuAbierto = ref(false)

// Prioridad de la nav inferior (rediseño Mobile-First 2026-09-22, pedido
// explícito de Federico: "Pedidos, Calendario, Stock, Báscula" en ese orden
// exacto — antes era ['bascula', 'pedidos', 'plan-semanal', 'stock']).
// Se dividen 2+2 alrededor del FAB central de "Nuevo pedido" (ver abajo).
const TABS_INFERIOR = ['pedidos', 'plan-semanal', 'stock', 'bascula']

// Solo se usa para resolver ícono/label de los 4 tabs de TABS_INFERIOR — el
// resto de los links de estas secciones no se lista en ningún lado de mobile
// (ver comentario de arriba).
const TODAS_LAS_SECCIONES = [...SECCIONES, SECCION_ADMINISTRACION]

const todosLosLinks = computed(() =>
  TODAS_LAS_SECCIONES.flatMap((s) => s.links).filter((l) => auth.puedeVerTab(l.tab))
)

// Label corto solo para la nav inferior — "Plan Semanal" se etiqueta
// "Calendario" acá (pedido explícito de Federico, rediseño Mobile-First
// 2026-09-22: pasa a ser la franja de días + detalle diario, ver
// PlanSemanalView.vue) sin tocar `nav.js` (fuente compartida con Desktop,
// donde el nombre completo "Plan semanal" sigue aplicando).
const ETIQUETA_CORTA_INFERIOR = { 'plan-semanal': 'Calendario' }

const linksNavInferior = computed(() =>
  TABS_INFERIOR.map((tab) => todosLosLinks.value.find((l) => l.tab === tab))
    .filter(Boolean)
    .map((link) => ({ ...link, labelCorta: ETIQUETA_CORTA_INFERIOR[link.tab] ?? link.label }))
)

// Mitad izquierda/derecha de la nav inferior, separadas por el FAB central
// (2 + FAB + 2) — ver template.
const linksNavIzquierda = computed(() => linksNavInferior.value.slice(0, 2))
const linksNavDerecha = computed(() => linksNavInferior.value.slice(2, 4))

function cerrarMenu() {
  menuAbierto.value = false
}

// FAB "Nuevo pedido" (rediseño Mobile-First 2026-09-22, pedido explícito de
// Federico: crear un pedido "desde cualquier pantalla"). El estado del
// formulario/modal vive en usePedidos.js (PedidosView.vue) — acá solo se
// navega a /pedidos con `?nuevo=1`; PedidosView lo detecta (una vez que
// terminó de cargar sus catálogos base) y abre el modal solo, limpiando el
// query después. Evita duplicar el composable completo de Pedidos en el
// layout solo para poder abrir un modal desde afuera.
function abrirNuevoPedido() {
  router.push({ path: '/pedidos', query: { nuevo: '1' } })
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

    <!-- Nav inferior: Pedidos/Calendario · FAB Nuevo pedido · Stock/Báscula,
         sin "Más" (rediseño Mobile-First 2026-09-22). Altura ~56px por
         ítem, thumb-friendly. El FAB se eleva por encima de la línea de la
         barra (-mt) para quedar destacado, sin tapar ningún label vecino
         (queda en su propia columna flex). -->
    <nav class="fixed inset-x-0 bottom-0 z-40 flex items-stretch border-t border-border bg-white">
      <router-link
        v-for="link in linksNavIzquierda"
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
        <span class="text-[10px] font-semibold">{{ link.labelCorta }}</span>
      </router-link>

      <div class="flex flex-1 items-start justify-center">
        <button
          type="button"
          class="-mt-6 flex h-14 w-14 items-center justify-center rounded-full bg-vialtec text-white shadow-lg transition-transform duration-150 active:scale-95"
          aria-label="Nuevo pedido"
          @click="abrirNuevoPedido"
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" class="h-6 w-6" v-html="ICONOS.plus" />
        </button>
      </div>

      <router-link
        v-for="link in linksNavDerecha"
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
        <span class="text-[10px] font-semibold">{{ link.labelCorta }}</span>
      </router-link>
    </nav>

    <!-- Hoja "Mi cuenta": solo usuario logueado + "Cerrar sesión" — sin
         listado de módulos (rediseño Mobile-First 2026-09-22, ver comentario
         de arriba). Abierta desde el ícono del header. -->
    <div v-if="menuAbierto" class="fixed inset-0 z-50 flex flex-col justify-end bg-black/40" @click.self="cerrarMenu">
      <div class="max-h-[80vh] overflow-y-auto rounded-t-2xl bg-white p-4 pb-8">
        <div class="mb-4 flex items-center justify-between">
          <p class="text-sm font-bold text-text">Mi cuenta</p>
          <button
            type="button"
            class="flex h-11 w-11 items-center justify-center rounded-md text-text-soft active:bg-gray-100"
            aria-label="Cerrar"
            @click="cerrarMenu"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="h-5 w-5" v-html="ICONOS.cerrar" />
          </button>
        </div>

        <div class="border-t border-border pt-3">
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
