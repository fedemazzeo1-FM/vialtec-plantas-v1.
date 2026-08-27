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
defineProps({
  columns: { type: Array, required: true },
  rows: { type: Array, default: () => [] },
  page: { type: Number, default: null },
  pageSize: { type: Number, default: null },
  total: { type: Number, default: null },
})

defineEmits(['update:page'])
</script>

<template>
  <div class="overflow-x-auto">
    <table class="min-w-full divide-y divide-gray-200 text-sm">
      <thead>
        <tr>
          <th
            v-for="col in columns"
            :key="col.key"
            class="px-3 py-2 text-left font-medium text-gray-500"
          >
            {{ col.label }}
          </th>
        </tr>
      </thead>
      <tbody class="divide-y divide-gray-100">
        <tr v-for="(row, i) in rows" :key="row.id ?? i">
          <td v-for="col in columns" :key="col.key" class="px-3 py-2 align-middle">
            <slot :name="`cell-${col.key}`" :row="row" :index="i">
              {{ col.format ? col.format(row[col.key], row) : row[col.key] }}
            </slot>
          </td>
        </tr>
      </tbody>
    </table>

    <div v-if="total != null" class="mt-3 flex items-center justify-between text-xs text-gray-500">
      <p>
        Mostrando {{ rows.length ? (page - 1) * pageSize + 1 : 0 }}–{{ Math.min(page * pageSize, total) }}
        de {{ total }}
      </p>
      <div class="flex items-center gap-2">
        <button
          type="button"
          class="rounded px-2 py-1 hover:bg-gray-100 disabled:opacity-40"
          :disabled="page <= 1"
          @click="$emit('update:page', page - 1)"
        >
          ‹ Anterior
        </button>
        <span>Página {{ page }} de {{ Math.max(1, Math.ceil(total / pageSize)) }}</span>
        <button
          type="button"
          class="rounded px-2 py-1 hover:bg-gray-100 disabled:opacity-40"
          :disabled="page * pageSize >= total"
          @click="$emit('update:page', page + 1)"
        >
          Siguiente ›
        </button>
      </div>
    </div>
  </div>
</template>
