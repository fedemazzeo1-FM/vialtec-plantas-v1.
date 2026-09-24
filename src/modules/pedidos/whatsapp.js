// Helper de notificaciones WhatsApp (el "WppToast" del sistema legado —
// Logica sis. plantas v1.rtf §8 / v2.rtf §6): el sistema NUNCA envía por
// API. Arma un mensaje pre-armado y un link a wa.me — la UI muestra un
// toast con ese mensaje y un botón que abre el link en una pestaña nueva;
// el usuario elige el contacto en su WhatsApp y lo manda él mismo.
//
// `plantas_usuarios_roles` sigue sin columna de teléfono propia (memory/
// relevamiento-sistema-viejo.md, gap de Usuarios) — pero el sistema de flota
// (`flota_usuarios_email.telefono`) sí lo tiene para varios usuarios
// (2026-09-07, ver `flota.service.js#fetchTelefonoPorNombre()`). Cuando se
// puede resolver un destinatario CONCRETO y sin ambigüedad (el encargado que
// pidió, por nombre exacto) el caller pasa `telefono` como segundo argumento
// de `urlWhatsapp()` y arma wa.me/<telefono>?text=... directo a su chat
// personal; sin match, sigue cayendo a wa.me/?text=... (el usuario elige el
// contacto a mano) — nunca se envía a un número adivinado.
//
// Funciones puras, sin Supabase — no es un service (memory/conventions.md:
// los services son solo acceso a datos). Vive en el módulo Pedidos porque
// es lógica específica de sus 2 disparadores (crear/confirmar), no
// compartida con otro módulo.

function destinoLabel(pedido, obraNombre) {
  return pedido.tipo_pedido === 'venta' ? pedido.cliente_externo || 'cliente externo' : obraNombre || 'obra'
}

function unidad(pedido) {
  return pedido.tipo === 'hormigon' ? 'm³' : 'tn'
}

function materialLabel(pedido) {
  return pedido.tipo === 'hormigon' ? 'hormigón' : 'asfalto'
}

const DIAS = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado']

/** 'YYYY-MM-DD' → 'jueves 24/09/2026' (día de la semana ayuda a no confundir la fecha en el chat). */
function fechaLabel(fechaIso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(fechaIso || '')
  if (!m) return fechaIso || '—'
  const [, anio, mes, dia] = m
  const diaSemana = DIAS[new Date(Number(anio), Number(mes) - 1, Number(dia)).getDay()]
  return `${diaSemana} ${dia}/${mes}/${anio}`
}

/**
 * Cuerpo común a los 3 avisos: destino + cantidad, mezcla, fecha y los datos
 * opcionales del pedido (solo si están cargados, para no mandar líneas vacías).
 */
function lineasDetalle(pedido, { obraNombre, formulaNombre, conEncargado = false }) {
  const lineas = [
    `${destinoLabel(pedido, obraNombre)} — ${pedido.cantidad_solicitada} ${unidad(pedido)}`,
    `Mezcla: ${formulaNombre || '—'}`,
    `Fecha: ${fechaLabel(pedido.fecha_programada)}`,
  ]
  if (pedido.ubicacion) lineas.push(`Ubicación: ${pedido.ubicacion}`)
  if (conEncargado) lineas.push(`Solicitado por: ${pedido.encargado || '—'}`)
  if (pedido.observaciones) lineas.push(`Obs.: ${pedido.observaciones}`)
  return lineas
}

export function urlWhatsapp(mensaje, telefono) {
  const texto = encodeURIComponent(mensaje)
  return telefono ? `https://wa.me/${telefono}?text=${texto}` : `https://wa.me/?text=${texto}`
}

/**
 * Al crear un pedido (solicitado) — dirigido al plantista. `telefono`
 * (2026-09-08, pedido explícito de Federico: "todos los que hagan un
 * pedido, el toast debe ser para Daniel Natel") resuelve el link directo a
 * su chat — ver NOMBRE_PLANTISTA_AVISO_CREACION en usePedidos.js. Sin
 * telefono (lookup falló o no está cargado), cae a wa.me sin destinatario,
 * mismo criterio de respaldo que el resto de estos toasts.
 */
export function toastCrearPedido(pedido, { obraNombre, formulaNombre, telefono } = {}) {
  const mensaje = [
    `🔔 Nuevo pedido de ${materialLabel(pedido)}`,
    ...lineasDetalle(pedido, { obraNombre, formulaNombre, conEncargado: true }),
  ].join('\n')
  return { titulo: 'Avisar al plantista', mensaje, url: urlWhatsapp(mensaje, telefono) }
}

/**
 * Al confirmar (solicitado → confirmado) — dirigido al encargado que pidió.
 * `telefono` (opcional, ver flota.service.js#fetchTelefonoPorNombre) manda
 * el link directo a su chat personal en vez de abrir wa.me sin destinatario.
 */
export function toastConfirmarPedido(pedido, { obraNombre, formulaNombre, telefono } = {}) {
  const mensaje = [
    `✅ Tu pedido de ${materialLabel(pedido)} fue confirmado`,
    ...lineasDetalle(pedido, { obraNombre, formulaNombre }),
  ].join('\n')
  return { titulo: 'Avisar al encargado', mensaje, url: urlWhatsapp(mensaje, telefono) }
}

/**
 * Al confirmar un pedido de HORMIGÓN — mensaje adicional para el operador de
 * hormigón (en el legado va a un usuario hardcodeado "angel"/u12 — acá no
 * hardcodeamos ningún contacto puntual, el balancero/plantista elige el
 * destinatario real en WhatsApp). Incluye la mezcla (ej. "H-8") y quién lo
 * pidió, para que el operador sepa qué producir y a quién consultar.
 */
export function toastConfirmarHormigonOperador(pedido, { obraNombre, formulaNombre } = {}) {
  const mensaje = [
    '🧱 Hormigón confirmado para producción',
    ...lineasDetalle(pedido, { obraNombre, formulaNombre, conEncargado: true }),
  ].join('\n')
  return { titulo: 'Avisar al operador de hormigón', mensaje, url: urlWhatsapp(mensaje) }
}
