// Ruteo de VialTec Plantas. Cada módulo nuevo agrega sus rutas acá.
// Guard global: exige sesión (excepto /login) y filtra por rol vía
// auth.store.js#puedeVerTab (memory/business-rules.md, 7 roles).

import { createRouter, createWebHistory, START_LOCATION } from 'vue-router'
import { useAuthStore } from '@/stores/auth.store'
import { esPantallaMobile } from '@/composables/useBreakpoint'
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

router.beforeEach(async (to, from) => {
  const auth = useAuthStore()

  if (!auth.listo) {
    await auth.restaurarSesion()
  }

  if (to.meta.publica) {
    // Ya logueado y yendo a /login -> mandarlo a su ruta de aterrizaje
    // (2026-09-14: antes era siempre 'dashboard' a ciegas — un rol sin
    // permiso de ver Home, como balancero, quedaba en loop infinito con el
    // chequeo de tab de abajo y la pantalla se veía congelada en /login.
    // 2026-09-16: la ruta de aterrizaje también prioriza Pedidos en mobile —
    // ver auth.store.js#rutaInicioSesion).
    if (auth.estaLogueado && to.name === 'login') return { name: auth.rutaInicioSesion(esPantallaMobile()) }
    return true
  }

  if (!auth.estaLogueado) {
    return { name: 'login', query: { redirect: to.fullPath } }
  }

  // Primer aterrizaje real de la sesión en esta carga de página (F5 en "/",
  // apertura directa del dominio/PWA) — `from === START_LOCATION` distingue
  // esto de un click explícito en "Home" ya con la sesión andando, que
  // siempre debe llevar a Home sin importar el dispositivo. En mobile,
  // Pedidos tiene prioridad sobre Home acá (2026-09-16, pedido de Federico:
  // la operativa de campo vive en Pedidos) — ver auth.store.js#rutaInicioSesion.
  if (from === START_LOCATION && to.name === 'dashboard' && esPantallaMobile() && auth.puedeVerTab('pedidos')) {
    return { name: 'pedidos' }
  }

  if (to.meta.tab && !auth.puedeVerTab(to.meta.tab)) {
    // Mismo fallback que arriba — nunca asumir 'dashboard' como destino
    // seguro, un rol sin permiso ahí loopearía contra este mismo chequeo.
    return { name: auth.rutaInicioSesion(esPantallaMobile()) }
  }

  return true
})
