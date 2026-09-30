/*
 * Medición de rendimiento por pantalla — VialTec Plantas (2026-09-30).
 *
 * USO: abrir https://produccion.vialtec.app con sesión iniciada, pegar este
 * archivo completo en la consola de DevTools y ejecutar:
 *
 *     const r = await medirRendimiento()          // todas las pantallas
 *     const r = await medirRendimiento(['/bascula', '/stock?tab=proveedores'])
 *
 * Qué hace (sin tocar código de la app ni la base):
 *  - Envuelve window.fetch: supabase-js resuelve `fetch` en cada llamada
 *    ((...args) => fetch(...args)), así que todas sus requests pasan por acá.
 *  - Navega pantalla por pantalla con el router de la propia app (navegación
 *    SPA real, como un usuario que hace click en el menú) y espera a que la
 *    red quede quieta.
 *  - Por pantalla registra: requests, KB descargados (cuerpo decodificado,
 *    sin gzip), filas devueltas, requests duplicadas (mismo método+URL),
 *    "niveles en cadena" (profundidad del waterfall: 1 = todo en paralelo)
 *    y tiempo hasta red quieta (orientativo: depende de la red).
 *  - Mide aparte la carga en frío del "shell" (assets + bootstrap de sesión)
 *    con performance.getEntriesByType, sin interceptor.
 *
 * Limitaciones:
 *  - La navegación SPA reutiliza lo que la app ya tiene en memoria (stores):
 *    mide el costo de ENTRAR a la pantalla, no de un F5 sobre ella. Para el
 *    F5, recargar la pantalla y mirar `shell` + la pestaña Network.
 *  - Con la pestaña en segundo plano Chrome frena los timers: los tiempos se
 *    inflan, pero requests/KB/filas/niveles no cambian.
 *  - Los datos que se ven dependen del rol y la RLS del usuario logueado.
 */
