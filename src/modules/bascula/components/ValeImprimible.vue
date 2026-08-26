<script setup>
// Documento imprimible compartido por "Imprimir vale" e "Imprimir remito".
// El wrapper .imprimible (definido en src/assets/main.css) es lo que hace que
// solo esto se vea al imprimir, ocultando el resto de la página/modal.

const props = defineProps({
  vale: { type: Object, required: true },
  obraNombre: { type: String, default: '' },
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
</script>

<template>
  <div class="border border-gray-300 p-6 text-sm text-gray-800">
    <!-- Encabezado: título a la izquierda, texto institucional fijo a la derecha -->
    <div class="mb-4 flex items-start justify-between border-b border-gray-300 pb-3">
      <div>
        <p class="text-lg font-bold">{{ modo === 'remito' ? 'Remito de entrega' : 'Vale de pesaje' }}</p>
        <p class="text-gray-500">N° {{ vale.numero_vale }}</p>
      </div>
      <p class="max-w-[45%] text-right text-xs leading-snug text-gray-600">
        Báscula Casilda 80, Modelo FAH 21301, Cert. Calibración N°260409-272
      </p>
    </div>

    <div class="grid grid-cols-2 gap-x-6 gap-y-2">
      <p><span class="text-gray-500">Fecha:</span> {{ formatFecha(vale.fecha_pesada).fecha }}</p>
      <p><span class="text-gray-500">Hora:</span> {{ formatFecha(vale.fecha_pesada).hora }}</p>
      <p><span class="text-gray-500">Obra:</span> {{ obraNombre || '—' }}</p>
      <p><span class="text-gray-500">Patente:</span> {{ vale.patente || '—' }}</p>
      <p><span class="text-gray-500">Chofer:</span> {{ vale.chofer || '—' }}</p>
      <p><span class="text-gray-500">Peso bruto:</span> {{ vale.peso_bruto }} {{ vale.unidad }}</p>
      <p><span class="text-gray-500">Tara:</span> {{ vale.tara }} {{ vale.unidad }}</p>
      <p><span class="text-gray-500">Peso neto:</span> {{ vale.peso_neto }} {{ vale.unidad }}</p>
    </div>

    <div v-if="modo === 'remito'" class="mt-4 border-t border-gray-300 pt-3">
      <p class="text-base font-semibold">
        Acumulado entregado a la obra: {{ acumuladoTn != null ? acumuladoTn.toFixed(2) : '—' }} tn
      </p>
    </div>

    <div class="mt-10 grid grid-cols-2 gap-8 text-xs text-gray-500">
      <p>Firma responsable de planta: ______________________</p>
      <p>Firma chofer: ______________________</p>
    </div>
  </div>
</template>
