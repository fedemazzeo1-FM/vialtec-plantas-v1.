<script setup>
// Tabla genérica. columns: [{ key, label, format? }]. rows: array de objetos.
//
// Por columna, el caller puede pasar:
//  - un slot con scope `#cell-<key>="{ row, index }"` para renderizar contenido
//    custom (inputs editables, badges, botones de acción, etc.) — esto es lo
//    que habilita edición inline sin duplicar el componente de tabla.
//  - `col.format(value, row)` para formatear el valor por defecto sin slot.
// Si no se pasa ninguno de los dos, se muestra `row[col.key]` tal cual.
//
// Paginación server-side (opcional): si el caller pasa `total`, se muestra un
// footer con "mostrando X–Y de Z" + Anterior/Siguiente, y `rows` se asume que
// ya es SOLO la página actual (no todo el dataset) — el caller es responsable
// de volver a pedir la página al service (ver src/services/fetch-paginado.js
// #fetchPagina) cuando escucha `update:page`. Si no se pasa `total`, la tabla
// se comporta exactamente igual que antes (sin footer, sin paginar).
//
// Modo mobile (roadmap Mobile, memory/pending.md 2026-09-02): bajo el
// breakpoint (768px, useBreakpoint()) cada fila se renderiza como una card
// (label: valor apilado) en vez de forzar scroll horizontal de la tabla —
// mismo dato, mismos slots `#cell-<key>`, ningún caller necesita cambiar
// nada. La columna `key === 'acciones'` (convención ya usada en todo el
// código para la última columna de botones) se separa del resto: va sin
// label, ancho completo, con un separador arriba — es donde viven los
// VButton de la fila, que ya tienen área táctil ~44px (ver VButton.vue).
//
// `rowClass` (opcional, 2026-09-04 — Báscula, memory/pending.md): función
// `(row) => string` con clases extra por fila (ej. franja de color por
// tipo_vale, réplica del legado). Se aplica tanto en la card mobile como en
// el <tr> desktop — un solo lugar para no duplicar el criterio de color por
// breakpoint. Devuelve '' o algo falsy si la fila no necesita clase extra.
//
// `col.secundaria: true` (opcional, 2026-09-07 — roadmap mobile, pedido de
// Federico: "menos sobrecarga de datos secundarios" en listados de tablas
// densas como el historial de Báscula, 14 columnas). Solo afecta el modo
// card mobile: esas columnas quedan colapsadas detrás de un toggle "Ver
// más"/"Ver menos" por card en vez de mostrarse siempre — mismo dato,
// ningún caller pierde información, solo cambia qué se ve por default en
// pantalla chica. Sin ninguna columna marcada `secundaria`, el comportamiento
// es idéntico a antes (todas las columnas siempre visibles). Desktop no se
// toca — ahí siempre se ven todas las columnas, como siempre.
import { reactive } from 'vue'
import { useBreakpoint } from '@/composables/useBreakpoint'

defineProps({
  columns: { type: Array, required: true },
  rows: { type: Array, default: () => [] },
  page: { type: Number, default: null },
  pageSize: { type: Number, default: null },
  total: { type: Number, default: null },
  rowClass: { type: Function, default: null },
})

defineEmits(['update:page'])

const { esMobile } = useBreakpoint()

const filasExpandidas = reactive(new Set())
function toggleExpandida(key) {
  if (filasExpandidas.has(key)) filasExpandidas.delete(key)
  else filasExpandidas.add(key)
}
</script>

