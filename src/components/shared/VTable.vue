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
// TODO: paginación de UI si el caller ya trae los datos paginados desde el
// service (recordar la regla de paginación de Supabase en memory/architecture.md
// — esta tabla no resuelve eso, solo pinta filas que ya le llegan).
defineProps({
  columns: { type: Array, required: true },
  rows: { type: Array, default: () => [] },
})
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
  </div>
</template>
