<script setup>
// Reporte ejecutivo mensual para el cuerpo del mail (2026-10-01, pedido de
// Federico: reemplaza las capturas de pantalla que se pegaban a mano). Tres
// piezas independientes, cada una con su propio encabezado, pensadas para
// rasterizarse a PNG (src/services/imagen-reporte.js) y pegarse en el mail:
//   1. Despachos por obra del mes (todo lo que salió de las plantas: obras y
//      ventas externas, discriminado por tipo de producto).
//   2. Resumen anual acumulado, mes a mes.
//   3. Gráfico de producción mensual (todos los tipos en un solo cuadro).
//
// Puramente presentacional: recibe los mismos datos que ya arman el Resumen
// por obra de Despachos y el Excel del informe mensual. Ancho fijo y sin
// nada de la interfaz (menús, botones), para que la imagen salga igual en
// cualquier pantalla. El gráfico está hecho con divs, no con SVG/canvas:
// html2canvas los rasteriza sin sorpresas.

import { computed } from 'vue'
import logoVialtec from '@/assets/img/logo-vialtec.png'
import { LISTA_TIPOS_PRODUCTO, sumarTotales } from '@/config/tipos-producto'

const props = defineProps({
  mesLabel: { type: String, required: true }, // 'Septiembre 2026'
  // [{ nombre, cantidadDespachos, asfaltoTn, hormigonM3, mezclaCementoTn }]
  obras: { type: Array, default: () => [] },
  // { filas: [{ mes, ...totales }], totalAcumulado, anio } — fetchResumenAnual()
  resumenAnual: { type: Object, required: true },
})

const ANCHO_PIEZA = 900
const ALTO_GRAFICO = 260

// Colores de serie: los mismos del gráfico del Excel del informe mensual
// (violeta claro hormigón / violeta asfalto), para que mail y adjunto se
// vean como el mismo informe. Un tipo sin color propio usa el de la config.
const COLOR_SERIE = { hormigonM3: '#C4B5FD', asfaltoTn: '#7C3AED' }
const colorDe = (tipo) => COLOR_SERIE[tipo.total] ?? tipo.color

function numero(valor, decimales = 1) {
  return (Number(valor) || 0).toLocaleString('es-AR', { minimumFractionDigits: decimales, maximumFractionDigits: decimales })
}

const fechaGeneracion = new Date().toLocaleDateString('es-AR')

/** Redondea hacia arriba a 1, 1,5, 2, 2,5, 5 o 10 × 10ⁿ. */
function pasoRedondo(valor) {
  const base = 10 ** Math.floor(Math.log10(valor))
  const candidato = [1, 1.5, 2, 2.5, 5, 10].find((m) => m * base >= valor)
  return candidato * base
}

// --- Pieza 1: despachos por obra -------------------------------------------

const tarjetas = computed(() =>
  props.obras.map((o) => ({
    nombre: o.nombre,
    cantidadDespachos: o.cantidadDespachos,
    lineas: LISTA_TIPOS_PRODUCTO.filter((t) => (Number(o[t.total]) || 0) > 0).map((t) => ({
      id: t.id,
      valor: numero(o[t.total]),
      unidad: t.unidadLabel,
      nombre: t.nombre.toLowerCase(),
      color: colorDe(t),
    })),
  }))
)

const totalMes = computed(() => {
  const totales = sumarTotales(...props.obras)
  return {
    despachos: props.obras.reduce((acc, o) => acc + (o.cantidadDespachos || 0), 0),
    lineas: LISTA_TIPOS_PRODUCTO.filter((t) => t.siempreVisible || totales[t.total] > 0).map((t) => ({
      id: t.id,
      texto: `${numero(totales[t.total])} ${t.unidadLabel}`,
      nombre: t.nombre,
    })),
  }
})

// --- Piezas 2 y 3: resumen anual -------------------------------------------

// Tipos con columna/serie: los fijos más cualquier otro con algo en el año.
const tiposAnual = computed(() =>
  LISTA_TIPOS_PRODUCTO.filter((t) => t.siempreVisible || (Number(props.resumenAnual.totalAcumulado?.[t.total]) || 0) > 0)
    // Hormigón primero, igual que el Excel del informe.
    .sort((a, b) => a.ordenListado - b.ordenListado)
)

// Más reciente arriba, igual que la hoja "Resumen anual" del Excel.
const filasTabla = computed(() => [...props.resumenAnual.filas].reverse())

