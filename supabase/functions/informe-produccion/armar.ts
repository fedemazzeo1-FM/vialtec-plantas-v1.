// Contenido del mail del informe mensual de Plantas (16/11/2026). Parte pura: recibe los datos ya leídos con el
// mismo código que Despachos → "Descargar informe mensual" (plantas.bundle.js) y no lee nada.
// Reglas (memory/business-rules.md):
//   · Asfalto (tn), hormigón (m³) y mezcla cemento (tn) NUNCA se suman entre sí: una tarjeta, una fila y un panel
//     de gráfico por tipo, cada uno en su unidad.
//   · El total sale de plantas_pedidos.cantidad_despachada (remito final), no de Báscula.
// La plantilla del mail es la única de VT360 (la dibuja notificaciones-enviar de Flota): acá solo se arma el
// "Contenido" (mismos campos que vialtec-flota-v2/supabase/functions/_shared/mail/plantilla.ts).

import { numeroAR } from '../_shared/mail/graficos.ts'
import type { PanelMensual } from './graficos.ts'

// deno-lint-ignore no-explicit-any
type J = any

type Kpi = { etiqueta: string; valor: string; unidad?: string; variacion?: number | null; mejorSiSube?: boolean | null; comparacion?: string }
type Seccion = { titulo: string; texto?: string; columnas?: Array<{ texto: string; derecha?: boolean }>; filas?: string[][]; total?: string[]; nota?: string }
export type Contenido = {
  tono?: string
  etiqueta?: string
  titulo: string
  mensaje?: string
  preencabezado?: string
  kpis?: Kpi[]
  imagenes?: Array<{ cid: string; alt: string; ancho: number; alto: number }>
  secciones?: Seccion[]
  accion?: { texto: string; url: string }
  nota?: string
  prueba?: boolean
  sistema?: 'plantas'
}

export const URL_INFORME = 'https://equipos2.vialtec.app/informe/' // página "Abrir informe" de VT360 (vive en Flota)
const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']
const MESES_CORTOS = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic']
const mayuscula = (t: string) => t.charAt(0).toUpperCase() + t.slice(1)
const DECIMALES = 1

export function nombresMes(anio: number, mes: number) {
  const ant = mes === 1 ? { anio: anio - 1, mes: 12 } : { anio, mes: mes - 1 }
  return {
    mesLabel: `${mayuscula(MESES[mes - 1])} ${anio}`,
    mesNombre: MESES[mes - 1],
    anteriorNombre: MESES[ant.mes - 1],
    clave: `${anio}-${String(mes).padStart(2, '0')}`,
    claveAnterior: `${ant.anio}-${String(ant.mes).padStart(2, '0')}`,
  }
}

export type Datos = {
  anio: number
  mes: number
  informe: J // fetchDatosInformeMensual(mes): lo mismo que arma el Excel
  comparativo: J[] // fetchComparativoMesAnterior(mes, totales del mes): filas por tipo, como el Home
  despachosAnterior: number // pedidos despachados del mes anterior
  serie: Array<J> // últimos 12 meses (filas de fetchResumenAnual: { mes: 'Octubre 2026', asfaltoTn, … })
  tipos: J[] // LISTA_TIPOS_PRODUCTO
  // fetchAnaliticaProveedoresDetalle del mes (Stock → Analítica de proveedores). Sin comparar con el mes anterior
  // (Federico, 16/11).
  proveedores: Proveedor[]
  generadoEl: string
  prueba: boolean
}

type Proveedor = { proveedor: string; viajes: number; totalTn: number; insumos: Array<{ material: string; viajes: number; toneladas: number }> }

/** Ingresos de proveedores, como la pantalla Stock → Analítica de proveedores: totales, por proveedor y por material.
 *  El detalle de cada proveedor va solo al Excel (Federico, 16/11: el mail se acercaba al límite de Gmail, ~102 KB). */
