<script setup>
// Layout para pantallas de escritorio: sidebar de navegación + <router-view>.
// Las secciones del sidebar agrupan módulos por área (Administración, Operación,
// etc.). Cada módulo nuevo agrega su link acá y su ruta en src/router/index.js.

const secciones = [
  {
    titulo: 'Operación',
    links: [
      { to: '/plan-semanal', label: 'Plan semanal' },
      { to: '/pedidos', label: 'Pedidos' },
    ],
  },
  {
    titulo: 'Administración',
    links: [
      { to: '/formulas', label: 'Fórmulas' },
      { to: '/maestros', label: 'Maestros' },
    ],
  },
]
</script>

<template>
  <div class="flex min-h-screen">
    <aside class="w-60 shrink-0 border-r border-gray-200 bg-white p-4">
      <p class="mb-4 text-lg font-semibold">VialTec Plantas</p>

      <nav class="space-y-4 text-sm">
        <div v-for="seccion in secciones" :key="seccion.titulo">
          <p class="mb-1 px-2 text-xs font-semibold uppercase tracking-wide text-gray-400">
            {{ seccion.titulo }}
          </p>
          <ul class="space-y-1">
            <li v-for="link in seccion.links" :key="link.to">
              <router-link
                :to="link.to"
                class="block rounded px-2 py-1.5 hover:bg-gray-100"
                active-class="bg-gray-100 font-medium"
              >
                {{ link.label }}
              </router-link>
            </li>
          </ul>
        </div>
      </nav>
    </aside>

    <main class="flex-1 p-6">
      <router-view />
    </main>
  </div>
</template>
