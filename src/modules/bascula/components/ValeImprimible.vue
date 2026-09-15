<script setup>
// Documento imprimible del "Vale de pesaje" (báscula) — formato A4 LANDSCAPE
// (@page único, margin:0, en src/assets/main.css — corregido 2026-09-03
// noche: la versión de la tarde usaba una "named page" por componente que el
// diálogo de impresión de Chrome no terminó respetando en la práctica, ver
// el comentario en main.css), las 2 copias (Original / Duplicado) LADO A
// LADO en una sola hoja, separadas por una línea de corte VERTICAL punteada
// al medio del ancho — al cortar quedan 2 vales verticales independientes
// (Logica sis. plantas v1.rtf §2.4 pedía esta misma disposición). `h-full`
// en el grid y en cada copia (`flex flex-col` + `mt-auto` en la firma) para
// que ocupen TODO el alto real de la hoja (≈200mm útiles con el padding de
// `.imprimible`), no solo lo que ocupe el contenido — pedido explícito de
// Federico: "aprovechá toda la hoja".
//
// El "remito" (documento fiscal, distinto de este vale de pesaje interno) se
// movió a `src/components/shared/RemitoImprimible.vue` — 2026-09-09, pedido
// explícito de Federico de que Báscula y Despachos impriman EXACTAMENTE el
// mismo documento (antes Despachos tenía su propio slip más simple). Este
// componente quedó 100% dedicado al vale de pesaje.

import { formatearNumeroVale } from '@/modules/bascula/services/bascula.service'
// Logo real (2026-09-01, provisto por Federico) — reemplaza el mockup en
// CSS/texto que se usaba antes (no había forma de bajar el archivo a disco
// en sesiones previas, ver memory/modules-status.md).
import logoVialtec from '@/assets/img/logo-vialtec.png'

const props = defineProps({
  vale: { type: Object, required: true },
  obraNombre: { type: String, default: '' },
  mezclaNombre: { type: String, default: '' },
  // Pedido de venta externa (plantas_pedidos.tipo_pedido = 'venta') vs. obra
  // propia — 2026-09-15, pedido explícito de Federico: el reemplazo por
  // "MEZCLA ASFÁLTICA" aplica SOLO a cliente externo; producción interna
  // (obra) sigue mostrando el nombre real/técnico de la fórmula.
  clienteExterno: { type: Boolean, default: false },
  acumuladoTn: { type: Number, default: null },
})

// Datos del instrumento de pesaje (2026-09-03, pedido textual de Federico:
// "Bascula Casilda 80 tn, modelo Fah 21301, balanza cert calibracion
// n°260409-272") — dato fijo del instrumento: si algún día se recalibra o se
// cambia de báscula, se actualiza acá, no hay tabla para esto (no es un dato
// operativo por vale).
const BALANZA_CERT_CALIBRACION =
  'Báscula Casilda 80 tn, modelo FAH 21301 — balanza cert. calibración N° 260409-272'

function formatFecha(iso) {
  const d = new Date(iso)
  return {
    fecha: d.toLocaleDateString('es-AR'),
    hora: d.toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit' }),
  }
}

// Cada copia del vale lleva UNA sola firma, distinta según a quién le queda
// esa copia (ajuste pedido por Federico, 2026-08-28). Corregido 2026-09-09
// (pedido explícito de Federico: la asignación había quedado invertida
// desde el ajuste de texto de 2026-09-03 tarde) — asignación correcta:
// ORIGINAL "Firma del chofer" / DUPLICADO "Firma del responsable en balanza".
const copiasVale = [
  { titulo: 'Original', firma: 'Firma del chofer' },
  { titulo: 'Duplicado', firma: 'Firma del responsable en balanza' },
]
</script>