export function seccionesProveedores(lista: Proveedor[], mesNombre: string): { kpis: Kpi[]; secciones: Seccion[] } {
  const tn = lista.reduce((a, x) => a + x.totalTn, 0)
  const viajes = lista.reduce((a, x) => a + x.viajes, 0)
  const kpis: Kpi[] = [
    { etiqueta: 'Ingresos de proveedores', valor: numeroAR(tn, DECIMALES), unidad: 'tn', comparacion: `${numeroAR(lista.length)} proveedores` },
    { etiqueta: 'Viajes de proveedores', valor: numeroAR(viajes), comparacion: `en ${mesNombre}` },
  ]
  if (!lista.length)
    return { kpis, secciones: [{ titulo: 'Ingresos de proveedores', texto: `No hubo ingresos de proveedores en ${mesNombre}.` }] }

  const porMaterial = new Map<string, { viajes: number; tn: number }>()
  for (const x of lista) for (const i of x.insumos) {
    const acc = porMaterial.get(i.material) ?? { viajes: 0, tn: 0 }
    acc.viajes += i.viajes
    acc.tn += i.toneladas
    porMaterial.set(i.material, acc)
  }
  const columnas = (primera: string) => [{ texto: primera }, { texto: 'Viajes', derecha: true }, { texto: 'Toneladas', derecha: true }]
  const total = ['Total', numeroAR(viajes), numeroAR(tn, DECIMALES)]
  return {
    kpis,
    secciones: [
      {
        titulo: 'Ingresos por proveedor',
        columnas: columnas('Proveedor'),
        filas: lista.map((x) => [x.proveedor, numeroAR(x.viajes), numeroAR(x.totalTn, DECIMALES)]),
        total,
        nota: `Ingresos de ${mesNombre} cargados en Plantas (báscula y manuales, sin anulados), en toneladas. El detalle de cada proveedor por material está en el Excel (hoja Analítica de Proveedores).`,
      },
      {
        titulo: 'Ingresos por material',
        columnas: columnas('Material'),
        filas: [...porMaterial.entries()].sort((a, b) => b[1].tn - a[1].tn).map(([m, x]) => [m, numeroAR(x.viajes), numeroAR(x.tn, DECIMALES)]),
        total,
      },
    ],
  }
}

const cant = (v: unknown, tipo: J) => `${numeroAR(Number(v) || 0, DECIMALES)} ${tipo.unidadLabel}`
const cantO = (v: unknown, tipo: J) => ((Number(v) || 0) > 0 ? cant(v, tipo) : '—')
const hay = (totales: J, tipo: J) => (Number(totales?.[tipo.total]) || 0) > 0

function listaNatural(partes: string[]): string {
  if (partes.length <= 1) return partes[0] ?? ''
  return `${partes.slice(0, -1).join(', ')} y ${partes[partes.length - 1]}`
}

/** Tabla de destinos (obras o clientes): una columna por tipo con algo en la tabla. */
function tablaDestinos(titulo: string, filas: J[], subtotal: J, tipos: J[], encabezado: string, nota?: string): Seccion {
  const conDatos = tipos.filter((t) => hay(subtotal, t))
  return {
    titulo,
    columnas: [{ texto: encabezado }, { texto: 'Desp.', derecha: true }, ...conDatos.map((t) => ({ texto: `${t.nombre} (${t.unidadLabel})`, derecha: true }))],
    filas: filas.map((r) => [
      r.nombre,
      String(r.cantidadDespachos),
      ...conDatos.map((t) => (hay(r, t) ? numeroAR(Number(r[t.total]), DECIMALES) : '—')),
    ]),
    total: ['Total', String(subtotal.despachos), ...conDatos.map((t) => numeroAR(Number(subtotal[t.total]) || 0, DECIMALES))],
    nota,
  }
}

