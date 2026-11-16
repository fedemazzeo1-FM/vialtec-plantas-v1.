import { createClient } from 'npm:@supabase/supabase-js@2'
import ExcelJS from 'npm:exceljs@4.4.0'
import {
  construirWorkbookInformeMensual,
  fetchComparativoMesAnterior,
  fetchDatosInformeMensual,
  fetchDespachosPorObraDelMes,
  fetchResumenAnual,
  LISTA_TIPOS_PRODUCTO,
  usarCliente,
} from './plantas.bundle.js'
import { LOGO_EXCEL_BASE64 } from './logo.bundle.js'
import { armarContenido, nombresMes, panelesMensuales, URL_INFORME } from './armar.ts'
import { panelesPorMes, svgGraficoExcelAnual } from './graficos.ts'
import { svgAPng } from '../_shared/mail/rasterizar.ts'

// Informe mensual de Plantas por la bandeja de avisos de VT360 (16/11/2026). Reemplaza a la versión vieja, que leía
// las tablas del sistema anterior (pedidos, ingresos: vacías) y mandaba directo a Resend con un dominio sin verificar:
// nunca llegó a nadie.
// Lo llama pg_cron el día 1 a las 08:00 AR (job informe-produccion-vialtec) con el secreto de Vault
// (core_secreto_llamada). Lee con el MISMO código que Despachos → "Descargar informe mensual" (plantas.bundle.js,
// generado con scripts/armar-informe-mail.mjs), arma el contenido con la plantilla única (la dibuja
// notificaciones-enviar), un gráfico PNG en el cuerpo (cid) y el MISMO Excel adjunto; guarda los archivos en
// core_notificacion_archivos y anota el evento informe_plantas_mensual con core_informe_publicar (destinatarios =
// reglas del evento; un link "Abrir informe" por destinatario).
// Body opcional:
//   { "mes": "2026-10" }               otro mes (por defecto, el anterior al de hoy en Argentina)
//   { "test_email": "a@b" }            prueba: va solo a esa casilla (evento prueba_envio), marcada PRUEBA
//   { "dry_run": true }                arma todo y devuelve un resumen; no guarda nada ni manda mails
// Una corrida real por mes: si el informe de ese mes ya está en la bandeja, no se vuelve a generar.

const EVENTO = 'informe_plantas_mensual'
const ENTIDAD = 'informe_plantas'
const ZONA_AR = 'America/Argentina/Buenos_Aires'

const json = (cuerpo: unknown, status = 200) =>
  new Response(JSON.stringify(cuerpo), { status, headers: { 'Content-Type': 'application/json' } })

const aHex = (b: Uint8Array) => '\\x' + Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('')
const desdeBase64 = (t: string) => Uint8Array.from(atob(t), (c) => c.charCodeAt(0))

function mesPorDefecto(): { anio: number; mes: number } {
  const [a, m] = new Date().toLocaleDateString('en-CA', { timeZone: ZONA_AR }).split('-').map(Number)
  return m === 1 ? { anio: a - 1, mes: 12 } : { anio: a, mes: m - 1 }
}

