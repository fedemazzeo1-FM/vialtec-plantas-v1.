// COPIA de vialtec-flota-v2/supabase/functions/_shared/mail/rasterizar.ts (commit a5d402a, 16/11/2026). No editar acá:
// los cambios van en Flota y se vuelven a copiar.
// SVG → PNG para las imágenes de los informes (Edge Functions, Deno). Motor resvg (wasm) y tipografía Manrope (la de
// los sistemas, subconjunto latino, SIL Open Font License), los dos con versión fija desde jsdelivr: se bajan la
// primera vez que se usan en cada arranque de la función. Si no se pueden bajar, el informe falla con el motivo y no
// se anota nada en la bandeja (se puede volver a correr).
import { initWasm, Resvg } from 'npm:@resvg/resvg-wasm@2.6.2'

const WASM_URL = 'https://cdn.jsdelivr.net/npm/@resvg/resvg-wasm@2.6.2/index_bg.wasm'
const FUENTES_URL = [400, 700, 800].map((w) => `https://cdn.jsdelivr.net/fontsource/fonts/manrope@5.1.1/latin-${w}-normal.ttf`)

let listo: Promise<Uint8Array[]> | null = null
let wasmIniciado = false

async function bajar(url: string): Promise<Response> {
  const res = await fetch(url)
  if (!res.ok) throw new Error(`No se pudo bajar ${url} (${res.status})`)
  return res
}

function preparar(): Promise<Uint8Array[]> {
  if (!listo) {
    listo = (async () => {
      const [wasm, ...fuentes] = await Promise.all([wasmIniciado ? null : bajar(WASM_URL), ...FUENTES_URL.map(bajar)])
      if (wasm) {
        await initWasm(wasm)
        wasmIniciado = true
      }
      return Promise.all(fuentes.map(async (r) => new Uint8Array(await (r as Response).arrayBuffer())))
    })()
    listo.catch(() => (listo = null))
  }
  return listo
}

export async function svgAPng(svg: string): Promise<Uint8Array> {
  const fontBuffers = await preparar()
  const r = new Resvg(svg, { font: { fontBuffers, loadSystemFonts: false, defaultFontFamily: 'Manrope' } })
  const png = r.render().asPng()
  r.free()
  return png
}