export function armarContenido(d: Datos, cid: { mensual: string }, medidas: { mensual: [number, number] }): Contenido {
  const { mesLabel, mesNombre, anteriorNombre } = nombresMes(d.anio, d.mes)
  const dp = d.informe.despachosPorObra
  const total = dp.totalGeneral
  const tiposMes = d.tipos.filter((t) => hay(total, t))

  // Tarjetas: una por tipo (actual vs. mes anterior completo, como el comparativo del Home) + pedidos despachados.
  const kpis: Kpi[] = d.comparativo.map((f) => ({
    etiqueta: f.tipo.nombre,
    valor: numeroAR(f.actual, DECIMALES),
    unidad: f.tipo.unidadLabel,
    variacion: f.anterior > 0 ? (f.actual - f.anterior) / f.anterior : null,
    mejorSiSube: true,
    comparacion: f.anterior > 0 ? `vs. ${cant(f.anterior, f.tipo)} en ${anteriorNombre}` : `sin producción en ${anteriorNombre}`,
  }))
  kpis.push({
    etiqueta: 'Pedidos despachados',
    valor: numeroAR(total.despachos),
    variacion: d.despachosAnterior > 0 ? (total.despachos - d.despachosAnterior) / d.despachosAnterior : null,
    mejorSiSube: true,
    comparacion: `vs. ${numeroAR(d.despachosAnterior)} en ${anteriorNombre}`,
  })

  const secciones: Seccion[] = []
  secciones.push({
    titulo: `Total de ${mesNombre}`,
    columnas: [{ texto: 'Producto' }, { texto: 'Obras propias', derecha: true }, { texto: 'Ventas externas', derecha: true }, { texto: 'Total', derecha: true }],
    filas: tiposMes.map((t) => [t.nombre, cantO(dp.subtotalInterno[t.total], t), cantO(dp.subtotalExterno[t.total], t), cant(total[t.total], t)]),
    nota: 'Cada producto en su unidad: asfalto, hormigón y mezcla cemento no se suman entre sí. Fuente: cantidad despachada de cada pedido (remito final).',
  })
  if (dp.internos.length)
    secciones.push(tablaDestinos('Despachos por obra', dp.internos, dp.subtotalInterno, d.tipos, 'Obra'))
  if (dp.externos.length)
    secciones.push(tablaDestinos('Ventas externas', dp.externos, dp.subtotalExterno, d.tipos, 'Cliente'))

  const insumos = d.informe.consumoInsumos
  if (insumos.filas.length) {
    const top = insumos.filas.slice(0, 10)
    secciones.push({
      titulo: 'Consumo de insumos',
      columnas: [{ texto: 'Material' }, { texto: 'Toneladas', derecha: true }],
      filas: top.map((f: J) => [f.fueraDeCatalogo ? `${f.material} (revisar fórmula)` : f.material, numeroAR(f.toneladas, DECIMALES)]),
      total: ['Total', numeroAR(insumos.totalTn, DECIMALES)],
      nota: `Fórmula × cantidad despachada de los pedidos del mes (sin agua ni purgue).${insumos.filas.length > top.length ? ` Los ${insumos.filas.length - top.length} restantes y los proveedores, en el Excel.` : ''}`,
    })
  }

  const prov = seccionesProveedores(d.proveedores, mesNombre)
  kpis.push(...prov.kpis)
  secciones.push(...prov.secciones)

  const resumenTipos = listaNatural(tiposMes.map((t) => `${cant(total[t.total], t)} de ${t.nombre.toLowerCase()}`))
  return {
    tono: 'principal',
    sistema: 'plantas', // color, ícono y nombre de Plantas en la plantilla (16/11/2026)
    etiqueta: 'Informe mensual',
    titulo: mesLabel,
    mensaje: tiposMes.length
      ? `${mayuscula(mesNombre)} cerró con ${resumenTipos} en ${numeroAR(total.despachos)} pedidos despachados. El detalle por obra y las pesadas están en el Excel adjunto.`
      : `En ${mesNombre} no hubo despachos.`,
    preencabezado: tiposMes.map((t) => `${cant(total[t.total], t)} de ${t.nombre.toLowerCase()}`).join(' · ') || 'Sin despachos en el mes',
    kpis,
    imagenes: [{ cid: cid.mensual, alt: `Gráfico: producción por mes hasta ${mesLabel}, un panel por producto`, ancho: medidas.mensual[0], alto: medidas.mensual[1] }],
    secciones,
    accion: { texto: 'Abrir informe', url: URL_INFORME }, // la URL real (una por destinatario) la pone core_informe_publicar
    nota: `Datos al ${d.generadoEl}. Se genera el día 3 de cada mes, con el mes anterior cerrado.`,
    prueba: d.prueba,
  }
}

/** Paneles del gráfico: un panel por tipo con producción en los últimos 12 meses. */
export function panelesMensuales(d: Datos): PanelMensual[] {
  return d.tipos
    .filter((t) => d.serie.some((s) => hay(s, t)))
    // Mismo orden que las tarjetas (LISTA_TIPOS_PRODUCTO): asfalto, hormigón, mezcla cemento.
    .map((t) => ({
      titulo: `${t.nombre} (${t.unidadLabel})`,
      unidad: t.unidadLabel,
      decimales: DECIMALES,
      meses: d.serie.map((s, i) => {
        const nombre = String(s.mes).split(' ')[0].toLowerCase()
        const m = MESES.indexOf(nombre)
        const enero = m === 0 && i > 0
        return {
          etiqueta: `${MESES_CORTOS[m]}${enero ? ` ${String(s.mes).slice(-2)}` : ''}`,
          valor: Number(s[t.total]) || 0,
          destacado: i === d.serie.length - 1,
        }
      }),
    }))
}
