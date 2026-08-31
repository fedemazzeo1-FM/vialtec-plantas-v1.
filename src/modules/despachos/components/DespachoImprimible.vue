<script setup>
// "Slip" imprimible de un despacho ya cerrado — Logica sis. plantas v1.rtf
// §4.5: "muestra un slip imprimible con datos del pedido, firma de
// responsable de planta y firma del encargado." Una sola copia (a
// diferencia del vale de báscula, que sí duplica planta/chofer — ver
// ValeImprimible.vue), misma mecánica de impresión (.imprimible + @page en
// src/assets/main.css, botón "Imprimir" -> window.print()).

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
</script>

<template>
  <div class="border border-gray-300 p-6 text-sm text-gray-800">
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
        <p class="text-lg font-bold">Remito de despacho</p>
        <p class="text-gray-500">N° remito: {{ pedido.nro_remito_global || '—' }}</p>
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

    <div v-if="cargas.length" class="mt-4 border-t border-gray-300 pt-3">
      <p class="mb-1 text-xs font-semibold uppercase tracking-wide text-gray-400">Cargas</p>
      <p v-for="(carga, i) in cargas" :key="carga.id" class="text-gray-700">
        Carga {{ i + 1 }} — {{ carga.patente || 'sin patente' }} — {{ carga.cantidad }} {{ unidad(pedido.tipo) }}
        <span class="text-gray-500">— {{ pedido.tipo === 'hormigon' ? 'Remito' : 'Vale' }}: {{ carga.numeroRemitoOVale || '—' }}</span>
      </p>
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
