<script setup>
// Gráfico de barras mensual — genérico, un solo componente reusable en vez
// de reimplementar el mismo SVG en cada pantalla (memory/conventions.md).
// Nace 2026-09-07 (pedido de Federico: "ese gráfico [el del Informe
// Mensual] replicalo en Home") — acá sí es un gráfico VIVO en la app (a
// diferencia del Excel, que lo embebe como imagen fija por una limitación
// real de esa librería, ver excel-informe-mensual.js).
//
// Un solo eje, una sola serie por instancia (dataviz skill: "dos medidas de
// escala distinta -> dos gráficos" — Asfalto en tn y Hormigón en m³ NUNCA
// comparten un eje, ver DashboardView.vue: se usa esta misma instancia una
// vez para cada uno, con su propio color/unidad). Serie única -> sin
// leyenda (el título ya dice qué se grafica). Orden CRONOLÓGICO (izquierda
// a derecha) — a diferencia de la tabla del Informe Mensual, que va al
// revés a pedido de Federico: acá es una tendencia en el tiempo, se lee de
// izquierda a derecha.
//
// Marcas: barra con extremo redondeado (4px equivalente) y base cuadrada,
// gridlines finas recesivas, tooltip por barra en hover Y foco (teclado),
// vista de tabla como alternativa accesible — mismo criterio que
// `references/marks-and-anatomy.md`/`interaction.md` del skill de dataviz.
import { computed, ref } from 'vue'

const props = defineProps({
  titulo: { type: String, required: true },
  filas: { type: Array, required: true }, // [{ mes: 'Enero 2026', valor: 123.4 }]
  color: { type: String, default: '#7B2F8E' },
  unidad: { type: String, default: '' },
})

const ANCHO = 600
const ALTO = 200
const MARGEN = { top: 14, right: 8, bottom: 24, left: 38 }
const anchoGrafico = ANCHO - MARGEN.left - MARGEN.right
const altoGrafico = ALTO - MARGEN.top - MARGEN.bottom

const mostrarTabla = ref(false)
const indiceActivo = ref(null)

function formatearValor(v) {
  return v.toLocaleString('es-AR', { maximumFractionDigits: 1 })
}

/** Path SVG de una barra con esquinas redondeadas arriba, base cuadrada (marks-and-anatomy.md). */
function pathBarraRedondeada(x, yTop, ancho, alto, radio) {
  if (alto <= 0) return ''
  const r = Math.min(radio, ancho / 2, alto)
  const yBase = yTop + alto
  return `M${x},${yBase} L${x},${yTop + r} Q${x},${yTop} ${x + r},${yTop} L${x + ancho - r},${yTop} Q${x + ancho},${yTop} ${x + ancho},${yTop + r} L${x + ancho},${yBase} Z`
}

const maxValor = computed(() => Math.max(1, ...props.filas.map((f) => f.valor)) * 1.15)
const escalaY = computed(() => altoGrafico / maxValor.value)

/** 4-5 líneas de referencia horizontales, valores redondos (marks-and-anatomy.md: "round to clean numbers"). */
const gridlines = computed(() => {
  const pasos = 4
  return Array.from({ length: pasos + 1 }, (_, i) => {
    const valor = (maxValor.value * i) / pasos
    return { y: ALTO - MARGEN.bottom - valor * escalaY.value, label: Math.round(valor).toLocaleString('es-AR') }
  })
})

const barras = computed(() => {
  const n = props.filas.length || 1
  const anchoSlot = anchoGrafico / n
  const anchoBarra = Math.min(30, anchoSlot * 0.55)
  return props.filas.map((f, i) => {
    const centroX = MARGEN.left + i * anchoSlot + anchoSlot / 2
    const altoBarra = f.valor * escalaY.value
    const yTop = ALTO - MARGEN.bottom - altoBarra
    return {
      ...f,
      mesCorto: f.mes.split(' ')[0].slice(0, 3),
      valorLabel: `${formatearValor(f.valor)} ${props.unidad}`,
      centroX,
      path: pathBarraRedondeada(centroX - anchoBarra / 2, yTop, anchoBarra, altoBarra, 4),
      // Hit target más ancho que la barra en sí (interaction.md: "bigger than the mark").
      hitX: MARGEN.left + i * anchoSlot,
      hitWidth: anchoSlot,
    }
  })
})

