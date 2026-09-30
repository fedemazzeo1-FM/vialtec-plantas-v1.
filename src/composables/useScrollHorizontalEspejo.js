// Barras de scroll horizontal "espejo" para tablas anchas (2026-09-30, pedido
// de Federico: en Báscula había que bajar hasta la última fila para llegar a
// la barra horizontal, incómodo con mouse tradicional en Windows).
//
// Dos barras sincronizadas con el contenedor real de la tabla:
//  - superior: siempre arriba de la tabla (solo si hay overflow);
//  - inferior flotante: fija al borde inferior de la ventana mientras la
//    tabla está en pantalla pero su propia barra (al pie) todavía no.
// `sticky bottom-0` no sirve acá: el <main> de DesktopLayout tiene
// overflow-x-auto, lo que lo vuelve el contenedor de scroll de referencia y
// el sticky nunca se pega a la ventana — por eso la flotante es `fixed` con
// posición/ancho copiados del contenedor.
import { nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'

export function useScrollHorizontalEspejo() {
  const contenedor = ref(null) // div overflow-x-auto que envuelve la <table>
  const barraSuperior = ref(null)
  const barraFlotante = ref(null)

  const estado = reactive({
    hayOverflow: false,
    anchoContenido: 0,
    flotanteVisible: false,
    left: 0,
    width: 0,
  })

  // Sin candado: solo se copia la posición a las barras que difieren, así
  // el scroll "rebote" que dispara cada asignación llega con el mismo valor
  // y no hace nada (no hay loop). Un candado con requestAnimationFrame se
  // trababa en pestañas en segundo plano (Chrome pausa rAF).
  function sincronizarDesde(origen) {
    if (!origen) return
    const x = origen.scrollLeft
    for (const el of [contenedor.value, barraSuperior.value, barraFlotante.value]) {
      if (el && el !== origen && Math.abs(el.scrollLeft - x) > 0.5) el.scrollLeft = x
    }
  }

  function medir() {
    const el = contenedor.value
    if (!el) return
    estado.anchoContenido = el.scrollWidth
    estado.hayOverflow = el.scrollWidth > el.clientWidth + 1
    const rect = el.getBoundingClientRect()
    const altoVentana = window.innerHeight
    // Visible si la tabla ocupa parte de la pantalla y su borde inferior
    // (donde está la barra nativa) quedó por debajo de la ventana.
    estado.flotanteVisible = estado.hayOverflow && rect.top < altoVentana - 40 && rect.bottom > altoVentana
    estado.left = rect.left
    estado.width = rect.width
  }

  let resizeObserver = null
  onMounted(() => {
    window.addEventListener('scroll', medir, { passive: true, capture: true })
    window.addEventListener('resize', medir, { passive: true })
    resizeObserver = new ResizeObserver(medir)
    observar(contenedor.value)
  })

  // El contenedor puede aparecer/desaparecer (VTable alterna tabla/cards
  // según breakpoint) — se re-observa cada vez que cambia.
  function observar(el) {
    if (!resizeObserver) return
    resizeObserver.disconnect()
    if (el) {
      resizeObserver.observe(el)
      if (el.firstElementChild) resizeObserver.observe(el.firstElementChild)
    }
    nextTick(medir)
  }
  watch(contenedor, observar)

  // Mientras está oculta (display:none) la barra flotante ignora scrollLeft:
  // al mostrarse se alinea con la posición real de la tabla.
  watch(
    () => [estado.flotanteVisible, estado.hayOverflow],
    () =>
      nextTick(() => {
        const x = contenedor.value?.scrollLeft ?? 0
        if (barraFlotante.value) barraFlotante.value.scrollLeft = x
        if (barraSuperior.value) barraSuperior.value.scrollLeft = x
      })
  )

  onBeforeUnmount(() => {
    window.removeEventListener('scroll', medir, { capture: true })
    window.removeEventListener('resize', medir)
    resizeObserver?.disconnect()
  })

  return { contenedor, barraSuperior, barraFlotante, estado, sincronizarDesde, medir }
}
