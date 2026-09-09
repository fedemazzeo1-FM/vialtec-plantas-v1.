<script setup>
// "Slip" imprimible de un despacho ya cerrado — Logica sis. plantas v1.rtf
// §4.5: "muestra un slip imprimible con datos del pedido, firma de
// responsable de planta y firma del encargado." Una sola copia (a
// diferencia del vale de báscula, que sí duplica planta/chofer — ver
// ValeImprimible.vue), misma mecánica de impresión (.imprimible + @page en
// src/assets/main.css, botón "Imprimir" -> window.print()).
//
// 2026-09-03 noche (corrección urgente de Federico): se sacó el desglose de
// "Cargas" (una línea por camión, hasta 18+ líneas en despachos con muchos
// viajes) — desbordaba a varias hojas al imprimir. Igual que el remito de
// báscula (ValeImprimible.vue modo "remito"), ahora muestra solo el
// ACUMULADO TOTAL + la fórmula/mezcla, sin desglose. El detalle camión por
// camión sigue disponible en pantalla vía el botón "Detalle de cargas" de
// DespachosView.vue (modal aparte, no impreso) — no se perdió el dato, solo
// se sacó de este documento imprimible.

import { computed } from 'vue'
import logoVialtec from '@/assets/img/logo-vialtec.png'

const props = defineProps({
  pedido: { type: Object, required: true },
  obraNombre: { type: String, default: '' },
  formulaNombre: { type: String, default: '' },
  cargas: { type: Array, default: () => [] },
})

function formatFecha(iso) {
  if (!iso) return '—'
  return new Date(`${iso}T00:00:00`).toLocaleDateString('es-AR')
}

function unidad(tipo) {
  return tipo === 'hormigon' ? 'm³' : 'tn'
}

// Fix (Federico, 2026-09-09): el remito salía siempre "—". `pedido.nro_remito_global`
// es un campo ÚNICO opcional para todo el despacho (solo asfalto lo pide, ver
// PedidosView.vue "N° de remito (opcional)") — nunca existió para hormigón:
// ahí el remito es OBLIGATORIO pero se carga por carga/mixer
// (`plantas_cargas_hormigon.numero_remito`, uno por camión), y esta vista
// nunca leía el prop `cargas` (lo recibía, pero el template no lo usaba en
// ningún lado). Fallback solo para hormigón — en asfalto `numeroRemitoOVale`
// de una carga es el N° DE VALE (ya se muestra aparte, línea de abajo), no
// un remito, así que no corresponde usarlo acá. Si hay más de un mixer con
// remito distinto en el mismo despacho, se listan todos separados por coma.
const numeroRemitoMostrar = computed(() => {
  if (props.pedido.nro_remito_global) return props.pedido.nro_remito_global
  if (props.pedido.tipo !== 'hormigon') return null
  const deCargas = [...new Set(props.cargas.map((c) => c.numeroRemitoOVale).filter(Boolean))]
  return deCargas.length ? deCargas.join(', ') : null
})
</script>

<template>
  <div class="border border-gray-300 p-6 text-sm text-gray-800">
    <div class="mb-4 flex items-start justify-between border-b border-gray-300 pb-3">
      <img :src="logoVialtec" alt="VIAL-TEC S.A." class="h-12 w-auto" />
      <div class="text-right">
        <p class="text-lg font-bold">Remito de despacho</p>
        <p class="text-gray-500">N° remito: {{ numeroRemitoMostrar || '—' }}</p>
        <p v-if="pedido.tipo === 'asfalto'" class="text-gray-500">N° vale: {{ pedido.nro_vale_global || '—' }}</p>
      </div>
    </div>

    <div class="grid grid-cols-2 gap-x-6 gap-y-2">
      <p><span class="text-gray-500">Fecha:</span> {{ formatFecha(pedido.fecha_programada) }}</p>
      <p><span class="text-gray-500">Obra / Cliente:</span> {{ obraNombre || '—' }}</p>
      <p><span class="text-gray-500">Mezcla:</span> {{ formulaNombre || '—' }}</p>
      <p><span class="text-gray-500">Encargado:</span> {{ pedido.encargado || '—' }}</p>
      <p><span class="text-gray-500">Pedido:</span> {{ pedido.cantidad_solicitada }} {{ unidad(pedido.tipo) }}</p>
      <p><span class="text-gray-500">Real:</span> {{ pedido.cantidad_despachada }} {{ unidad(pedido.tipo) }}</p>
    </div>

    <div class="mt-4 border-t border-gray-300 pt-3">
      <p class="text-base font-semibold">
        Total despachado: {{ pedido.cantidad_despachada }} {{ unidad(pedido.tipo) }}
      </p>
    </div>

    <div class="mt-10 grid grid-cols-2 gap-8 text-xs text-gray-500">
      <p>Firma responsable de planta: ______________________</p>
      <p>Firma del encargado: ______________________</p>
    </div>
  </div>
</template>
