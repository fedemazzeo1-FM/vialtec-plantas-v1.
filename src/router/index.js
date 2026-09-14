// Ruteo de VialTec Plantas. Cada módulo nuevo agrega sus rutas acá.
// Guard global: exige sesión (excepto /login) y filtra por rol vía
// auth.store.js#puedeVerTab (memory/business-rules.md, 7 roles).

import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth.store'
// Import estático (no lazy): App.vue también la usa directo para el gate de
// sesión, así que iba a terminar en el bundle principal de todos modos.
import LoginView from '@/views/LoginView.vue'

const routes = [
  {
    path: '/login',
    name: 'login',
    component: LoginView,
    meta: { publica: true },
  },
  {
    path: '/',
    redirect: '/dashboard',
  },
  {
    path: '/dashboard',
    name: 'dashboard',
    component: () => import('@/views/DashboardView.vue'),
    meta: { tab: 'dashboard' },
  },
  {
    path: '/pedidos',
    name: 'pedidos',
    component: () => import('@/views/PedidosView.vue'),
    meta: { tab: 'pedidos' },
  },
  {
    path: '/plan-semanal',
    name: 'plan-semanal',
    component: () => import('@/views/PlanSemanalView.vue'),
    meta: { tab: 'plan-semanal' },
  },
  {
    path: '/bascula',
    name: 'bascula',
    component: () => import('@/views/BasculaView.vue'),
    meta: { tab: 'bascula' },
  },
  {
    path: '/despachos',
    name: 'despachos',
    component: () => import('@/views/DespachosView.vue'),
    meta: { tab: 'despachos' },
  },
  {
    path: '/formulas',
    name: 'formulas',
    component: () => import('@/views/FormulasView.vue'),
    meta: { tab: 'formulas' },
  },
  {
    path: '/maestros',
    name: 'maestros',
    component: () => import('@/views/MaestrosView.vue'),
    meta: { tab: 'maestros' },
  },
  {
    path: '/stock',
    name: 'stock',
    component: () => import('@/views/StockView.vue'),
    meta: { tab: 'stock' },
  },
  {
    path: '/simulador',
    name: 'simulador',
    component: () => import('@/views/SimuladorView.vue'),
    meta: { tab: 'simulador' },
  },
  {
    path: '/usuarios',
    name: 'usuarios',
    component: () => import('@/views/AdministracionView.vue'),
    meta: { tab: 'usuarios' },
  },
  // TODO: /backup — a medida que se implemente (ver memory/modules-status.md).
]

export const router = createRouter({
  history: createWebHistory(),
  routes,
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()

  if (!auth.listo) {
    await auth.restaurarSesion()
  }

  if (to.meta.publica) {
    // Ya logueado y yendo a /login -> mandarlo a su primera tab disponible
    // (2026-09-14: antes era siempre 'dashboard' a ciegas — un rol sin
    // permiso de ver Home, como balancero, quedaba en loop infinito con el
    // chequeo de tab de abajo y la pantalla se veía congelada en /login. Ver
    // auth.store.js#primeraTabDisponible).
    if (auth.estaLogueado && to.name === 'login') return { name: auth.primeraTabDisponible ?? 'dashboard' }
    return true
  }

  if (!auth.estaLogueado) {
    return { name: 'login', query: { redirect: to.fullPath } }
  }

  if (to.meta.tab && !auth.puedeVerTab(to.meta.tab)) {
    // Mismo fallback que arriba — nunca asumir 'dashboard' como destino
    // seguro, un rol sin permiso ahí loopearía contra este mismo chequeo.
    return { name: auth.primeraTabDisponible ?? 'dashboard' }
  }

  return true
})
