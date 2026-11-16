// COPIA de vialtec-flota-v2/supabase/functions/_shared/mail/graficos.ts (commit a5d402a, 16/11/2026). No editar acá:
// los cambios van en Flota y se vuelven a copiar.
// Gráficos de los informes por mail, como SVG (después se pasan a PNG con rasterizar.ts). Sin dependencias.
// Se dibujan al doble del tamaño en que se muestran (1072 px → 536 px en el mail) para que se vean nítidos.
// Paleta validada (dataviz, 11/11/2026): violeta de marca #7B3A8E + lavanda #B07ACC (contraste, daltonismo y visión
// normal OK). Texto siempre en tinta/gris, nunca del color de la serie. Una sola escala por gráfico.

const ANCHO = 1072
const C = {
  fondo: '#FFFFFF',
  tinta: '#1E1E1B',
  suave: '#6E6C70',
  grilla: '#ECEAEE',
  eje: '#C9C6CC',
  serie1: '#7B3A8E',
  serie2: '#B07ACC',
}
const F = "font-family=\"Manrope\""

const esc = (t: unknown) => String(t ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]!)
export const numeroAR = (v: number, dec = 0) =>
  Number(v).toLocaleString('es-AR', { minimumFractionDigits: dec, maximumFractionDigits: dec })

/** Paso de eje redondo: 1, 2, 2,5, 5 o 10 × 10ⁿ. */
function pasoRedondo(valor: number): number {
  if (valor <= 0) return 1
  const base = 10 ** Math.floor(Math.log10(valor))
  return ([1, 2, 2.5, 5, 10].find((m) => m * base >= valor) ?? 10) * base
}

/** Barra con la punta de datos redondeada (4 px a tamaño de pantalla = 8 aquí) y la base recta sobre el eje. */
function barraV(x: number, y: number, w: number, h: number, color: string, redondear: boolean): string {
  if (h <= 0) return ''
  const r = redondear ? Math.min(8, h, w / 2) : 0
  if (!r) return `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${color}"/>`
  return `<path d="M${x},${y + h} V${y + r} Q${x},${y} ${x + r},${y} H${x + w - r} Q${x + w},${y} ${x + w},${y + r} V${y + h} Z" fill="${color}"/>`
}

function barraH(x: number, y: number, w: number, h: number, color: string): string {
  if (w <= 0) return ''
  const r = Math.min(8, w, h / 2)
  return `<path d="M${x},${y} H${x + w - r} Q${x + w},${y} ${x + w},${y + r} V${y + h - r} Q${x + w},${y + h} ${x + w - r},${y + h} H${x} Z" fill="${color}"/>`
}

function encabezado(titulo: string, subtitulo: string): string {
  return `<text x="48" y="70" ${F} font-size="34" font-weight="800" fill="${C.tinta}">${esc(titulo)}</text>
<text x="48" y="112" ${F} font-size="24" font-weight="400" fill="${C.suave}">${esc(subtitulo)}</text>`
}

function leyenda(items: Array<{ texto: string; color: string }>, y: number): string {
  let x = 48
  return items
    .map((it) => {
      const s = `<rect x="${x}" y="${y - 16}" width="20" height="20" rx="5" fill="${it.color}"/><text x="${x + 30}" y="${y}" ${F} font-size="22" font-weight="700" fill="${C.tinta}">${esc(it.texto)}</text>`
      x += 30 + it.texto.length * 12.5 + 36
      return s
    })
    .join('')
}