Deno.serve(async (req: Request) => {
  const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
  const { data: secreto, error: errorSecreto } = await sb.rpc('core_secreto_llamada')
  if (errorSecreto || !secreto) return json({ ok: false, error: 'sin secreto de llamada' }, 500)
  if ((req.headers.get('x-informe-secret') ?? '') !== secreto) return new Response('Unauthorized', { status: 401 })

  const body = await req.json().catch(() => ({}))
  const testEmail: string | null = typeof body.test_email === 'string' ? body.test_email.trim().toLowerCase() : null
  if (testEmail && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(testEmail)) return json({ ok: false, error: 'test_email inválido' }, 400)
  const dryRun = body.dry_run === true
  let periodo = mesPorDefecto()
  if (body.mes != null) {
    const m = /^(\d{4})-(\d{2})$/.exec(String(body.mes))
    if (!m || +m[2] < 1 || +m[2] > 12) return json({ ok: false, error: 'mes inválido (AAAA-MM)' }, 400)
    periodo = { anio: +m[1], mes: +m[2] }
  }
  const { mesLabel, clave, claveAnterior } = nombresMes(periodo.anio, periodo.mes)

  try {
    if (!testEmail && !dryRun) {
      const { count, error } = await sb.from('core_notificaciones').select('id', { count: 'exact', head: true })
        .eq('evento', EVENTO).eq('entidad', ENTIDAD).eq('entidad_id', clave)
      if (error) throw new Error(`core_notificaciones: ${error.message}`)
      if (count) return json({ ok: true, mes: clave, ya_generado: true, mails: count })
    }

    const t0 = Date.now()
    usarCliente(sb)
    const generadoEl = new Date().toLocaleDateString('es-AR', { timeZone: ZONA_AR, day: '2-digit', month: '2-digit', year: 'numeric' })

    // Mismos datos que el Excel de Despachos; la serie del gráfico son los últimos 12 meses (cruza el año).
    const [informe, anteriorPorObra, anioPrevio] = await Promise.all([
      fetchDatosInformeMensual(clave),
      fetchDespachosPorObraDelMes(claveAnterior),
      periodo.mes < 12 ? fetchResumenAnual(`${periodo.anio - 1}-12`) : Promise.resolve({ filas: [] }),
    ])
    const filasAnio = informe.resumenAnual.filas
    const totalesMes = filasAnio[filasAnio.length - 1]
    const comparativo = await fetchComparativoMesAnterior(clave, totalesMes)
    // Sin los meses del principio que no tienen ningún dato (antes de 2026 el sistema no tiene registros): un mes
    // vacío se leería como "no hubo producción".
    const conDatos = (f: Record<string, unknown>) => LISTA_TIPOS_PRODUCTO.some((t: { total: string }) => Number(f[t.total]) > 0)
    const ultimos = [...anioPrevio.filas, ...filasAnio].slice(-12)
    const desde = ultimos.findIndex(conDatos)
    const serie = desde < 0 ? ultimos.slice(-1) : ultimos.slice(desde)

    const datos = {
      anio: periodo.anio, mes: periodo.mes, informe, comparativo, serie, generadoEl,
      despachosAnterior: anteriorPorObra.totalGeneral.despachos,
      tipos: LISTA_TIPOS_PRODUCTO,
      prueba: !!testEmail,
    }
    const grafico = panelesPorMes({
      titulo: 'Producción por mes',
      subtitulo: `Últimos 12 meses hasta ${mesLabel} · cada producto en su unidad`,
      paneles: panelesMensuales(datos),
    })
    const pngMensual = await svgAPng(grafico.svg)
    const libro = await construirWorkbookInformeMensual(informe, desdeBase64(LOGO_EXCEL_BASE64), {
      graficoAnual: (filas: Array<{ mes: string; hormigonM3: number; asfaltoTn: number }>) => svgAPng(svgGraficoExcelAnual(filas)),
    })
    const excel = new Uint8Array(await libro.xlsx.writeBuffer())
    const nombreExcel = `Informe Plantas prod. ${mesLabel.toUpperCase()}.xlsx`
    const cid = { mensual: `plantas-mensual-${clave}` }
    const contenido = armarContenido(datos, cid, { mensual: [grafico.ancho, grafico.alto] })
    const asunto = `${testEmail ? '[PRUEBA] ' : ''}Informe de Plantas · ${mesLabel}`

    if (dryRun)
      return json({
        ok: true, dry_run: true, mes: clave, asunto, ms: Date.now() - t0,
        kpis: contenido.kpis, mensaje: contenido.mensaje,
        secciones: contenido.secciones?.map((s) => [s.titulo, s.filas?.length, s.total]),
        serie: serie.map((s: { mes: string }) => s.mes),
        hojas: libro.worksheets.map((w: { name: string }) => w.name), archivo: nombreExcel,
        bytes: { grafico: pngMensual.length, excel: excel.length },
      })

    const archivos = [
      { nombre: `plantas-mensual-${clave}.png`, tipo: 'image/png', bytes: pngMensual, cid: cid.mensual },
      { nombre: nombreExcel, tipo: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', bytes: excel, cid: undefined },
    ]
    const adjuntos = []
    for (const a of archivos) {
      const { data, error } = await sb.from('core_notificacion_archivos').insert({ nombre: a.nombre, tipo: a.tipo, contenido: aHex(a.bytes) }).select('id').single()
      if (error) throw new Error(`core_notificacion_archivos: ${error.message}`)
      adjuntos.push({ archivo_id: data.id, nombre: a.nombre, tipo: a.tipo, ...(a.cid ? { cid: a.cid } : {}) })
    }

    const { data: enlaces, error: errorNotificar } = await sb.rpc('core_informe_publicar', {
      p_evento: testEmail ? 'prueba_envio' : EVENTO,
      p_asunto: asunto,
      p_datos: contenido,
      p_entidad: ENTIDAD,
      p_entidad_id: clave,
      p_dinamicos: testEmail ? { para: testEmail } : {},
      p_clave: testEmail ? `prueba:${ENTIDAD}:${clave}:${Date.now()}` : `${EVENTO}:${clave}`,
      p_adjuntos: adjuntos,
      p_informe: 'plantas_mensual',
      p_periodo: clave,
      p_archivos: adjuntos.map((a) => ({ ...a, rol: a.cid ? 'imagen' : 'excel' })),
      p_url_base: URL_INFORME,
    })
    if (errorNotificar) {
      // Sin mails anotados, los archivos no los usa nadie: se borran para no dejar basura.
      await sb.from('core_notificacion_archivos').delete().in('id', adjuntos.map((a) => a.archivo_id))
      throw new Error(`core_informe_publicar: ${errorNotificar.message}`)
    }
    return json({ ok: true, mes: clave, mails: enlaces?.length ?? 0, archivos: adjuntos.map((a) => a.archivo_id), ms: Date.now() - t0 })
  } catch (e) {
    console.error('informe-produccion', clave, e)
    return json({ ok: false, mes: clave, error: String(e) }, 500)
  }
})