<template>
  <div>
    <!-- Mobile: cards apiladas -->
    <div v-if="esMobile" class="space-y-3">
      <div
        v-for="(row, i) in rows"
        :key="row.id ?? i"
        class="rounded-xl border border-border bg-white p-3 shadow-sm"
        :class="rowClass?.(row)"
      >
        <div class="space-y-1.5">
          <div
            v-for="col in columns.filter((c) => c.key !== 'acciones' && !c.secundaria)"
            :key="col.key"
            class="flex items-start justify-between gap-3 text-sm"
          >
            <span class="shrink-0 text-xs font-semibold uppercase tracking-wide text-text-soft">{{ col.label }}</span>
            <span class="text-right text-text">
              <slot :name="`cell-${col.key}`" :row="row" :index="i">
                {{ col.format ? col.format(row[col.key], row) : row[col.key] }}
              </slot>
            </span>
          </div>
        </div>

        <!-- Columnas secundarias: colapsadas por default (menos ruido en la
             primera mirada), un toggle por card las despliega sin perder el
             dato — nunca se ocultan del todo. -->
        <template v-if="columns.some((c) => c.secundaria)">
          <button
            type="button"
            class="mt-2 flex min-h-[36px] items-center gap-1 text-xs font-semibold text-vialtec"
            @click="toggleExpandida(row.id ?? i)"
          >
            {{ filasExpandidas.has(row.id ?? i) ? '▴ Ver menos' : '▾ Ver más' }}
          </button>
          <div v-if="filasExpandidas.has(row.id ?? i)" class="mt-1.5 space-y-1.5 border-t border-border pt-2">
            <div
              v-for="col in columns.filter((c) => c.secundaria)"
              :key="col.key"
              class="flex items-start justify-between gap-3 text-sm"
            >
              <span class="shrink-0 text-xs font-semibold uppercase tracking-wide text-text-soft">{{ col.label }}</span>
              <span class="text-right text-text">
                <slot :name="`cell-${col.key}`" :row="row" :index="i">
                  {{ col.format ? col.format(row[col.key], row) : row[col.key] }}
                </slot>
              </span>
            </div>
          </div>
        </template>

        <div v-if="columns.some((c) => c.key === 'acciones')" class="mt-3 flex flex-wrap gap-2 border-t border-border pt-3">
          <slot name="cell-acciones" :row="row" :index="i" />
        </div>
      </div>
      <p v-if="!rows.length" class="py-2 text-center text-sm text-text-soft">Sin resultados.</p>
    </div>

    <!-- Desktop: tabla clásica -->
    <div v-else class="overflow-x-auto">
      <table class="min-w-full divide-y divide-border text-sm">
        <thead class="bg-gray-50">
          <tr>
            <th
              v-for="col in columns"
              :key="col.key"
              class="px-4 py-3 text-left text-xs font-bold uppercase tracking-wide text-text-soft"
            >
              {{ col.label }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-border">
          <tr
            v-for="(row, i) in rows"
            :key="row.id ?? i"
            class="text-text transition-colors duration-150 hover:bg-gray-50"
            :class="rowClass?.(row)"
          >
            <td v-for="col in columns" :key="col.key" class="px-4 py-3 align-middle">
              <slot :name="`cell-${col.key}`" :row="row" :index="i">
                {{ col.format ? col.format(row[col.key], row) : row[col.key] }}
              </slot>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div v-if="total != null" class="mt-3 flex flex-wrap items-center justify-between gap-2 text-xs text-text-soft">
      <p>
        Mostrando {{ rows.length ? (page - 1) * pageSize + 1 : 0 }}–{{ Math.min(page * pageSize, total) }}
        de {{ total }}
      </p>
      <div class="flex items-center gap-1">
        <button
          type="button"
          class="flex min-h-[44px] items-center rounded px-3 hover:bg-gray-100 disabled:opacity-40"
          :disabled="page <= 1"
          @click="$emit('update:page', page - 1)"
        >
          ‹ Anterior
        </button>
        <span class="px-1">Página {{ page }} de {{ Math.max(1, Math.ceil(total / pageSize)) }}</span>
        <button
          type="button"
          class="flex min-h-[44px] items-center rounded px-3 hover:bg-gray-100 disabled:opacity-40"
          :disabled="page * pageSize >= total"
          @click="$emit('update:page', page + 1)"
        >
          Siguiente ›
        </button>
      </div>
    </div>
  </div>
</template>
