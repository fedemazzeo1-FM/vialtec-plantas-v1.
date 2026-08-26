<script setup>
// Tabla genérica. columns: [{ key, label }]. rows: array de objetos.
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
          <td v-for="col in columns" :key="col.key" class="px-3 py-2">
            {{ row[col.key] }}
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