;(function () {
  const PANTALLAS_POR_DEFECTO = [
    '/dashboard',
    '/pedidos',
    '/plan-semanal',
    '/bascula',
    '/despachos',
    '/stock?tab=actual',
    '/stock?tab=ingresos',
    '/stock?tab=proveedores',
    '/formulas',
    '/maestros?tab=encargados',
    '/maestros?tab=obras',
    '/simulador',
    '/usuarios?tab=usuarios',
    '/usuarios?tab=roles',
  ]

  const esAPI = (url) => /supabase\.co\/(rest|auth|storage|functions)\//.test(url)
  const limpiarURL = (url) => {
    const u = new URL(url)
    u.searchParams.delete('apikey')
    return u.pathname.replace('/rest/v1/', '') + (u.search ? decodeURIComponent(u.search) : '')
  }

  function instalarInterceptor() {
    if (window.__medicionFetchOriginal) return
    const original = window.fetch
    window.__medicionFetchOriginal = original
    window.__medicionRegistros = []
    window.__medicionEnVuelo = 0
    window.fetch = async function (input, init) {
      const url = typeof input === 'string' ? input : input.url
      if (!esAPI(url)) return original.apply(this, arguments)
      const metodo = (init?.method || (typeof input !== 'string' && input.method) || 'GET').toUpperCase()
      const reg = { url, metodo, inicio: performance.now(), fin: null, bytes: 0, filas: null, status: null }
      window.__medicionRegistros.push(reg)
      window.__medicionEnVuelo++
      try {
        const resp = await original.apply(this, arguments)
        reg.status = resp.status
        reg.contentRange = resp.headers.get('content-range')
        try {
          const buf = await resp.clone().arrayBuffer()
          reg.bytes = buf.byteLength
          if (buf.byteLength) {
            const json = JSON.parse(new TextDecoder().decode(buf))
            reg.filas = Array.isArray(json) ? json.length : 1
          } else {
            reg.filas = 0
          }
        } catch {
          /* cuerpo no JSON */
        }
        return resp
      } finally {
        reg.fin = performance.now()
        window.__medicionEnVuelo--
      }
    }
  }

  const esperar = (ms) => new Promise((r) => setTimeout(r, ms))

  async function esperarRedQuieta({ quietoMs = 1500, maxMs = 25000 } = {}) {
    const t0 = performance.now()
    let quietoDesde = null
    while (performance.now() - t0 < maxMs) {
      await esperar(200)
      if (window.__medicionEnVuelo === 0) {
        quietoDesde ??= performance.now()
        if (performance.now() - quietoDesde >= quietoMs) return
      } else {
        quietoDesde = null
      }
    }
  }

  /** Profundidad del waterfall: una request "depende" de otra si arrancó
   *  después de que la otra terminó. 1 = todo en paralelo. */
  function nivelesEnCadena(regs) {
    const ordenados = [...regs].sort((a, b) => a.inicio - b.inicio)
    const prof = new Map()
    for (const r of ordenados) {
      let max = 0
      for (const p of ordenados) {
        if (p === r || p.fin == null) continue
        if (p.fin <= r.inicio + 5) max = Math.max(max, prof.get(p) || 1)
      }
      prof.set(r, max + 1)
    }
    return Math.max(0, ...prof.values())
  }

  function resumir(pantalla, regs, ms) {
    const claves = regs.map((r) => `${r.metodo} ${limpiarURL(r.url)}`)
    const repetidas = claves.filter((c, i) => claves.indexOf(c) !== i)
    return {
      pantalla,
      requests: regs.length,
      kb: +(regs.reduce((a, r) => a + r.bytes, 0) / 1024).toFixed(1),
      filas: regs.reduce((a, r) => a + (r.filas || 0), 0),
      niveles: nivelesEnCadena(regs),
      duplicadas: repetidas.length,
      msHastaRedQuieta: Math.round(ms),
      detalle: regs.map((r) => ({
        req: `${r.metodo} ${limpiarURL(r.url)}`.slice(0, 220),
        kb: +(r.bytes / 1024).toFixed(1),
        filas: r.filas,
        status: r.status,
        inicio: Math.round(r.inicio),
        ms: r.fin ? Math.round(r.fin - r.inicio) : null,
      })),
      requestsDuplicadas: [...new Set(repetidas)],
    }
  }

  function medirShell() {
    const res = performance.getEntriesByType('resource')
    const assets = res.filter((r) => new URL(r.name).pathname.startsWith('/assets/'))
    const api = res.filter((r) => esAPI(r.name))
    return {
      assetsJsCss: assets.length,
      assetsKbTransferidos: +(assets.reduce((a, r) => a + (r.transferSize || 0), 0) / 1024).toFixed(1),
      assetsKbDecodificados: +(assets.reduce((a, r) => a + (r.decodedBodySize || 0), 0) / 1024).toFixed(1),
      requestsApiAntesDelScript: api.length,
    }
  }

  window.medirRendimiento = async function (pantallas = PANTALLAS_POR_DEFECTO) {
    const app = document.querySelector('#app')?.__vue_app__
    const router = app?.config.globalProperties.$router
    if (!router) throw new Error('No encontré el router de la app (¿estás en produccion.vialtec.app con sesión?)')

    const shell = medirShell()
    instalarInterceptor()
    const resultados = []
    for (const pantalla of pantallas) {
      // Entre dos rutas distintas la vista se monta de cero; con la misma
      // ruta y otra ?tab= (Stock, Maestros, Usuarios) se mide el cambio de
      // tab, que es lo que hace el usuario al clickearla.
      await esperarRedQuieta({ quietoMs: 800 })
      const desde = window.__medicionRegistros.length
      const t0 = performance.now()
      await router.push(pantalla).catch(() => {})
      await esperarRedQuieta()
      const regs = window.__medicionRegistros.slice(desde)
      const ultimoFin = Math.max(t0, ...regs.map((r) => r.fin || 0))
      resultados.push(resumir(pantalla, regs, ultimoFin - t0))
    }
    console.table(resultados.map(({ detalle, requestsDuplicadas, ...r }) => r))
    const salida = { fecha: new Date().toISOString(), shell, resultados }
    window.__medicionResultado = salida
    return salida
  }
})()
