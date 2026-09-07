// Config de navegación compartida entre DesktopLayout y MobileLayout
// (memory/conventions.md: lógica compartida entre módulos va en un helper
// común, no duplicada en cada layout) — extraído de DesktopLayout.vue
// 2026-09-02 al construir MobileLayout. Cada módulo nuevo agrega su link acá
// (con su `tab` y su `icon`, ver auth.store.js#puedeVerTab) y su ruta en
// src/router/index.js — un solo lugar para los dos layouts.

export const SECCIONES = [
  {
    // "Home" (2026-09-03, pedido de Federico — antes "Dashboard"): Plan
    // semanal y Pedidos suben acá junto al inicio, son las 3 pantallas de
    // uso diario más frecuente — quedan afuera de "Operación" (que se queda
    // con lo más puntual/operativo del día a día de planta).
    titulo: 'General',
    links: [
      { to: '/dashboard', label: 'Home', tab: 'dashboard', icon: 'grid' },
      { to: '/plan-semanal', label: 'Plan semanal', tab: 'plan-semanal', icon: 'calendario' },
      { to: '/pedidos', label: 'Pedidos', tab: 'pedidos', icon: 'clipboard' },
    ],
  },
  {
    titulo: 'Operación',
    links: [
      { to: '/despachos', label: 'Despachos', tab: 'despachos', icon: 'camion' },
      { to: '/bascula', label: 'Báscula', tab: 'bascula', icon: 'balanza' },
      { to: '/stock', label: 'Stock', tab: 'stock', icon: 'caja' },
      { to: '/simulador', label: 'Simulador', tab: 'simulador', icon: 'capas' },
      { to: '/formulas', label: 'Fórmulas', tab: 'formulas', icon: 'matraz' },
    ],
  },
]

// Sección "Administración" — separada del array de arriba a propósito
// (2026-09-06, pedido de Federico, réplica visual del sidebar de Flota/
// equipos2.vialtec.app): en DesktopLayout.vue se renderiza pegada abajo del
// todo, justo arriba de "Cerrar sesión" (con `mt-auto` empujándola), no
// mezclada con el resto de las secciones que scrollean arriba.
export const SECCION_ADMINISTRACION = {
  titulo: 'Administración',
  links: [
    // Antes "Usuarios y Permisos" — renombrado a "Administración" (tab
    // "usuarios" sin cambios a propósito, es la clave que ya usa
    // PERMISOS_POR_ROL/auth.store.js#puedeVerTab en todos lados; cambiar el
    // string rompería esos chequeos sin ganar nada). Solo aparece para
    // admin: PERMISOS_POR_ROL['admin'].tabs === 'todas' es el único rol que
    // matchea 'usuarios' — el resto no tiene 'usuarios' en su array de
    // tabs, el link se filtra solo y el router bloquea el acceso directo
    // por URL igual (mismo guard genérico de siempre).
    { to: '/usuarios', label: 'Administración', tab: 'usuarios', icon: 'engranaje' },
    { to: '/maestros', label: 'Maestros', tab: 'maestros', icon: 'base-datos' },
  ],
}

// Set mínimo de íconos outline (24x24, stroke-only) — reemplazable por una
// librería de verdad (ej. Heroicons) si en algún momento se agrega como
// dependencia. Markup estático (no viene de datos de usuario ni de DB), no
// hay riesgo de inyección al renderizarlo con v-html.
export const ICONOS = {
  grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  clipboard:
    '<rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 4V3a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v1"/><line x1="8" y1="10" x2="16" y2="10"/><line x1="8" y1="14" x2="16" y2="14"/><line x1="8" y1="18" x2="13" y2="18"/>',
  calendario:
    '<rect x="3" y="5" width="18" height="16" rx="2"/><line x1="16" y1="3" x2="16" y2="7"/><line x1="8" y1="3" x2="8" y2="7"/><line x1="3" y1="10" x2="21" y2="10"/>',
  balanza:
    '<line x1="12" y1="3" x2="12" y2="21"/><line x1="5" y1="7" x2="19" y2="7"/><path d="M5 7l-3 6a3 3 0 0 0 6 0z"/><path d="M19 7l-3 6a3 3 0 0 0 6 0z"/>',
  camion:
    '<rect x="1" y="7" width="13" height="10" rx="1"/><path d="M14 10h4l3 3v4h-7z"/><circle cx="6" cy="19" r="2"/><circle cx="17" cy="19" r="2"/>',
  caja:
    '<path d="M3 8l9-5 9 5-9 5-9-5z"/><path d="M3 8v9l9 5 9-5V8"/><line x1="12" y1="13" x2="12" y2="22"/>',
  capas:
    '<path d="M12 2 2 7l10 5 10-5-10-5z"/><path d="M2 12l10 5 10-5"/><path d="M2 17l10 5 10-5"/>',
  matraz: '<path d="M9 3h6M10 3v5.5L5.5 17a2 2 0 0 0 1.8 3h9.4a2 2 0 0 0 1.8-3L14 8.5V3"/>',
  'base-datos':
    '<ellipse cx="12" cy="5" rx="8" ry="3"/><path d="M4 5v6c0 1.7 3.6 3 8 3s8-1.3 8-3V5"/><path d="M4 11v6c0 1.7 3.6 3 8 3s8-1.3 8-3v-6"/>',
  usuarios:
    '<circle cx="9" cy="7" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><circle cx="17.5" cy="8" r="2.5"/><path d="M15.5 12.5a5 5 0 0 1 5.8 4.9"/>',
  engranaje:
    '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1"/>',
  salir: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/>',
  menu: '<line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="18" x2="21" y2="18"/>',
  cerrar: '<line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>',
}
