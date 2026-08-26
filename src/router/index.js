// Ruteo de VialTec Plantas. Cada módulo nuevo agrega sus rutas acá.

import { createRouter, createWebHistory } from 'vue-router'

const routes = [
  {
    // TODO: apuntar a /dashboard cuando exista ese módulo (ver memory/modules-status.md).
    path: '/',
    redirect: '/formulas',
  },
  {
    path: '/formulas',
    name: 'formulas',
    component: () => import('@/views/FormulasView.vue'),
  },
  {
    path: '/maestros',
    name: 'maestros',
    component: () => import('@/views/MaestrosView.vue'),
  },
  // TODO: /dashboard, /pedidos, /plan-semanal, /stock, /despachos, /bascula,
  // /usuarios, /roles, /backup — a medida que se implemente cada módulo
  // (ver memory/modules-status.md).
]

export const router = createRouter({
  history: createWebHistory(),
  routes,
})
