<script setup>
// Desplegable "Pedido de Flota" de la puerta de Ingreso (migraciones 79/80).
// Propio y no un <select>: cada opción lleva el N° de pedido chico al final
// (Federico, 26/11), cosa que un <option> no permite. Filas altas para tocar
// con el dedo en la tablet de la balanza.
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'

const props = defineProps({
  modelValue: { type: String, default: '' },
  // [{ item_id, ... }] y una función que devuelve { texto, numero }.
  pedidos: { type: Array, required: true },
  etiqueta: { type: Function, required: true },
  // Elegido solo (un único pedido pendiente de ese material).
  automatico: { type: Boolean, default: false },
})
const emit = defineEmits(['update:modelValue', 'elegido'])

const abierto = ref(false)
const raiz = ref(null)

const elegido = computed(() => props.pedidos.find((p) => p.item_id === props.modelValue) ?? null)

function elegir(id) {
  emit('update:modelValue', id)
  emit('elegido', id)
  abierto.value = false
}

function alClickAfuera(e) {
  if (abierto.value && raiz.value && !raiz.value.contains(e.target)) abierto.value = false
}
onMounted(() => document.addEventListener('pointerdown', alClickAfuera))
onBeforeUnmount(() => document.removeEventListener('pointerdown', alClickAfuera))
</script>

<template>
  <div ref="raiz" class="relative mt-1" @keydown.esc="abierto = false">
    <button
      type="button"
      class="flex w-full items-center justify-between gap-2 rounded-lg border border-border bg-white px-3 py-2 text-left text-sm focus:border-vialtec focus:outline-none"
      :aria-expanded="abierto"
      aria-haspopup="listbox"
      @click="abierto = !abierto"
    >
      <span v-if="elegido" class="flex min-w-0 flex-1 items-baseline justify-between gap-2">
        <span class="truncate text-text">{{ etiqueta(elegido).texto }}</span>
        <span class="shrink-0 text-[11px] text-text-soft">{{ etiqueta(elegido).numero }}</span>
      </span>
      <span v-else class="flex-1 text-text-mid">Sin pedido</span>
      <svg class="h-4 w-4 shrink-0 text-text-soft" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
        <path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.06l3.71-3.83a.75.75 0 111.08 1.04l-4.25 4.39a.75.75 0 01-1.08 0L5.21 8.27a.75.75 0 01.02-1.06z" clip-rule="evenodd" />
      </svg>
    </button>

    <ul
      v-if="abierto"
      role="listbox"
      class="absolute z-20 mt-1 max-h-72 w-full overflow-auto rounded-lg border border-border bg-white py-1 shadow-lg"
    >
      <li
        role="option"
        :aria-selected="!modelValue"
        class="cursor-pointer px-3 py-3 text-sm text-text-mid hover:bg-vialtec-light"
        :class="{ 'bg-vialtec-light': !modelValue }"
        @click="elegir('')"
      >
        Sin pedido
      </li>
      <li
        v-for="p in pedidos"
        :key="p.item_id"
        role="option"
        :aria-selected="p.item_id === modelValue"
        class="flex cursor-pointer items-baseline justify-between gap-3 px-3 py-3 text-sm hover:bg-vialtec-light"
        :class="{ 'bg-vialtec-light font-medium': p.item_id === modelValue }"
        @click="elegir(p.item_id)"
      >
        <span class="text-text">{{ etiqueta(p).texto }}</span>
        <span class="shrink-0 text-[11px] text-text-soft">{{ etiqueta(p).numero }}</span>
      </li>
    </ul>

    <span v-if="automatico && elegido" class="mt-1 block text-xs text-vialtec">
      Elegido solo: es el único pedido pendiente de ese material. Podés cambiarlo.
    </span>
  </div>
</template>
