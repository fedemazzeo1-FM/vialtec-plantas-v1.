// Gráficos del informe mensual de Plantas por mail (16/11/2026). SVG → PNG con ../_shared/mail/rasterizar.ts.
// Mismo estilo que los de Flota (../_shared/mail/graficos.ts: tamaño 1072 px mostrado a 536, Manrope, marco
// redondeado, paleta violeta de marca), pero REGLA DE PLANTAS: asfalto, hormigón y mezcla cemento nunca se suman ni
// comparten barra. Por eso un panel por tipo, cada uno con su escala y su unidad (no barras apiladas).

import { numeroAR } from '../_shared/mail/graficos.ts'

const ANCHO = 1072
const C = {
  fondo: '#FFFFFF',
  tinta: '#1E1E1B',
  suave: '#6E6C70',
  grilla: '#ECEAEE',
  eje: '#C9C6CC',
  marca: '#7B3A8E',
  lavanda: '#B07ACC',
}
const F = 'font-family="Manrope"'
const esc = (t: unknown) => String(t ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]!)

function pasoRedondo(valor: number): number {
  if (valor <= 0) return 1
  const base = 10 ** Math.floor(Math.log10(valor))
  return ([1, 2, 2.5, 5, 10].find((m) => m * base >= valor) ?? 10) * base
}

function barraV(x: number, y: number, w: number, h: number, color: string): string {
  if (h <= 0) return ''
  const r = Math.min(8, h, w / 2)
  return `<path d="M${x},${y + h} V${y + r} Q${x},${y} ${x + r},${y} H${x + w - r} Q${x + w},${y} ${x + w},${y + r} V${y + h} Z" fill="${color}"/>`
}

export type PanelMensual = {
  titulo: string // 'Asfalto'
  unidad: string // 'tn'
  decimales: number
  meses: Array<{ etiqueta: string; valor: number; destacado?: boolean }>
}