function marco(alto: number, contenido: string): string {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${ANCHO}" height="${alto}" viewBox="0 0 ${ANCHO} ${alto}">
<rect width="${ANCHO}" height="${alto}" rx="24" fill="${C.fondo}"/>
<rect x="1" y="1" width="${ANCHO - 2}" height="${alto - 2}" rx="23" fill="none" stroke="#E7E4EA" stroke-width="2"/>
${contenido}
</svg>`
}

export type MesApilado = { etiqueta: string; a: number; b: number; destacado?: boolean }

/** Barras apiladas por mes (ej. litros de cisterna propia + externos), con el total arriba de cada barra. */
export function barrasApiladasPorMes(o: {
  titulo: string
  subtitulo: string
  serieA: string
  serieB: string
  meses: MesApilado[]
  unidad: string
}): { svg: string; ancho: number; alto: number } {
  const alto = 640
  const x0 = 120
  const x1 = ANCHO - 48
  const yTop = 230
  const yBase = alto - 84
  const mayor = Math.max(1, ...o.meses.map((m) => m.a + m.b))
  const paso = Math.max(1, pasoRedondo((mayor * 1.12) / 4))
  const max = paso * 4
  const y = (v: number) => yBase - ((yBase - yTop) * v) / max
  const grilla = Array.from({ length: 5 }, (_, i) => {
    const v = paso * i
    return `<line x1="${x0}" x2="${x1}" y1="${y(v)}" y2="${y(v)}" stroke="${i ? C.grilla : C.eje}" stroke-width="2"/>
<text x="${x0 - 16}" y="${y(v) + 8}" ${F} font-size="20" text-anchor="end" fill="${C.suave}">${numeroAR(v)}</text>`
  }).join('')
  const n = Math.max(1, o.meses.length)
  const banda = (x1 - x0) / n
  const w = Math.min(84, banda * 0.56)
  const barras = o.meses
    .map((m, i) => {
      const cx = x0 + banda * (i + 0.5)
      const x = cx - w / 2
      const hA = yBase - y(m.a)
      const hB = yBase - y(m.b)
      const gap = hA > 0 && hB > 0 ? 4 : 0
      const total = m.a + m.b
      return `${barraV(x, yBase - hA, w, hA, C.serie1, hB <= 0)}
${barraV(x, yBase - hA - gap - hB, w, hB, C.serie2, true)}
<text x="${cx}" y="${y(total) - 16 - gap}" ${F} font-size="${m.destacado ? 24 : 21}" font-weight="${m.destacado ? 800 : 700}" text-anchor="middle" fill="${m.destacado ? C.tinta : C.suave}">${numeroAR(total)}</text>
<text x="${cx}" y="${yBase + 40}" ${F} font-size="22" font-weight="${m.destacado ? 800 : 400}" text-anchor="middle" fill="${m.destacado ? C.tinta : C.suave}">${esc(m.etiqueta)}</text>`
    })
    .join('')
  const vacio = !o.meses.some((m) => m.a + m.b > 0)
    ? `<text x="${(x0 + x1) / 2}" y="${(yTop + yBase) / 2}" ${F} font-size="24" text-anchor="middle" fill="${C.suave}">Sin despachos en el período</text>`
    : ''
  const svg = marco(
    alto,
    `${encabezado(o.titulo, o.subtitulo)}
${leyenda([{ texto: o.serieA, color: C.serie1 }, { texto: o.serieB, color: C.serie2 }], 170)}${vacio}
<text x="${x0 - 16}" y="${yTop - 24}" ${F} font-size="18" text-anchor="end" fill="${C.suave}">${esc(o.unidad)}</text>
${grilla}${barras}`,
  )
  return { svg, ancho: ANCHO, alto }
}

export type FilaHorizontal = { etiqueta: string; valor: number; texto: string; nota?: string }

/** Barras horizontales ordenadas (ej. litros por tipo de equipo), con el valor y una nota a la derecha. */
export function barrasHorizontales(o: { titulo: string; subtitulo: string; filas: FilaHorizontal[] }): { svg: string; ancho: number; alto: number } {
  const fila = 58
  const yTop = 160
  const alto = yTop + Math.max(1, o.filas.length) * fila + 44
  const xEtiqueta = 48
  const x0 = 372
  const x1 = ANCHO - 360
  const mayor = Math.max(1, ...o.filas.map((f) => f.valor))
  const filas = o.filas
    .map((f, i) => {
      const yc = yTop + i * fila + fila / 2
      const w = ((x1 - x0) * f.valor) / mayor
      const etiqueta = f.etiqueta.length > 26 ? f.etiqueta.slice(0, 25) + '…' : f.etiqueta
      return `<text x="${xEtiqueta}" y="${yc + 8}" ${F} font-size="22" font-weight="700" fill="${C.tinta}">${esc(etiqueta)}</text>
${barraH(x0, yc - 15, w, 30, C.serie1)}
<text x="${x0 + w + 14}" y="${yc + 8}" ${F} font-size="22" font-weight="800" fill="${C.tinta}">${esc(f.texto)}</text>
${f.nota ? `<text x="${ANCHO - 48}" y="${yc + 8}" ${F} font-size="20" text-anchor="end" fill="${C.suave}">${esc(f.nota)}</text>` : ''}`
    })
    .join('')
  const svg = marco(
    alto,
    `${encabezado(o.titulo, o.subtitulo)}
<line x1="${x0}" x2="${x0}" y1="${yTop}" y2="${yTop + o.filas.length * fila}" stroke="${C.eje}" stroke-width="2"/>
${filas}${o.filas.length ? '' : `<text x="${x0 + 16}" y="${yTop + fila / 2 + 8}" ${F} font-size="22" fill="${C.suave}">Sin despachos en el mes</text>`}`,
  )
  return { svg, ancho: ANCHO, alto }
}

export type MesSeries = { etiqueta: string; valores: number[]; destacado?: boolean }

/** Barras apiladas por mes con N series (13/11/2026, informe de gastos: preventivo, correctivo, sin OT), total arriba.
 * Colores en orden: violeta de marca, lavanda y ámbar (el mismo ámbar del "Sin OT" del Home). */
export function barrasApiladasSeries(o: {
  titulo: string
  subtitulo: string
  series: string[]
  meses: MesSeries[]
  unidad: string
  formato?: (v: number) => string
}): { svg: string; ancho: number; alto: number } {
  const colores = [C.serie1, C.serie2, '#C98A1B', '#6E6C70']
  const fmt = o.formato ?? ((v: number) => numeroAR(v))
  const alto = 640
  const x0 = 120
  const x1 = ANCHO - 48
  const yTop = 230
  const yBase = alto - 84
  const totales = o.meses.map((m) => m.valores.reduce((s, v) => s + (v > 0 ? v : 0), 0))
  const mayor = Math.max(1, ...totales)
  const paso = Math.max(1, pasoRedondo((mayor * 1.12) / 4))
  const max = paso * 4
  const y = (v: number) => yBase - ((yBase - yTop) * v) / max
  const grilla = Array.from({ length: 5 }, (_, i) => {
    const v = paso * i
    return `<line x1="${x0}" x2="${x1}" y1="${y(v)}" y2="${y(v)}" stroke="${i ? C.grilla : C.eje}" stroke-width="2"/>
<text x="${x0 - 16}" y="${y(v) + 8}" ${F} font-size="20" text-anchor="end" fill="${C.suave}">${esc(fmt(v))}</text>`
  }).join('')
  const n = Math.max(1, o.meses.length)
  const banda = (x1 - x0) / n
  const w = Math.min(84, banda * 0.56)
  const barras = o.meses
    .map((m, i) => {
      const cx = x0 + banda * (i + 0.5)
      const x = cx - w / 2
      let base = yBase
      const alturas = m.valores.map((v) => (v > 0 ? yBase - y(v) : 0))
      const ultima = alturas.reduce((u, h, j) => (h > 0 ? j : u), -1)
      const tramos = alturas
        .map((h, j) => {
          if (h <= 0) return ''
          const gap = base < yBase ? 3 : 0
          const tramo = barraV(x, base - gap - h, w, h, colores[j % colores.length], j === ultima)
          base = base - gap - h
          return tramo
        })
        .join('\n')
      return `${tramos}
<text x="${cx}" y="${base - 16}" ${F} font-size="${m.destacado ? 24 : 21}" font-weight="${m.destacado ? 800 : 700}" text-anchor="middle" fill="${m.destacado ? C.tinta : C.suave}">${esc(fmt(totales[i]))}</text>
<text x="${cx}" y="${yBase + 40}" ${F} font-size="22" font-weight="${m.destacado ? 800 : 400}" text-anchor="middle" fill="${m.destacado ? C.tinta : C.suave}">${esc(m.etiqueta)}</text>`
    })
    .join('')
  const vacio = !totales.some((t) => t > 0)
    ? `<text x="${(x0 + x1) / 2}" y="${(yTop + yBase) / 2}" ${F} font-size="24" text-anchor="middle" fill="${C.suave}">Sin datos en el período</text>`
    : ''
  const svg = marco(
    alto,
    `${encabezado(o.titulo, o.subtitulo)}
${leyenda(o.series.map((s, j) => ({ texto: s, color: colores[j % colores.length] })), 170)}${vacio}
<text x="${x0 - 16}" y="${yTop - 24}" ${F} font-size="18" text-anchor="end" fill="${C.suave}">${esc(o.unidad)}</text>
${grilla}${barras}`,
  )
  return { svg, ancho: ANCHO, alto }
}