/** Posición del tooltip como % del contenedor — funciona sea cual sea el ancho real renderizado del SVG responsive. */
const estiloTooltip = computed(() => {
  if (indiceActivo.value == null) return {}
  const b = barras.value[indiceActivo.value]
  return { left: `${(b.centroX / ANCHO) * 100}%`, top: `${(MARGEN.top / ALTO) * 100}%` }
})
</script>

<template>
  <div>
    <div class="mb-1.5 flex items-center justify-between gap-2">
      <p class="text-[11px] font-semibold uppercase tracking-wide text-text-soft">{{ titulo }}</p>
      <button
        type="button"
        class="shrink-0 text-xs font-semibold text-vialtec hover:underline"
        @click="mostrarTabla = !mostrarTabla"
      >
        {{ mostrarTabla ? 'Ver gráfico' : 'Ver tabla' }}
      </button>
    </div>

    <p v-if="!filas.length" class="py-6 text-center text-sm text-text-soft">Sin datos para mostrar.</p>

    <!-- Vista de tabla (interaction.md/components.md: alternativa accesible, siempre disponible). -->
    <div v-else-if="mostrarTabla" class="max-h-48 overflow-y-auto rounded-lg border border-border">
      <table class="w-full text-xs">
        <thead class="sticky top-0 bg-gray-50 text-text-soft">
          <tr>
            <th class="px-2.5 py-1.5 text-left font-semibold">Mes</th>
            <th class="px-2.5 py-1.5 text-right font-semibold">{{ unidad }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="f in filas" :key="f.mes" class="border-t border-border">
            <td class="px-2.5 py-1.5 text-text-mid">{{ f.mes }}</td>
            <td class="px-2.5 py-1.5 text-right font-semibold text-text">{{ formatearValor(f.valor) }}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Gráfico -->
    <div v-else class="relative">
      <svg :viewBox="`0 0 ${ANCHO} ${ALTO}`" class="w-full" role="img" :aria-label="`${titulo}: gráfico de barras por mes, en ${unidad}`">
        <g v-for="(g, i) in gridlines" :key="i">
          <line :x1="MARGEN.left" :x2="ANCHO - MARGEN.right" :y1="g.y" :y2="g.y" stroke="#EAECF0" stroke-width="1" />
          <text :x="MARGEN.left - 6" :y="g.y + 3" text-anchor="end" font-size="9" fill="#98A2B3">{{ g.label }}</text>
        </g>

        <g v-for="(b, i) in barras" :key="b.mes">
          <path :d="b.path" :fill="color" :opacity="indiceActivo === i ? 1 : 0.85" />
          <text :x="b.centroX" :y="ALTO - MARGEN.bottom + 13" text-anchor="middle" font-size="9" fill="#667085">
            {{ b.mesCorto }}
          </text>
          <!-- Hit target invisible, más ancho que la barra — el mark es el target (interaction.md). -->
          <rect
            :x="b.hitX"
            :y="MARGEN.top"
            :width="b.hitWidth"
            :height="altoGrafico"
            fill="transparent"
            tabindex="0"
            role="button"
            :aria-label="`${b.mes}: ${b.valorLabel}`"
            style="cursor: pointer; outline: none"
            @mouseenter="indiceActivo = i"
            @mouseleave="indiceActivo = null"
            @focus="indiceActivo = i"
            @blur="indiceActivo = null"
          />
        </g>

        <line
          :x1="MARGEN.left"
          :x2="ANCHO - MARGEN.right"
          :y1="ALTO - MARGEN.bottom"
          :y2="ALTO - MARGEN.bottom"
          stroke="#374151"
          stroke-width="1"
        />
      </svg>

      <div
        v-if="indiceActivo != null"
        class="pointer-events-none absolute -translate-x-1/2 -translate-y-full whitespace-nowrap rounded-lg border border-border bg-white px-2.5 py-1.5 text-xs shadow-md"
        :style="estiloTooltip"
      >
        <p class="font-semibold text-text">{{ barras[indiceActivo].valorLabel }}</p>
        <p class="text-text-soft">{{ barras[indiceActivo].mes }}</p>
      </div>
    </div>
  </div>
</template>
