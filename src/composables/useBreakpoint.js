// Detección de viewport mobile/desktop — helper transversal (memory/conventions.md:
// lógica compartida entre módulos/layouts va acá, no duplicada).
//
// Breakpoint: 768px (mismo valor que el prefijo `md:` de Tailwind — así el
// switch de layout en JS y cualquier clase `md:` en templates quedan
// consistentes, sin dos fuentes de verdad para "qué es mobile").
//
// `matchMedia` reactivo (no `window.innerWidth` polleado): se suscribe una
// sola vez por instancia y se actualiza solo en el resize/rotate real del
// dispositivo, sin listener de `resize` a mano ni recálculo en cada pixel.
import { onBeforeUnmount, ref } from 'vue'

export const BREAKPOINT_MOBILE_PX = 768

// Snapshot no-reactivo, usable fuera de un componente (ej. router/index.js,
// LoginView.vue antes de navegar) — a diferencia de useBreakpoint() de abajo,
// no se suscribe a cambios de viewport, solo responde "¿es mobile ahora?" en
// el momento puntual en que se lo llama (memory: redirección por defecto en
// mobile, 2026-09-16). Mismo breakpoint, una sola fuente de verdad.
export function esPantallaMobile() {
  return window.matchMedia(`(max-width: ${BREAKPOINT_MOBILE_PX - 1}px)`).matches
}

export function useBreakpoint() {
  const query = window.matchMedia(`(max-width: ${BREAKPOINT_MOBILE_PX - 1}px)`)
  const esMobile = ref(query.matches)

  function actualizar(e) {
    esMobile.value = e.matches
  }

  // Safari <14 no soporta addEventListener acá — addListener es el fallback
  // legacy, deprecated pero inofensivo de tener como belt-and-suspenders.
  if (query.addEventListener) query.addEventListener('change', actualizar)
  else query.addListener(actualizar)

  onBeforeUnmount(() => {
    if (query.removeEventListener) query.removeEventListener('change', actualizar)
    else query.removeListener(actualizar)
  })

  return { esMobile }
}