<template>
  <!-- Landscape, 2 columnas lado a lado (Original / Duplicado) — línea de
       corte VERTICAL al medio del ancho de la hoja (2026-09-03 tarde).
       Ajuste 2026-09-07 (pedido de Federico: "corto la hoja exactamente a
       la mitad y corto parte de un vale"): verificado con un harness fuera
       de la app (mismo criterio de medición que sesiones anteriores) que el
       centrado en sí ya es matemáticamente exacto (grid de 2 columnas
       iguales, línea de corte a `left-1/2` del mismo contenedor) — lo que
       faltaba era MARGEN DE SEGURIDAD real: con `gap-6` (24px ≈ 6.35mm)
       quedaban solo ~3.17mm de aire a cada lado de la línea antes de tocar
       el borde de cada vale, insuficiente para la imprecisión real de
       imprimir/cortar a mano. `gap-[14mm]` (valor en mm, no en rem, para no
       depender de ningún font-size) duplica eso a 7mm de cada lado —
       verificado que sigue perfectamente centrado (7.00mm y 7.00mm exactos)
       y que ninguna columna se achica lo suficiente como para desbordar
       contenido (pierde <4mm de ancho útil cada una, sigue sobrando lugar
       de sobra para los campos del vale). -->
  <div class="relative grid h-full grid-cols-2 gap-[14mm]">
    <!-- Línea de corte entre copias: visual de "cortar acá" en el medio del
         ancho, mismo criterio que un talonario físico con duplicado, ahora
         vertical en vez de horizontal. -->
    <div class="pointer-events-none absolute inset-y-0 left-1/2 flex -translate-x-1/2 flex-col items-center text-gray-300">
      <span class="text-[10px] leading-none">✂</span>
      <div class="mt-1 w-0 flex-1 border-l border-dashed border-gray-300"></div>
    </div>

    <div
      v-for="copia in copiasVale"
      :key="copia.titulo"
      class="flex h-full flex-col border border-gray-300 p-6 text-base text-gray-800"
    >
      <div class="mb-4 flex items-start justify-between border-b border-gray-300 pb-3">
        <img :src="logoVialtec" alt="VIAL-TEC S.A." class="h-14 w-auto" />
        <div class="text-right">
          <p class="text-2xl font-bold">Vale de pesaje N° {{ formatearNumeroVale(vale.numero_vale) }}</p>
          <p class="text-sm font-semibold uppercase tracking-wide text-gray-400">{{ copia.titulo }}</p>
          <p class="text-[11px] leading-tight text-gray-400">{{ BALANZA_CERT_CALIBRACION }}</p>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-x-6 gap-y-3">
        <p><span class="text-gray-500">Fecha:</span> {{ formatFecha(vale.fecha_pesada).fecha }}</p>
        <p><span class="text-gray-500">Hora:</span> {{ formatFecha(vale.fecha_pesada).hora }}</p>
        <p><span class="text-gray-500">Patente:</span> {{ vale.patente || '—' }}</p>
        <p><span class="text-gray-500">Chofer:</span> {{ vale.chofer || '—' }}</p>
        <!-- Obra: solo tiene sentido para asfalto/egreso de áridos — un
             ingreso de áridos (2026-09-08, pedido de Federico: sumarle el
             botón "Vale") no tiene obra asociada, va con
             Proveedor/Remito/Remito(cantidad) en su lugar. -->
        <p v-if="vale.tipo_vale !== 'ingreso_arido'" class="col-span-2"><span class="text-gray-500">Obra:</span> {{ obraNombre || '—' }}</p>
        <!-- Mezcla (2026-09-15, ajuste explícito de Federico sobre la
             decisión del 2026-09-14): "MEZCLA ASFÁLTICA" genérico SOLO para
             venta a cliente externo (clienteExterno=true, tipo_pedido='venta')
             — producción interna/obra propia sigue mostrando el nombre real
             de la fórmula, igual que siempre mostró este vale antes del
             2026-09-14. Egreso/ingreso de áridos no tienen pedido/fórmula,
             llevan Material (texto libre que cargó el balancero en la
             puerta). -->
        <p v-if="vale.tipo_vale === 'asfalto'" class="col-span-2">
          <span class="text-gray-500">Mezcla:</span> {{ clienteExterno ? 'MEZCLA ASFÁLTICA' : (mezclaNombre || '—') }}
        </p>
        <p v-else class="col-span-2"><span class="text-gray-500">Material:</span> {{ vale.material || '—' }}</p>
        <template v-if="vale.tipo_vale === 'ingreso_arido'">
          <p><span class="text-gray-500">N° Remito:</span> {{ vale.numero_remito_ingreso || '—' }}</p>
          <p>
            <span class="text-gray-500">Cantidad s/remito:</span>
            {{ vale.cantidad_remito_ingreso != null ? Number(vale.cantidad_remito_ingreso).toFixed(2) + ' tn' : '—' }}
          </p>
        </template>
        <p><span class="text-gray-500">Bruto:</span> {{ vale.peso_bruto }} {{ vale.unidad }}</p>
        <p><span class="text-gray-500">Tara:</span> {{ vale.tara }} {{ vale.unidad }}</p>
        <p><span class="text-gray-500">Neto:</span> {{ vale.peso_neto }} {{ vale.unidad }}</p>
        <p v-if="vale.temperatura != null"><span class="text-gray-500">Temp.:</span> {{ vale.temperatura }} °C</p>
      </div>

      <div class="mt-6 border-t border-gray-300 pt-3">
        <p class="text-xl font-bold">Acumulado: {{ acumuladoTn != null ? acumuladoTn.toFixed(2) : '—' }} tn</p>
      </div>

      <div class="mt-auto pt-8 text-sm text-gray-500">
        <p>{{ copia.firma }}: ________________________________</p>
      </div>
    </div>
  </div>
</template>