const grafico = computed(() => {
  const filas = props.resumenAnual.filas
  const mayor = Math.max(1, ...filas.flatMap((f) => tiposAnual.value.map((t) => Number(f[t.total]) || 0)))
  // Eje con valores redondos (0, 1.500, 3.000…) y aire arriba para la
  // etiqueta de la barra más alta.
  const pasos = 4
  const paso = pasoRedondo((mayor * 1.08) / pasos)
  const maximo = paso * pasos
  return {
    lineas: Array.from({ length: pasos + 1 }, (_, i) => {
      const valor = (maximo * i) / pasos
      return { etiqueta: Math.round(valor).toLocaleString('es-AR'), bottom: (valor / maximo) * ALTO_GRAFICO }
    }),
    meses: filas.map((f) => ({
      mes: f.mes.slice(0, 3),
      barras: tiposAnual.value.map((t) => {
        const valor = Number(f[t.total]) || 0
        return {
          id: t.id,
          color: colorDe(t),
          alto: Math.round((valor / maximo) * ALTO_GRAFICO),
          etiqueta: valor > 0 ? Math.round(valor).toLocaleString('es-AR') : '',
        }
      }),
    })),
  }
})
</script>

<template>
  <div>
    <!-- Pieza 1: despachos por obra -->
    <section data-pieza="obras" class="bg-white p-8 text-text" :style="{ width: ANCHO_PIEZA + 'px' }">
      <header class="mb-5 flex items-center justify-between border-b-2 border-vialtec pb-4">
        <div>
          <p class="text-[11px] font-semibold uppercase tracking-widest text-text-soft">Informe mensual de producción</p>
          <h2 class="mt-1 text-2xl font-extrabold">Despachos por obra — {{ mesLabel }}</h2>
        </div>
        <img :src="logoVialtec" alt="VialTec" class="h-11" />
      </header>

      <div class="grid grid-cols-3 gap-3">
        <div
          v-for="t in tarjetas"
          :key="t.nombre"
          class="rounded-lg border border-gray-200 border-l-4 border-l-vialtec bg-white px-4 py-3"
        >
          <p class="text-sm font-bold leading-snug">{{ t.nombre }}</p>
          <p v-for="l in t.lineas" :key="l.id" class="mt-1.5 leading-none">
            <span class="text-xl font-extrabold">{{ l.valor }}</span>
            <span class="ml-1 text-xs text-text-soft">{{ l.unidad }} {{ l.nombre }}</span>
          </p>
          <p class="mt-2 text-[11px] text-text-soft">
            {{ t.cantidadDespachos }} despacho{{ t.cantidadDespachos === 1 ? '' : 's' }}
          </p>
        </div>
      </div>
      <p v-if="!tarjetas.length" class="py-6 text-center text-sm text-text-soft">Sin despachos en el mes.</p>

      <div class="mt-5 flex items-center justify-between rounded-lg bg-vialtec px-5 py-3 text-white">
        <p class="text-xs font-semibold uppercase tracking-widest">Total del mes</p>
        <div class="flex items-baseline gap-6">
          <p v-for="l in totalMes.lineas" :key="l.id" class="text-right leading-tight">
            <span class="block text-[10px] uppercase tracking-wide opacity-80">{{ l.nombre }}</span>
            <span class="text-lg font-extrabold">{{ l.texto }}</span>
          </p>
          <p class="text-right leading-tight">
            <span class="block text-[10px] uppercase tracking-wide opacity-80">Despachos</span>
            <span class="text-lg font-extrabold">{{ totalMes.despachos }}</span>
          </p>
        </div>
      </div>

      <p class="mt-4 text-[10px] text-text-soft">VialTec S.A. — Plantas de Producción · Generado el {{ fechaGeneracion }}</p>
    </section>

    <!-- Pieza 2: resumen anual acumulado -->
    <section data-pieza="anual" class="bg-white p-8 text-text" :style="{ width: ANCHO_PIEZA + 'px' }">
      <header class="mb-5 flex items-center justify-between border-b-2 border-vialtec pb-4">
        <div>
          <p class="text-[11px] font-semibold uppercase tracking-widest text-text-soft">Informe mensual de producción</p>
          <h2 class="mt-1 text-2xl font-extrabold">Resumen anual — Enero a {{ mesLabel }}</h2>
        </div>
        <img :src="logoVialtec" alt="VialTec" class="h-11" />
      </header>

      <table class="w-full border-collapse text-sm">
        <thead>
          <tr class="bg-vialtec text-white">
            <th class="px-4 py-2.5 text-left text-xs font-semibold tracking-wide">Mes</th>
            <th v-for="t in tiposAnual" :key="t.id" class="px-4 py-2.5 text-right text-xs font-semibold tracking-wide">
              {{ t.nombre }} ({{ t.unidadLabel }})
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(f, i) in filasTabla" :key="f.mes" :class="i % 2 === 1 ? 'bg-gray-50' : 'bg-white'">
            <td class="border-b border-gray-200 px-4 py-2 font-semibold">{{ f.mes }}</td>
            <td v-for="t in tiposAnual" :key="t.id" class="border-b border-gray-200 px-4 py-2 text-right">
              {{ f[t.total] ? numero(f[t.total]) : '—' }}
            </td>
          </tr>
        </tbody>
        <tfoot>
          <tr class="bg-gray-100 font-extrabold">
            <td class="border-t-2 border-vialtec px-4 py-2.5 text-xs uppercase tracking-wide">Total acumulado</td>
            <td v-for="t in tiposAnual" :key="t.id" class="border-t-2 border-vialtec px-4 py-2.5 text-right">
              {{ numero(resumenAnual.totalAcumulado[t.total]) }} {{ t.unidadLabel }}
            </td>
          </tr>
        </tfoot>
      </table>

      <p class="mt-4 text-[10px] text-text-soft">VialTec S.A. — Plantas de Producción · Generado el {{ fechaGeneracion }}</p>
    </section>

    <!-- Pieza 3: gráfico de producción mensual -->
    <section data-pieza="grafico" class="bg-white p-8 text-text" :style="{ width: ANCHO_PIEZA + 'px' }">
      <header class="mb-5 flex items-center justify-between border-b-2 border-vialtec pb-4">
        <div>
          <p class="text-[11px] font-semibold uppercase tracking-widest text-text-soft">Informe mensual de producción</p>
          <h2 class="mt-1 text-2xl font-extrabold">Producción mensual — {{ resumenAnual.anio }}</h2>
        </div>
        <img :src="logoVialtec" alt="VialTec" class="h-11" />
      </header>

      <div class="mb-3 flex justify-end gap-5 text-xs text-text-mid">
        <span v-for="t in tiposAnual" :key="t.id" class="flex items-center gap-1.5">
          <span class="inline-block h-3 w-3 rounded-sm" :style="{ background: colorDe(t) }"></span>
          {{ t.nombre }} ({{ t.unidadLabel }})
        </span>
      </div>

      <div class="flex">
        <!-- Eje de valores -->
        <div class="relative w-12 shrink-0" :style="{ height: ALTO_GRAFICO + 'px' }">
          <span
            v-for="l in grafico.lineas"
            :key="l.etiqueta"
            class="absolute right-2 text-[10px] leading-none text-text-soft"
            :style="{ bottom: l.bottom - 4 + 'px' }"
          >
            {{ l.etiqueta }}
          </span>
        </div>
        <div class="flex-1">
          <div class="relative border-b border-gray-700" :style="{ height: ALTO_GRAFICO + 'px' }">
            <div
              v-for="l in grafico.lineas"
              :key="l.etiqueta"
              class="absolute left-0 right-0 border-t border-gray-200"
              :style="{ bottom: l.bottom + 'px' }"
            ></div>
            <div class="absolute inset-0 flex">
              <div v-for="m in grafico.meses" :key="m.mes" class="flex min-w-0 flex-1 items-end justify-center gap-1 px-1.5">
                <div v-for="b in m.barras" :key="b.id" class="flex min-w-0 max-w-[28px] flex-1 flex-col items-center justify-end">
                  <span class="mb-1 whitespace-nowrap text-[9px] font-semibold leading-none text-text-mid">{{ b.etiqueta }}</span>
                  <div class="w-full rounded-t-sm" :style="{ height: b.alto + 'px', background: b.color }"></div>
                </div>
              </div>
            </div>
          </div>
          <div class="mt-1.5 flex">
            <span v-for="m in grafico.meses" :key="m.mes" class="flex-1 text-center text-xs text-text-mid">{{ m.mes }}</span>
          </div>
        </div>
      </div>

      <p class="mt-4 text-[10px] text-text-soft">VialTec S.A. — Plantas de Producción · Generado el {{ fechaGeneracion }}</p>
    </section>
  </div>
</template>
