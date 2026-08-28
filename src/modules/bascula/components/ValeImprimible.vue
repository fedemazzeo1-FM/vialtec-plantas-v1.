<script setup>
// Documento imprimible compartido por "Imprimir vale" e "Imprimir remito".
// El wrapper .imprimible (definido en src/assets/main.css) es lo que hace que
// solo esto se vea al imprimir, ocultando el resto de la página/modal.
//
// Formato A4 landscape, DOS copias por página para modo "vale" (planta +
// chofer) — Logica sis. plantas v1.rtf §2.4: "formato A4 landscape, dos
// copias por página (planta y chofer)". El remito sigue siendo una sola
// copia (la spec no pide duplicado ahí). @page va en src/assets/main.css.

import { computed } from 'vue'
import { formatearNumeroVale } from '@/modules/bascula/services/bascula.service'

const props = defineProps({
  vale: { type: Object, required: true },
  obraNombre: { type: String, default: '' },
  mezclaNombre: { type: String, default: '' },
  modo: { type: String, required: true }, // 'vale' | 'remito'
  acumuladoTn: { type: Number, default: null },
})

function formatFecha(iso) {
  const d = new Date(iso)
  return {
    fecha: d.toLocaleDateString('es-AR'),
    hora: d.toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit' }),
  }
}

// Cada copia del vale lleva UNA sola firma, distinta según a quién le queda
// esa copia (ajuste pedido por Federico, 2026-08-28) — no las dos firmas
// genéricas de antes repetidas en ambas copias. El remito sigue siendo una
// sola hoja con las dos firmas (entrega/recibe), no cambia.
const copias = computed(() =>
  props.modo === 'vale'
    ? [
        { titulo: 'Copia planta', firma: 'Firma del Balancero Responsable' },
        { titulo: 'Copia chofer', firma: 'Firma del Chofer que Retira' },
      ]
    : [{ titulo: 'Remito de entrega', firma: null }]
)
</script>

<template>
  <div class="grid grid-cols-1 gap-4" :class="modo === 'vale' ? 'print:grid-cols-2' : ''">
    <div v-for="copia in copias" :key="copia.titulo" class="border border-gray-300 p-6 text-sm text-gray-800">
      <!-- Encabezado: logo a la izquierda, título + copia a la derecha -->
      <div class="mb-4 flex items-start justify-between border-b border-gray-300 pb-3">
        <div>
          <p class="text-lg font-extrabold leading-none text-gray-800">
            VIAL<span class="text-vialtec">-TEC</span> <span class="font-semibold text-gray-400">S.A.</span>
          </p>
          <p class="text-[10px] uppercase tracking-[0.2em] text-gray-400">Obras viales</p>
          <div
            class="mt-1 h-1.5 w-28"
            style="background-color: #7b2f8e; background-image: repeating-linear-gradient(90deg, transparent 0 4px, white 4px 6px)"
          ></div>
        </div>
        <div class="text-right">
          <p class="text-lg font-bold">{{ modo === 'remito' ? 'Remito de entrega' : 'Vale de pesaje' }}</p>
          <p class="text-gray-500">N° {{ formatearNumeroVale(vale.numero_vale) }}</p>
          <p v-if="modo === 'vale'" class="text-xs font-semibold uppercase tracking-wide text-gray-400">{{ copia.titulo }}</p>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-x-6 gap-y-2">
        <p><span class="text-gray-500">Fecha:</span> {{ formatFecha(vale.fecha_pesada).fecha }}</p>
        <p><span class="text-gray-500">Hora:</span> {{ formatFecha(vale.fecha_pesada).hora }}</p>
        <p><span class="text-gray-500">Obra:</span> {{ obraNombre || '—' }}</p>
        <p><span class="text-gray-500">Mezcla:</span> {{ mezclaNombre || '—' }}</p>
        <p><span class="text-gray-500">Patente:</span> {{ vale.patente || '—' }}</p>
        <p><span class="text-gray-500">Chofer:</span> {{ vale.chofer || '—' }}</p>
        <p><span class="text-gray-500">Peso bruto:</span> {{ vale.peso_bruto }} {{ vale.unidad }}</p>
        <p><span class="text-gray-500">Tara:</span> {{ vale.tara }} {{ vale.unidad }}</p>
        <p><span class="text-gray-500">Peso neto:</span> {{ vale.peso_neto }} {{ vale.unidad }}</p>
        <p v-if="vale.temperatura != null"><span class="text-gray-500">Temperatura:</span> {{ vale.temperatura }} °C</p>
      </div>

      <div class="mt-4 border-t border-gray-300 pt-3">
        <p class="text-base font-semibold">
          Acumulado{{ modo === 'remito' ? ' entregado a la obra' : '' }}: {{ acumuladoTn != null ? acumuladoTn.toFixed(2) : '—' }} tn
        </p>
      </div>

      <div class="mt-10 text-xs text-gray-500">
        <p v-if="copia.firma">{{ copia.firma }}: ______________________</p>
        <div v-else class="grid grid-cols-2 gap-8">
          <p>Firma responsable de planta: ______________________</p>
          <p>Firma chofer: ______________________</p>
        </div>
      </div>
    </div>
  </div>
</template>
