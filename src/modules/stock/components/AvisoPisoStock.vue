<script setup>
// Aviso fijo abajo a la derecha cuando un despacho o una corrección no pudo
// descontar todo lo que pedía la fórmula porque el stock llegó a 0 (ver
// useAvisoPisoStock.js). Se cierra a mano: es para que alguien lo lea.
import { useAvisoPisoStock } from '@/modules/stock/composables/useAvisoPisoStock'

const { avisos, cerrarAviso } = useAvisoPisoStock()

const kg = (n) => n.toLocaleString('es-AR', { maximumFractionDigits: 2 })
</script>

<template>
  <div v-if="avisos.length" class="fixed bottom-20 right-4 z-50 flex max-w-sm flex-col gap-2 md:bottom-4">
    <div
      v-for="aviso in avisos"
      :key="aviso.pedidoId"
      role="alert"
      class="rounded-lg border border-warning/30 bg-warning-light px-4 py-3 text-sm text-warning shadow-sm"
    >
      <div class="flex items-start justify-between gap-3">
        <p class="font-semibold">Stock insuficiente{{ aviso.pedido ? ` — ${aviso.pedido}` : '' }}</p>
        <button type="button" class="-mr-1 text-warning/70 hover:text-warning" aria-label="Cerrar aviso" @click="cerrarAviso(aviso.pedidoId)">✕</button>
      </div>
      <ul class="mt-1 space-y-0.5">
        <li v-for="r in aviso.recortes" :key="r.material">
          {{ r.material }}: la fórmula pedía {{ kg(r.solicitadoKg) }} kg y solo se descontaron {{ kg(r.aplicadoKg) }} kg (quedó en 0).
        </li>
      </ul>
      <p class="mt-1 text-xs">Revisá la fórmula y el stock (relevamiento) de ese material.</p>
    </div>
  </div>
</template>