/** Producción por mes: un panel por tipo de producto, uno debajo del otro, cada uno con su escala. */
export function panelesPorMes(o: { titulo: string; subtitulo: string; paneles: PanelMensual[] }): { svg: string; ancho: number; alto: number } {
  const altoPanel = 330
  const yInicio = 150
  const alto = yInicio + Math.max(1, o.paneles.length) * altoPanel + 20
  const x0 = 120
  const x1 = ANCHO - 48
  const partes: string[] = []
  o.paneles.forEach((p, k) => {
    const yTitulo = yInicio + k * altoPanel + 30
    const yTop = yTitulo + 60
    const yBase = yInicio + (k + 1) * altoPanel - 70
    const mayor = Math.max(1, ...p.meses.map((m) => m.valor))
    const paso = Math.max(1, pasoRedondo((mayor * 1.15) / 3))
    const max = paso * 3
    const y = (v: number) => yBase - ((yBase - yTop) * v) / max
    partes.push(`<text x="48" y="${yTitulo}" ${F} font-size="26" font-weight="800" fill="${C.tinta}">${esc(p.titulo)}</text>
<text x="${x0 - 16}" y="${yTop - 22}" ${F} font-size="18" text-anchor="end" fill="${C.suave}">${esc(p.unidad)}</text>`)
    for (let i = 0; i <= 3; i++) {
      const v = paso * i
      partes.push(`<line x1="${x0}" x2="${x1}" y1="${y(v)}" y2="${y(v)}" stroke="${i ? C.grilla : C.eje}" stroke-width="2"/>
<text x="${x0 - 16}" y="${y(v) + 7}" ${F} font-size="18" text-anchor="end" fill="${C.suave}">${numeroAR(v)}</text>`)
    }
    const banda = (x1 - x0) / Math.max(1, p.meses.length)
    const w = Math.min(64, banda * 0.56)
    p.meses.forEach((m, i) => {
      const cx = x0 + banda * (i + 0.5)
      const h = yBase - y(m.valor)
      partes.push(barraV(cx - w / 2, yBase - h, w, h, m.destacado ? C.marca : C.lavanda))
      if (m.valor > 0)
        partes.push(`<text x="${cx}" y="${y(m.valor) - 12}" ${F} font-size="${m.destacado ? 20 : 16}" font-weight="${m.destacado ? 800 : 600}" text-anchor="middle" fill="${m.destacado ? C.tinta : C.suave}">${numeroAR(m.valor, m.destacado ? p.decimales : 0)}</text>`)
      partes.push(`<text x="${cx}" y="${yBase + 34}" ${F} font-size="20" font-weight="${m.destacado ? 800 : 400}" text-anchor="middle" fill="${m.destacado ? C.tinta : C.suave}">${esc(m.etiqueta)}</text>`)
    })
    if (!p.meses.some((m) => m.valor > 0))
      partes.push(`<text x="${(x0 + x1) / 2}" y="${(yTop + yBase) / 2}" ${F} font-size="22" text-anchor="middle" fill="${C.suave}">Sin despachos en el período</text>`)
  })
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${ANCHO}" height="${alto}" viewBox="0 0 ${ANCHO} ${alto}">
<rect width="${ANCHO}" height="${alto}" rx="24" fill="${C.fondo}"/>
<rect x="1" y="1" width="${ANCHO - 2}" height="${alto - 2}" rx="23" fill="none" stroke="#E7E4EA" stroke-width="2"/>
<text x="48" y="70" ${F} font-size="34" font-weight="800" fill="${C.tinta}">${esc(o.titulo)}</text>
<text x="48" y="112" ${F} font-size="24" fill="${C.suave}">${esc(o.subtitulo)}</text>
${partes.join('\n')}
</svg>`
  return { svg, ancho: ANCHO, alto }
}

/**
 * Gráfico de la hoja "Resumen anual" del Excel, en SVG (en el navegador lo dibuja canvas:
 * generarImagenGraficoAnual de excel-informe-mensual.js). Mismas medidas (900×380 al doble), mismos colores y
 * mismo contenido: barras lado a lado de hormigón (m³) y asfalto (tn) por mes, nunca sumadas.
 */
export function svgGraficoExcelAnual(filas: Array<{ mes: string; hormigonM3: number; asfaltoTn: number }>): string {
  const ESC = 2
  const ANCHO_X = 900
  const ALTO_X = 380
  const M = { top: 55, right: 30, bottom: 55, left: 70 }
  const ancho = ANCHO_X - M.left - M.right
  const altoG = ALTO_X - M.top - M.bottom
  const COLOR_H = '#DDD6FE'
  const COLOR_A = '#7C3AED'
  const GRIS = '#374151'
  const maxValor = Math.max(1, ...filas.map((f) => Math.max(f.hormigonM3 || 0, f.asfaltoTn || 0))) * 1.15
  const baseY = M.top + altoG
  const yDe = (v: number) => baseY - (v / maxValor) * altoG
  const p: string[] = []
  p.push(`<rect width="${ANCHO_X}" height="${ALTO_X}" fill="#FFFFFF"/>`)
  p.push(`<text x="${M.left}" y="24" ${F} font-size="15" font-weight="700" fill="${GRIS}">Producción mensual</text>`)
  let xl = ANCHO_X - M.right - 220
  for (const [color, texto] of [[COLOR_H, 'Hormigón (m³)'], [COLOR_A, 'Asfalto (tn)']]) {
    p.push(`<rect x="${xl}" y="12" width="12" height="12" fill="${color}"/><text x="${xl + 16}" y="22" ${F} font-size="11" fill="${GRIS}">${texto}</text>`)
    xl += 110
  }
  for (let i = 0; i <= 4; i++) {
    const v = (maxValor * i) / 4
    p.push(`<line x1="${M.left}" x2="${M.left + ancho}" y1="${yDe(v)}" y2="${yDe(v)}" stroke="#E5E7EB" stroke-width="1"/>
<text x="${M.left - 8}" y="${yDe(v) + 3}" ${F} font-size="10" text-anchor="end" fill="#9CA3AF">${Math.round(v).toLocaleString('es-AR')}</text>`)
  }
  const banda = ancho / Math.max(1, filas.length)
  const w = Math.min(28, banda * 0.32)
  filas.forEach((f, i) => {
    const cx = M.left + banda * (i + 0.5)
    for (const [k, valor, color] of [[-1, f.hormigonM3 || 0, COLOR_H], [1, f.asfaltoTn || 0, COLOR_A]] as const) {
      const h = (valor / maxValor) * altoG
      const x = k < 0 ? cx - w - 2 : cx + 2
      if (h > 0) p.push(`<rect x="${x}" y="${baseY - h}" width="${w}" height="${h}" fill="${color}"/>`)
      if (valor > 0) p.push(`<text x="${x + w / 2}" y="${baseY - h - 4}" ${F} font-size="9" text-anchor="middle" fill="${GRIS}">${Math.round(valor).toLocaleString('es-AR')}</text>`)
    }
    p.push(`<text x="${cx}" y="${baseY + 18}" ${F} font-size="11" text-anchor="middle" fill="${GRIS}">${esc(f.mes.slice(0, 3))}</text>`)
  })
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${ANCHO_X * ESC}" height="${ALTO_X * ESC}" viewBox="0 0 ${ANCHO_X} ${ALTO_X}">${p.join('\n')}</svg>`
}
